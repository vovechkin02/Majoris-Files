namespace MajorisFiles {
    public interface PreviewProvider : Object {
        public abstract bool supports(FileItem item);
        public abstract async Gtk.Widget render(FileItem item, Cancellable token) throws Error;
    }
    public class TextPreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("text/") || item.mime == "application/json" || item.mime == "application/xml";
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            var input = yield item.file.read_async(Priority.LOW, token);
            uint8[] bytes = new uint8[256 * 1024 + 1];
            size_t count;
            try {
                yield input.read_all_async(bytes[0 : bytes.length - 1], Priority.LOW, token, out count);
            }
            catch(Error e) {
                try {
                    yield input.close_async(Priority.LOW, null);
                }
                catch(Error ignored) {}
                throw e;
            }
            yield input.close_async(Priority.LOW, null);
            bytes[count] = 0;
            string text = ((string)bytes).make_valid();
            var view = new Gtk.TextView();
            view.editable = false;
            view.monospace = true;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.buffer.text = text + (item.bytes > count ? "\n\n[Preview limited to 256 KiB]" : "");
            var scroll = new Gtk.ScrolledWindow();
            scroll.set_child(view);
            return scroll;
        }
    }
    public class ImagePreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("image/");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if (item.bytes > 64 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("This image exceeds the preview size limit");
            var bytes = yield PreviewSandbox.run(item, "image", {"0"}, token);
            return new ImageView(item, Gdk.Texture.from_bytes(bytes), token);
        }
    }
    public class MediaPreview : Object, PreviewProvider {
        MetadataStore? metadata;
        public MediaPreview(MetadataStore? metadata = null)
        {
            this.metadata = metadata;
        }
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("audio/") || item.mime.has_prefix("video/");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            // GtkMediaFile delegates playback to GTK's installed GStreamer media backend.
            var media = Gtk.MediaFile.for_file(item.file);
            media.set_volume(0.5);
            var video = new Gtk.Video.for_media_stream(media);
            video.autoplay = metadata != null && metadata.state("autoplay-media", "false") == "true";
            return video;
        }
    }
    public class PreviewPane : Gtk.Box {
        Cancellable token = new Cancellable();
        Gee.ArrayList<PreviewProvider> providers = new Gee.ArrayList<PreviewProvider>();
        uint generation;
        public PreviewPane(MetadataStore? metadata = null)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);
            width_request = 280;
            providers.add(new ImagePreview());
            providers.add(new MarkdownPreview());
            providers.add(new TextPreview());
            providers.add(new MediaPreview(metadata));
            providers.add(new PdfPreview());
            providers.add(new ArchivePreview());
            providers.add(new FontPreview());
            providers.add(new OfficePreview());
        }
        public void cancel()
        {
            token.cancel();
            generation++;
            clear();
        }
        void clear()
        {
            while (get_first_child() != null)
            {
                var child = get_first_child();
                if (child is Gtk.Video)
                {
                    var stream = ((Gtk.Video)child).media_stream;
                    if (stream != null)
                        stream.pause();
                }
                remove(child);
            }
        }
        public async void show_item(FileItem item)
        {
            cancel();
            token = new Cancellable();
            var pending = token;
            uint epoch = generation;
            var label = new Gtk.Label(item.name);
            label.wrap = true;
            append(label);
            try {
                if (!item.file.is_native())
                    throw new FileError.UNSUPPORTED("Remote previews require a local copy");
                foreach (var provider in providers)
                    if (provider.supports(item))
                    {
                        var widget = yield provider.render(item, pending);
                        if (pending.is_cancelled() || epoch != generation)
                            return;
                        widget.vexpand = true;
                        append(widget);
                        return;
                    }
                append(new Gtk.Image.from_gicon(item.info.get_icon()));
                append(new Gtk.Label(Paths.size(item.bytes) + "\n" + item.mime));
            }
            catch (Error e) {
                if (!pending.is_cancelled() && epoch == generation)
                {
                    var message = new Gtk.Label("Preview unavailable\n" + e.message);
                    message.wrap = true;
                    append(message);
                }
            }
        }
        ~PreviewPane()
        {
            token.cancel();
        }
    }
}
