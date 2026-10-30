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
        MetadataStore? metadata;
        bool managed;
        File original_file;
        Gee.HashMap<string, Adw.ActionRow> file_rows = new Gee.HashMap<string, Adw.ActionRow>();
        Gee.HashMap<string, Adw.ActionRow> attribute_rows = new Gee.HashMap<string, Adw.ActionRow>();
        public Adw.ActionRow exact_size;
        public Adw.ActionRow allocated;
        Adw.ExpanderRow file_information = new Adw.ExpanderRow();
        Adw.PreferencesGroup loading = new Adw.PreferencesGroup();
        Gee.HashMap<string, Adw.PreferencesGroup> groups = new Gee.HashMap<string, Adw.PreferencesGroup>();
        public MetadataPage(FileItem item, MetadataStore? metadata = null, bool managed = false) {
            this.metadata = metadata; this.managed = managed; original_file = item.file; title = _("Details"); icon_name = "dialog-information-symbolic";
            add_field(_("File Information"), _("Name"), item.name);
            add_field(_("File Information"), _("Location"), item.file.get_path() ?? item.file.get_uri());
            add_field(_("File Information"), _("Content Type"), item.mime);
            var storage = new Adw.PreferencesGroup(); storage.title = _("Storage"); add(storage);
            exact_size = PropertiesDialog.value_row(_("Exact Size"), item.info.has_attribute("standard::size") ? item.bytes.to_string() + _(" bytes") : _("Unavailable")); storage.add(exact_size);
            allocated = PropertiesDialog.value_row(_("Size on Disk"), item.info.has_attribute("standard::allocated-size") ? Paths.size(item.info.get_attribute_uint64("standard::allocated-size")) : _("Unavailable")); storage.add(allocated);
            var modified = item.info.has_attribute("time::modified") ? item.info.get_modification_date_time() : null; if (modified != null) add_field(_("File Information"), _("Modified"), modified.to_local().format("%c") + " · " + modified.format("%FT%T%:z"));
            var created = item.info.has_attribute("time::created") ? item.info.get_creation_date_time() : null; if (created != null) add_field(_("File Information"), _("Created"), created.to_local().format("%c"));
            var accessed = item.info.has_attribute("time::access") ? item.info.get_access_date_time() : null; if (accessed != null) add_field(_("File Information"), _("Accessed"), accessed.to_local().format("%c"));
            if (item.info.has_attribute("owner::user")) add_field(_("File Information"), _("Owner"), item.info.get_attribute_string("owner::user"));
            if (item.info.has_attribute("owner::group")) add_field(_("File Information"), _("Group"), item.info.get_attribute_string("owner::group"));
            if (item.info.has_attribute("unix::mode")) add_field(_("File Information"), _("Mode"), "%04o".printf(item.info.get_attribute_uint32("unix::mode") & 07777));
            if (item.info.has_attribute("selinux::context")) add_field(_("File Information"), _("SELinux Context"), item.info.get_attribute_string("selinux::context"));
            if (Paths.is_symlink(item.info)) add_field(_("File Information"), _("Link Target"), item.info.get_symlink_target() ?? _("Unavailable"));
            var filesystem = new Adw.PreferencesGroup(); filesystem.title = _("Filesystem"); add(filesystem);
            var attributes = new Adw.ExpanderRow(); attributes.title = _("Additional Filesystem Attributes"); filesystem.add(attributes);
            foreach (var key in item.info.list_attributes(null)) { var row = PropertiesDialog.value_row(key, item.info.get_attribute_as_string(key) ?? _("Unavailable")); attribute_rows[key] = row; attributes.add_row(row); }
            loading.description = _("Loading metadata…"); add(loading);
            load.begin(item);
        }
        public void cancel() { token.cancel(); }
        public override void unroot() { if (!managed) cancel(); base.unroot(); }
        void add_field(string section, string key, string value) {
            if (token.is_cancelled()) return;
            if (!groups.has_key(section)) {
                var group = new Adw.PreferencesGroup(); groups[section] = group; add(group);
                if (section == _("File Information")) { file_information.title = section; file_information.subtitle = _("Name, location, exact timestamps and ownership"); group.add(file_information); }
                else group.title = section;
            }
            var row = PropertiesDialog.value_row(key, value);
            if (section == _("File Information")) { file_information.add_row(row); file_rows[key] = row; }
            else groups[section].add(row);
        }
        public async void refresh_file_info() {
            try {
                var info = yield original_file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                token.set_error_if_cancelled();
                if (file_rows.has_key(_("Owner"))) file_rows[_("Owner")].subtitle = info.get_attribute_string("owner::user") ?? _("Unavailable");
                if (file_rows.has_key(_("Group"))) file_rows[_("Group")].subtitle = info.get_attribute_string("owner::group") ?? _("Unavailable");
                if (file_rows.has_key(_("Mode"))) file_rows[_("Mode")].subtitle = info.has_attribute("unix::mode") ? "%04o".printf(info.get_attribute_uint32("unix::mode") & 07777) : _("Unavailable");
                foreach (var key in attribute_rows.keys) attribute_rows[key].subtitle = info.get_attribute_as_string(key) ?? _("Unavailable");
            } catch (Error e) { if (!token.is_cancelled()) add_field(_("Filesystem"), _("Refresh unavailable"), e.message); }
        }
        public static string classify(string key, string mime) {
            string lower = key.down();
            if (lower.has_prefix("exif.") || lower.has_prefix("xmp.") || lower.contains("camera") || lower.contains("lens") || lower.contains("exposure") || lower.contains("iso speed") || lower.contains("gps") || key in new string[] {"Aperture", "ISO", "Focal Length", "Capture Date"}) return _("Camera");
            if (lower.has_prefix("audio") || lower.contains("sample rate") || lower.contains("channels")) return _("Audio");
            if (lower.has_prefix("video") || lower.contains("frame rate")) return _("Video");
            if (mime.has_prefix("image/") && (lower == "dimensions" || lower.contains("width") || lower.contains("height") || lower.contains("resolution") || lower.contains("format") || lower.contains("orientation") || lower.contains("profile") || lower.contains("depth"))) return _("Image");
            if (lower == "duration (seconds)" || lower == "resolution" || lower == "title" || lower == "artist" || lower == "album" || lower == "copyright" || lower == "description") {
                if (mime.has_prefix("video/")) return _("Video");
                if (mime.has_prefix("audio/")) return _("Audio");
            }
            return _("Additional Metadata");
        }
        async void load(FileItem item) {
            // Providers are independent: one failure must never suppress the others.
            try {
                var cloud = yield CloudFiles.get_default().query(item.file, token); token.set_error_if_cancelled();
                if (cloud.state != "unsupported" && (cloud.state != "local" || cloud.quota_known || cloud.capabilities.length > 0 || cloud.error != "")) {
                    add_field(_("Cloud"), _("Sync State"), cloud.state);
                    add_field(_("Cloud"), _("Online Only"), cloud.online_only ? _("Yes") : _("No"));
                    if (cloud.error != "") add_field(_("Cloud"), _("Status"), cloud.error);
                    if (cloud.quota_known) add_field(_("Cloud"), _("Account Storage"), _("%s of %s used").printf(Paths.size(cloud.quota_used), Paths.size(cloud.quota_total)));
                    if (cloud.mime != "") add_field(_("Cloud"), _("Provider Content Type"), cloud.mime);
                    if (cloud.capabilities.length > 0) add_field(_("Cloud"), _("Available Actions"), string.joinv(", ", cloud.capabilities));
                }
            } catch (Error e) { if (!token.is_cancelled()) add_field(_("Cloud"), _("Unavailable"), e.message); }
            if (token.is_cancelled()) return;
            try {
                var fields = yield RichMetadata.load(item, token); token.set_error_if_cancelled();
                var keys = new Gee.ArrayList<string>(); keys.add_all(fields.keys); keys.sort((a, b) => strcmp(a, b));
                foreach (var key in keys) if (key != "Artwork PNG") add_field(classify(key, item.mime), key, fields[key]);
            } catch (Error e) { if (!token.is_cancelled()) add_field(_("Additional Metadata"), _("Media metadata unavailable"), e.message); }
            if (metadata != null && !token.is_cancelled()) foreach (var extension in ExtensionManager.get_default(metadata).extensions) {
                if (!extension.enabled || !("metadata" in extension.capabilities || "properties" in extension.capabilities)) continue;
                try {
                    var fields = new Gee.HashMap<string, string>();
                    if ("metadata" in extension.capabilities) {
                        var values = yield extension.file_info(item, token); token.set_error_if_cancelled();
                        foreach (var key in values.keys) fields[key] = values[key];
                    }
                    if ("properties" in extension.capabilities) {
                        var response = yield extension.call("GetProperties", new Variant("(s)", ExternalExtension.safe_uri(item)), "(a(ss))", token);
                        token.set_error_if_cancelled(); var entries = response.get_child_value(0);
                        if (entries.n_children() > 64) throw new FileError.INVALID("Too many extension properties");
                        for (size_t i = 0; i < entries.n_children(); i++) { var entry = entries.get_child_value(i); string key = entry.get_child_value(0).get_string(), value = entry.get_child_value(1).get_string(); if (key.length > 100 || value.length > 16384) throw new FileError.INVALID("Oversized extension property"); fields[fields.has_key(key) ? _("Property: ") + key : key] = value; }
                    }
                    if (fields.size > 0) {
                        string section = _("Extension Properties");
                        if (!groups.has_key(section)) { var group = new Adw.PreferencesGroup(); group.title = section; groups[section] = group; add(group); }
                        var expander = new Adw.ExpanderRow(); expander.use_markup = false; expander.title = extension.name; groups[section].add(expander);
                        foreach (var key in fields.keys) expander.add_row(PropertiesDialog.value_row(key, fields[key]));
                    }
                } catch (Error e) { if (!token.is_cancelled()) add_field(_("Extension Properties"), extension.name, _("Unavailable: ") + e.message); }
            }
            if (!token.is_cancelled()) remove(loading);
        }
    }
}
