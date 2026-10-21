namespace MajorisFiles {
    public class RichMetadata : Object {
        public static async Gee.HashMap<string, string> load(FileItem item, Cancellable token) throws Error
        {
            var result = new Gee.HashMap<string, string>();
            if (!(item.mime.has_prefix("audio/") || item.mime.has_prefix("video/") || item.mime.has_prefix("image/")))
                return result;
            var bytes = yield PreviewSandbox.run(item, item.mime.has_prefix("image/") ? "image-info" : "media-info", {}, token);
            if (bytes.get_size() > 512 * 1024)
                throw new FileError.INVALID("Media metadata exceeds the limit");
            var parser = new Json.Parser();
            parser.load_from_data((string)bytes.get_data(), (ssize_t)bytes.get_size());
            if (parser.get_root().get_node_type() != Json.NodeType.OBJECT)
                throw new FileError.INVALID("Invalid media metadata");
            var object = parser.get_root().get_object();
            foreach (var key in object.get_members())
                if (object.get_member(key).get_value_type() == typeof(string))
                    result[key] = object.get_string_member(key);
            return result;
        }
        public static Gtk.Widget presentation(Gee.Map<string, string> fields)
        {
            var list = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            foreach (var key in fields.keys) {
                if (key == "Artwork PNG") {
                    var picture = new Gtk.Picture.for_paintable(Gdk.Texture.from_bytes(new Bytes(Base64.decode(fields[key]))));
                    picture.content_fit = Gtk.ContentFit.CONTAIN;
                    list.append(picture);
                    continue;
                }
                var label = new Gtk.Label(key + ": " + fields[key]);
                label.xalign = 0;
                label.wrap = true;
                label.selectable = true;
                list.append(label);
            }
            return list;
        }
    }
    public class MetadataPage : Adw.PreferencesPage {
        Cancellable token = new Cancellable();
        Adw.PreferencesGroup group = new Adw.PreferencesGroup();
        MetadataStore? metadata;
        public MetadataPage(FileItem item, MetadataStore? metadata = null)
        {
            this.metadata = metadata;
            title = "Metadata";
            icon_name = "dialog-information-symbolic";
            add(group);
            load.begin(item);
        }
        public override void unroot() { token.cancel(); base.unroot(); }
        async void load(FileItem item)
        {
            try {
                var fields = yield RichMetadata.load(item, token);
                token.set_error_if_cancelled();
                group.description = fields.size == 0 ? "No additional metadata is available for this file." : "Stream metadata reported by the installed system decoders.";
                foreach (var key in fields.keys) {
                    if (key == "Artwork PNG") continue;
                    var row = new Adw.ActionRow();
                    row.title = key;
                    row.subtitle = fields[key];
                    row.subtitle_selectable = true;
                    group.add(row);
                }
                if (metadata != null)
                    foreach (var extension in ExtensionManager.get_default(metadata).extensions) {
                        if (!extension.enabled) continue;
                        try {
                            if ("metadata" in extension.capabilities) {
                                var values = yield extension.file_info(item);
                                foreach (var key in values.keys) {
                                    var row = new Adw.ActionRow(); row.title = extension.name + ": " + key;
                                    row.subtitle = values[key]; row.subtitle_selectable = true; group.add(row);
                                }
                            }
                            if ("properties" in extension.capabilities) {
                                var response = yield extension.call("GetProperties", new Variant("(s)", ExternalExtension.safe_uri(item)), "(a(ss))", token);
                                var entries = response.get_child_value(0);
                                if (entries.n_children() > 64) throw new FileError.INVALID("Too many extension properties");
                                for (size_t i = 0; i < entries.n_children(); i++) {
                                    var entry = entries.get_child_value(i);
                                    string title = entry.get_child_value(0).get_string(), value = entry.get_child_value(1).get_string();
                                    if (title.length > 100 || value.length > 16384) throw new FileError.INVALID("Oversized extension property");
                                    var row = new Adw.ActionRow(); row.title = extension.name + ": " + title; row.subtitle = value; row.subtitle_selectable = true; group.add(row);
                                }
                            }
                        }
                        catch (Error e) { if (!token.is_cancelled()) { var row = new Adw.ActionRow(); row.title = extension.name; row.subtitle = _("Extension unavailable: ") + e.message; group.add(row); } }
                    }
            }
            catch (Error e) { if (!token.is_cancelled()) group.description = e.message; }
        }
    }
}
