namespace MajorisFiles {
    // Files controls access and transactions. ImageKit owns all image interpretation.
    public class ImageKitIntegration : Object {
        static ImageKitIntegration? instance;
        ImageKit.DecoderRegistry registry = new ImageKit.DecoderRegistry();
        ImageKit.ThumbnailService thumbnails = new ImageKit.ThumbnailService();
        public static ImageKitIntegration get_default() {
            if (instance == null) instance = new ImageKitIntegration();
            return instance;
        }
        public static bool is_candidate(FileItem item) {
            if (item.directory) return false;
            if (item.mime.has_prefix("image/")) return true;
            if (item.mime != "application/octet-stream") return false;
            // Some GVfs backends omit content-type. GIO's MIME database provides
            // only a candidate hint; ImageKit still verifies the actual content.
            bool uncertain;
            return ContentType.get_mime_type(ContentType.guess(item.name, null, out uncertain)).has_prefix("image/");
        }
        public static ImageKit.ImageSource source(FileItem item) throws Error {
            if (!item.file.is_native() || Paths.is_symlink(item.info) || item.info.get_file_type() != FileType.REGULAR)
                throw new IOError.NOT_SUPPORTED("Image access requires an authorized local regular file");
            return new ImageKit.ImageSource(item.file);
        }
        public static ImageKit.DecodeOptions preview_options() {
            var options = new ImageKit.DecodeOptions();
            options.preview_size = 512;
            options.raw_preview_first = true;
            options.raw_preview_only = false; // ImageKit may develop RAWs without an embedded preview.
            return options;
        }
        // A small bounded set of physical-pixel variants, within ImageKit's public range.
        public static int thumbnail_edge(int logical_edge, int scale) {
            int64 pixels = (int64)logical_edge.clamp(1, 1024) * scale.clamp(1, 16);
            foreach (int edge in new int[] {32, 64, 128, 256, 512, 1024})
                if (pixels <= edge) return edge;
            return 1024;
        }
        public async Bytes thumbnail(FileItem item, int edge, Cancellable token) throws Error {
            var result = yield thumbnails.generate(source(item), edge, token);
            token.set_error_if_cancelled();
            return result;
        }
        public async Gee.HashMap<string, string> metadata(FileItem item, Cancellable token) throws Error {
            // MetadataPage queries the provider independently. A broken provider must
            // not suppress image facts for an already available local file.
            var cloud = CloudFiles.get_default().cached(item.file);
            if (cloud != null && cloud.online_only)
                throw new IOError.NOT_SUPPORTED("Download this image before reading its metadata");
            var probe = yield registry.inspect(source(item), token);
            token.set_error_if_cancelled();
            var fields = new Gee.HashMap<string, string>();
            fields["Dimensions"] = "%d × %d".printf(probe.width, probe.height);
            fields["Image Format"] = probe.mime;
            fields["Bit Depth"] = probe.depth.to_string();
            if (probe.source_bit_depth > 0) fields["Source Bit Depth"] = probe.source_bit_depth.to_string();
            fields["Pages"] = probe.pages.to_string();
            fields["Alpha"] = probe.has_alpha ? _("Yes") : _("No");
            fields["HDR Source"] = probe.hdr ? _("Yes") : _("No");
            fields["RAW Source"] = probe.raw ? _("Yes") : _("No");
            fields["Animated"] = probe.animated ? _("Yes") : _("No");
            fields["Colour Managed"] = probe.color_managed ? _("Yes") : _("No");
            if (probe.color_diagnostic != "") fields["Colour Profile Status"] = probe.color_diagnostic;
            if (probe.animated) {
                fields["Frame Duration (ms)"] = probe.frame_duration_ms.to_string();
                fields["Loop Count"] = probe.loop_count.to_string();
            }
            // This is ImageKit's decoded metadata, never EXIF parsing in Files.
            var parser = new Json.Parser();
            parser.load_from_data(probe.metadata);
            if (parser.get_root().get_node_type() == Json.NodeType.OBJECT) {
                var object = parser.get_root().get_object();
                append_metadata(fields, object, "", 0);
            }
            return fields;
        }
        static void append_metadata(Gee.HashMap<string, string> fields, Json.Object object, string prefix, int depth) {
            if (depth > 3) return;
            foreach (var key in object.get_members()) {
                var node = object.get_member(key);
                // Human-readable scalar facts only; never expose internal JSON documents.
                if (key == "") continue;
                if (prefix == "" && key in new string[] {"format", "width", "height", "bit-depth", "source-bit-depth", "effective-bit-depth", "alpha", "raw", "hdr", "pages", "animated", "loop-count", "backend"}) continue;
                string label = key.replace("-", " ").replace("_", " ");
                label = prefix + label.substring(0, 1).up() + label.substring(1);
                if (key == "latitude" || key == "longitude" || key == "altitude") label = "GPS " + label;
                if (node.get_node_type() == Json.NodeType.OBJECT) {
                    if (key == "colour" || key == "raw-details" || key == "image-details")
                        append_metadata(fields, node.get_object(), key == "colour" ? "Colour Profile: " : key == "raw-details" ? "RAW: " : "Image: ", depth + 1);
                } else if (node.get_node_type() == Json.NodeType.VALUE) {
                    if (node.get_value_type() == typeof(string)) fields[label] = node.get_string();
                    else if (node.get_value_type() == typeof(bool)) fields[label] = node.get_boolean() ? _("Yes") : _("No");
                    else fields[label] = Json.to_string(node, false);
                }
            }
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/preview-image.ui")]
    public class ImageKitPreview : Gtk.Box {
        private bool template_disposing;
        [GtkChild] public unowned ImageKit.ImageView image_view;
        [GtkChild] private unowned Gtk.ScrolledWindow toolbar_scroll;
        [GtkChild] private unowned Gtk.Label description;
        Cancellable? token;
        ulong cancelled;
        uint request_generation;
        static construct { ImageKit.ImageView.register_type(); }
        construct {
            var builder = new Gtk.Builder.from_resource("/com/majoris/files/ui/preview-controls.ui");
            var toolbar = new Majoris.Ui.Toolbar();
            toolbar.compact = true; toolbar.divider = true;
            var actions = toolbar.append_group();
            var zoom_out = (Gtk.Button)builder.get_object("control_1");
            var zoom_in = (Gtk.Button)builder.get_object("control_2");
            var next = (Gtk.Button)builder.get_object("control_3");
            var previous = (Gtk.Button)builder.get_object("control_4");
            var rotate = (Gtk.Button)builder.get_object("control_5");
            var fit = (Gtk.Button)builder.get_object("control_6");
            var play = (Gtk.Button)builder.get_object("control_7");
            var actual = (Gtk.Button)builder.get_object("control_actual");
            actions.append_control(PreviewButtons.connect(zoom_out, () => image_view.zoom_out()));
            actions.append_control(PreviewButtons.connect(zoom_in, () => image_view.zoom_in()));
            actions.append_control(PreviewButtons.connect(fit, () => image_view.fit_to_view()));
            actions.append_control(PreviewButtons.connect(actual, () => image_view.actual_size()));
            actions.append_control(PreviewButtons.connect(rotate, () => image_view.rotate_clockwise()));
            actions.append_control(PreviewButtons.connect(play, () => { if (image_view.playing) image_view.pause(); else image_view.play(); }));
            actions.append_control(PreviewButtons.connect(previous, () => change_page.begin(-1)));
            actions.append_control(PreviewButtons.connect(next, () => change_page.begin(1)));
            toolbar_scroll.child = toolbar;
            Callback update_controls = () => {
                bool ready = image_view.document != null;
                zoom_in.sensitive = ready && image_view.zoom < image_view.maximum_zoom;
                zoom_out.sensitive = ready && image_view.zoom > image_view.minimum_zoom;
                fit.sensitive = actual.sensitive = rotate.sensitive = ready;
                play.visible = image_view.animated;
                play.icon_name = image_view.playing ? "media-playback-pause-symbolic" : "media-playback-start-symbolic";
                next.visible = previous.visible = ready && !image_view.animated && image_view.page_count > 1;
                previous.sensitive = image_view.current_page > 0;
                next.sensitive = image_view.current_page + 1 < image_view.page_count;
                description.label = image_view.error_message != "" ? image_view.error_message :
                    image_view.warning != "" ? image_view.warning : image_view.presentation_diagnostic;
                description.visible = description.label != "";
            };
            image_view.notify.connect((property) => update_controls());
            image_view.transformed.connect(() => update_controls());
            update_controls();
        }
        async void change_page(int delta) {
            try { yield image_view.set_page(image_view.current_page + delta, token); }
            catch (Error e) { if (token != null && !token.is_cancelled()) { description.label = e.message; description.visible = true; } }
        }
        public async void load(FileItem item, Cancellable pending) throws Error {
            if (token != null && cancelled != 0) token.disconnect(cancelled);
            uint epoch = ++request_generation;
            token = pending;
            // Cancellation can come from a worker thread; GTK operations stay on its context.
            weak ImageKitPreview self = this;
            cancelled = pending.cancelled.connect(() => {
                Idle.add(() => { if (self != null && !self.template_disposing && self.request_generation == epoch) self.image_view.clear(); return Source.REMOVE; });
            });
            yield image_view.load_source(ImageKitIntegration.source(item), ImageKitIntegration.preview_options(), pending);
            pending.set_error_if_cancelled();
            if (template_disposing || request_generation != epoch) throw new IOError.CANCELLED("Image selection replaced");
            image_view.accessible_description = item.name;
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                request_generation++;
                if (token != null && cancelled != 0) { token.disconnect(cancelled); cancelled = 0; }
                image_view.clear();
                dispose_template(typeof(ImageKitPreview));
            }
            base.dispose();
        }
    }
}
