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
            var buffer = new GtkSource.Buffer(null);
            buffer.language = GtkSource.LanguageManager.get_default().guess_language(item.name, item.mime);
            buffer.highlight_syntax = true;
            var view = new GtkSource.View.with_buffer(buffer);
            view.show_line_numbers = true;
            view.editable = false;
            view.monospace = true;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            string[] encodings = {"Automatic", "UTF-8", "UTF-16LE", "UTF-16BE", "WINDOWS-1252", "ISO-8859-1"};
            var encoding = new Gtk.DropDown.from_strings(encodings);
            encoding.tooltip_text = _("Text Encoding");
            var status = new Gtk.Label("");
            status.wrap = true;
            Callback update = () => {
                try {
                    string selected = encodings[encoding.selected];
                    if (selected == "Automatic") {
                        if (count >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) selected = "UTF-16LE";
                        else if (count >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) selected = "UTF-16BE";
                        else selected = ((string)bytes).validate((ssize_t)count) ? "UTF-8" : "WINDOWS-1252";
                    }
                    if (!selected.has_prefix("UTF-16"))
                        for (size_t i = 0; i < count; i++)
                            if (bytes[i] == 0)
                                throw new FileError.UNSUPPORTED("This file contains binary data");
                    size_t read, written;
                    string text = GLib.convert((string)bytes, (ssize_t)count, "UTF-8", selected, out read, out written);
                    buffer.text = text;
                    status.label = selected + (item.bytes > count ? " · Preview limited to 256 KiB" : "");
                }
                catch (Error e) { buffer.text = ""; status.label = e.message + " · Select another encoding if appropriate"; }
            };
            encoding.notify["selected"].connect(() => update());
            update();
            box.append(encoding);
            box.append(status);
            var scroll = new Gtk.ScrolledWindow();
            scroll.set_child(view);
            scroll.vexpand = true;
            box.append(scroll);
            return box;
        }
    }
    public class ImagePreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("image/");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if (item.bytes > 256 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("This image exceeds the preview size limit");
            if (item.mime == "image/gif" || item.mime == "image/webp" || item.mime == "image/avif" || item.mime == "image/heif" || item.mime == "image/heic") {
                try {
                    var animation = yield PreviewSandbox.run(item, "image-animation", {}, token);
                    return new AnimatedImageView(animation, token);
                }
                catch (IOError.CANCELLED e) { throw e; }
                catch (Error e) {} // Static files and unavailable animation decoders use the image provider.
            }
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
            // GTK retains the controls and paintable. Only bounded raw RGBA and
            // PCM from the isolated GStreamer decoder enter this process.
            var media = IsolatedPlayback.open(item,token);
            media.set_volume(0.5);
            if (item.mime.has_prefix("audio/"))
            {
                var audio = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
                var icon = new Gtk.Image.from_icon_name("audio-x-generic-symbolic");
                icon.pixel_size = 96;
                icon.vexpand = true;
                audio.append(icon);
                var name = new Gtk.Label(item.name);
                name.wrap = true;
                name.selectable = true;
                audio.append(name);
                var controls = new Gtk.MediaControls(media);
                audio.append(controls);
                add_error(audio,media);
                add_metadata.begin(audio, item, token);
                if (metadata != null && metadata.state("autoplay-media", "false") == "true")
                    media.play();
                return audio;
            }
            var video = new Gtk.Video.for_media_stream(media);
            video.autoplay = metadata != null && metadata.state("autoplay-media", "false") == "true";
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            video.vexpand = true;
            box.append(video);
            add_error(box,media);
            add_metadata.begin(box, item, token);
            return box;
        }
        static void add_error(Gtk.Box box,Gtk.MediaStream media){
            var label=new Gtk.Label("");label.wrap=true;label.visible=false;
            media.notify["error"].connect(()=>{if(media.get_error()!=null){label.label=_("Media preview unavailable: ")+media.get_error().message;label.visible=true;}});
            if(media.get_error()!=null){label.label=_("Media preview unavailable: ")+media.get_error().message;label.visible=true;}
            box.append(label);
        }
        async void add_metadata(Gtk.Box box, FileItem item, Cancellable token)
        {
            try {
                var fields = yield RichMetadata.load(item, token);
                token.set_error_if_cancelled();
                box.append(RichMetadata.presentation(fields));
            }
            catch (Error e) {
                if (!token.is_cancelled()) {
                    var label = new Gtk.Label(_("Metadata unavailable: ") + e.message);
                    label.wrap = true;
                    box.append(label);
                }
            }
        }
    }
    public class PreviewPane : Gtk.Box {
        MetadataStore? metadata;
        Cancellable token = new Cancellable();
        Gee.ArrayList<PreviewProvider> providers = new Gee.ArrayList<PreviewProvider>();
        uint generation;
        public PreviewPane(MetadataStore? metadata = null)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 8);
            width_request = 280;
            this.metadata = metadata;
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
        public async void show_item(owned FileItem item, bool remote_requested = false)
        {
            cancel();
            token = new Cancellable();
            var pending = token;
            uint epoch = generation;
            var label = new Gtk.Label(item.name);
            label.wrap = true;
            append(label);
            File? staging = null;
            try {
                var cloud = yield CloudFiles.get_default().query(item.file, pending);
                if (cloud.online_only) {
                    if (!remote_requested) {
                        var download = new Gtk.Button.with_label(_("Download Cloud Preview"));
                        download.clicked.connect(() => show_item.begin(item, true)); append(download); return;
                    }
                    uint limit = 16;
                    if (metadata != null) uint.try_parse(metadata.state("remote-preview-limit-mib", "16"), out limit);
                    var progress = new Gtk.ProgressBar(); progress.show_text = true; append(progress);
                    var file = yield CloudFiles.get_default().materialize(item.file, (uint64)limit.clamp(1, 1024) * 1024 * 1024, pending, (fraction, message) => { progress.fraction = fraction < 0 ? 0 : fraction; progress.text = message; });
                    remove(progress);
                    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.LOW, pending);
                    item = new FileItem(file, info);
                }
                if (!item.file.is_native()) {
                    string policy = metadata == null ? "On Request" : metadata.state("remote-preview-policy", "On Request");
                    if (policy == "Never")
                        throw new FileError.UNSUPPORTED("Remote previews are disabled in Preferences");
                    if (policy != "Automatic" && !remote_requested) {
                        var download = new Gtk.Button.with_label(_("Download Preview"));
                        download.clicked.connect(() => show_item.begin(item, true));
                        append(download);
                        return;
                    }
                    uint limit = 16;
                    if (metadata != null) uint.try_parse(metadata.state("remote-preview-limit-mib", "16"), out limit);
                    var limits = new ImportPolicy();
                    limits.maximum_bytes = (uint64)limit.clamp(1, 1024) * 1024 * 1024;
                    limits.timeout_seconds = 30;
                    staging = File.new_for_path(DirUtils.make_tmp("majoris-remote-preview-XXXXXX"));
                    var local = yield ChooserImport.download(item.file, pending, staging, limits);
                    pending.set_error_if_cancelled();
                    var info = yield local.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, pending);
                    info.set_content_type(item.mime);
                    info.set_display_name(item.name);
                    item = new FileItem(local, info);
                    var retained = staging;
                    pending.cancelled.connect(() => OperationManager.remove_tree.begin(retained, new Cancellable()));
                }
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
                if (staging != null)
                    try { yield OperationManager.remove_tree(staging, new Cancellable()); } catch (Error ignored) {}
                if (!pending.is_cancelled() && epoch == generation)
                {
                    var message = new Gtk.Label(_("Preview unavailable\n") + e.message);
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
