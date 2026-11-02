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
            var box = new TextPreviewWidget(); var buffer = box.buffer;
            buffer.language = GtkSource.LanguageManager.get_default().guess_language(item.name, item.mime);
            string[] encodings = {"Automatic", "UTF-8", "UTF-16LE", "UTF-16BE", "WINDOWS-1252", "ISO-8859-1"};
            var encoding = box.encoding; var status = box.status;
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
            var box = new MediaPreviewWidget();
            bool audio = item.mime.has_prefix("audio/");
            box.icon.visible = box.name_label.visible = box.controls.visible = audio;
            box.video.visible = !audio;
            if (audio) {
                box.spacing = 12; box.name_label.label = item.name; box.controls.media_stream = media;
                if (metadata != null && metadata.state("autoplay-media", "false") == "true") media.play();
            } else {
                box.video.media_stream = media;
                box.video.autoplay = metadata != null && metadata.state("autoplay-media", "false") == "true";
            }
            add_error(box.error_label, media);
            add_metadata.begin(box, item, token);
            return box;
        }
        static void add_error(Gtk.Label label,Gtk.MediaStream media){
            media.notify["error"].connect(()=>{if(media.get_error()!=null){label.label=_("Media preview unavailable: ")+media.get_error().message;label.visible=true;}});
            if(media.get_error()!=null){label.label=_("Media preview unavailable: ")+media.get_error().message;label.visible=true;}
        }
        async void add_metadata(MediaPreviewWidget box, FileItem item, Cancellable token)
        {
            try {
                var fields = yield RichMetadata.load(item, token);
                token.set_error_if_cancelled();
                box.append(RichMetadata.presentation(fields));
            }
            catch (Error e) {
                if (!token.is_cancelled()) {
                    box.metadata_error.label = _("Metadata unavailable: ") + e.message; box.metadata_error.visible = true;
                }
            }
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/preview.ui")]
    public class PreviewPane : Gtk.Box {
        private bool template_disposing;
        [GtkChild] private unowned Gtk.Button request_button;
        [GtkChild] private unowned Gtk.ProgressBar download_progress;
        [GtkChild] private unowned Gtk.Label unavailable_label;
        [GtkChild] private unowned Gtk.Box fallback;
        [GtkChild] private unowned Gtk.Image fallback_icon;
        [GtkChild] private unowned Gtk.Label fallback_info;
        FileItem? requested_item;
        bool request_connected;
        [GtkChild] private unowned Gtk.Box content_box;
        [GtkChild] private unowned Gtk.Label title_label;
        MetadataStore? metadata;
        Cancellable token = new Cancellable();
        Gee.ArrayList<PreviewProvider> providers = new Gee.ArrayList<PreviewProvider>();
        uint generation;
        public PreviewPane(MetadataStore? metadata = null)
        {
            Object();
            configure(metadata);
        }
        public void configure(MetadataStore? metadata) {
            if (!request_connected) {
                request_connected = true;
                request_button.clicked.connect(() => { if (requested_item != null) show_item.begin(requested_item, true); });
            }
            this.metadata = metadata;
            providers.clear();
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
            title_label.visible = false;
            request_button.visible = download_progress.visible = unavailable_label.visible = fallback.visible = false;
            requested_item = null;
            download_progress.fraction = 0; download_progress.text = "";
            while (content_box.get_first_child() != null)
            {
                var child = content_box.get_first_child();
                if (child is Gtk.Video)
                {
                    var stream = ((Gtk.Video)child).media_stream;
                    if (stream != null)
                        stream.pause();
                }
                content_box.remove(child);
            }
        }
        public async void show_item(owned FileItem item, bool remote_requested = false)
        {
            cancel();
            token = new Cancellable();
            var pending = token;
            uint epoch = generation;
            title_label.label = item.name; title_label.visible = true; requested_item = item;
            File? staging = null;
            try {
                var cloud = yield CloudFiles.get_default().query(item.file, pending);
                if (cloud.online_only) {
                    if (!remote_requested) {
                        request_button.label = _("Download Cloud Preview"); request_button.visible = true; return;
                    }
                    uint limit = 16;
                    if (metadata != null) uint.try_parse(metadata.state("remote-preview-limit-mib", "16"), out limit);
                    var progress = download_progress; progress.visible = true;
                    var file = yield CloudFiles.get_default().materialize(item.file, (uint64)limit.clamp(1, 1024) * 1024 * 1024, pending, (fraction, message) => { if (pending == token && epoch == generation) { progress.fraction = fraction < 0 ? 0 : fraction; progress.text = message; } });
                    progress.visible = false;
                    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.LOW, pending);
                    item = new FileItem(file, info);
                }
                if (!item.file.is_native()) {
                    string policy = metadata == null ? "On Request" : metadata.state("remote-preview-policy", "On Request");
                    if (policy == "Never")
                        throw new FileError.UNSUPPORTED("Remote previews are disabled in Preferences");
                    if (policy != "Automatic" && !remote_requested) {
                        request_button.label = _("Download Preview"); request_button.visible = true;
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
                        content_box.append(widget);
                        return;
                    }
                fallback_icon.set_from_gicon(item.info.get_icon());
                fallback_info.label = Paths.size(item.bytes) + "\n" + item.mime; fallback.visible = true;
            }
            catch (Error e) {
                if (staging != null)
                    try { yield OperationManager.remove_tree(staging, new Cancellable()); } catch (Error ignored) {}
                if (!pending.is_cancelled() && epoch == generation)
                {
                    unavailable_label.label = _("Preview unavailable\n") + e.message; unavailable_label.visible = true;
                }
            }
        }
        ~PreviewPane()
        {
            token.cancel();
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                if (token != null) token.cancel();
                dispose_template(typeof(PreviewPane));
            }
            base.dispose();
        }
    }
}
