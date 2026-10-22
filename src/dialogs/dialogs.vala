namespace MajorisFiles {
    public delegate void PropertiesPermissions();
    public delegate Adw.PreferencesPage PropertiesSharing();
    public class Dialogs : Object {
        public static void error(Gtk.Widget parent, string message)
        {
            var dialog = new Adw.AlertDialog(_("Could not complete the action"), message);
            dialog.add_response("close", _("Close"));
            dialog.present(parent);
        }
        public static async string? prompt(Gtk.Widget parent, string title, string initial = "")
        {
            var dialog = new Adw.AlertDialog(title, null);
            var entry = new Gtk.Entry();
            entry.text = initial;
            entry.activates_default = true;
            dialog.extra_child = entry;
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("apply", _("Apply"));
            dialog.default_response = "apply";
            dialog.close_response = "cancel";
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED);
            entry.grab_focus();
            return (yield dialog.choose(parent, null)) == "apply" ? entry.text : null;
        }
        public static async bool confirm(Gtk.Widget parent, string title, string body, string action)
        {
            var dialog = new Adw.AlertDialog(title, body);
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("apply", action);
            dialog.close_response = "cancel";
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.DESTRUCTIVE);
            return (yield dialog.choose(parent, null)) == "apply";
        }
        public static async string? password(Gtk.Widget parent, string title, bool confirmation = false, string note = "")
        {
            string message = "The password is used for this operation and is not saved." + (note == "" ? "" : "\n" + note);
            while(true)
            {
                var dialog = new Adw.AlertDialog(title, message);
                var fields = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
                var entry = new Adw.PasswordEntryRow();
                entry.title = _("Password");
                fields.append(entry);
                var repeat = new Adw.PasswordEntryRow();
                repeat.title = _("Confirm Password");
                if(confirmation)
                    fields.append(repeat);
                dialog.extra_child = fields;
                dialog.add_response("cancel", _("Cancel"));
                dialog.add_response("apply", _("Continue"));
                dialog.close_response = "cancel";
                dialog.default_response = "apply";
                dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED);
                if((yield dialog.choose(parent, null)) != "apply")
                    return null;
                if(entry.text != "" && entry.text.length <= 4096 && (!confirmation || entry.text == repeat.text))
                {
                    string result = entry.text;
                    entry.text = "";
                    repeat.text = "";
                    return result;
                }
                entry.text = "";
                repeat.text = "";
                message = "Enter a non-empty password up to 4096 bytes. Confirmation must match.";
            }
        }
        public static void show_properties(Gtk.Window parent, Gee.List<FileItem> items, MetadataStore metadata, owned PropertiesSharing? permissions = null, owned PropertiesSharing? sharing = null, owned PropertiesSharing? details = null, owned PropertiesSharing? associations = null)
        {
            if(items.size == 0)
                return;
            var dialog = new Adw.PreferencesDialog();
            dialog.title = _("Properties");
            var page = new Adw.PreferencesPage();
            page.title = _("General");
            page.icon_name = "document-properties-symbolic";
            var group = new Adw.PreferencesGroup();
            page.add(group);
            dialog.add(page);
            if (sharing != null && items.size == 1 && items[0].directory && items[0].file.is_native() && !Paths.is_symlink(items[0].info))
                dialog.add(sharing());
            if (details != null && items.size == 1)
                dialog.add(details());
            if (permissions != null)
                dialog.add(permissions());
            if (associations != null && items.size == 1 && !items[0].directory)
                dialog.add(associations());
            uint64 size = 0;
            foreach (var item in items)
                size += item.bytes;
            group.add(row("Items", items.size.to_string()));
            var size_row = row("Size", Paths.size(size) + " (" + size.to_string() + " bytes)");
            group.add(size_row);
            var counts_row = row("Contents", "Calculating…");
            group.add(counts_row);
            var allocated_row = row("Size on Disk", "Calculating…");
            group.add(allocated_row);
            var counts = new FileCounts();
            var token = new Cancellable();
            var roots = new Gee.ArrayList<File>();
            foreach(var item in items)
                roots.add(item.file);
            counts.updated.connect(() => {
                counts_row.subtitle = _("%") + uint64.FORMAT + " files, %" + uint64.FORMAT + " folders";
                counts_row.subtitle = counts_row.subtitle.printf(counts.files, counts.folders) + (counts.unreadable > 0 ? " · Some items are unreadable" : "");
                allocated_row.subtitle = Paths.size(counts.allocated);
                size_row.subtitle = Paths.size(counts.bytes) + " (" + counts.bytes.to_string() + " bytes)" + (counts.unreadable > 0 ? " · Partial total" : "");
            });
            counts.scan.begin(roots, token, (obj, res) => { try { counts.scan.end(res);
                                                            }
                                                            catch(Error e) {}
                });
            dialog.closed.connect(() => token.cancel());
            if(items.size > 1)
            {
                var types = new Gee.HashSet<string>();
                foreach(var item in items)
                    types.add(item.mime);
                var type_names = new Gee.ArrayList<string>();
                type_names.add_all(types);
                type_names.sort((a, b) => strcmp(a, b));
                group.add(row("Types", string.joinv(", ", type_names.to_array())));
                var common = items[0].file.get_parent();
                foreach(var item in items)
                    if(common != null && (item.file.get_parent() == null || !common.equal(item.file.get_parent())))
                        common = null;
                group.add(row("Location", common == null ? "Multiple locations" : common.get_parse_name()));
                string? common_mode = null;
                bool mixed_mode = false;
                foreach(var item in items)
                {
                    string mode = item.info.has_attribute("unix::mode") ? "%04o".printf(item.info.get_attribute_uint32("unix::mode") & 07777) : "Unavailable";
                    if(common_mode == null)
                        common_mode = mode;
                    else if(common_mode != mode)
                        mixed_mode = true;
                }
                group.add(row("Permissions", mixed_mode ? "Multiple permissions" : common_mode ?? "Unavailable"));
                var common_tags = new Gee.ArrayList<string>();
                foreach(var tag in metadata.tags(items[0].file).split(","))
                    if(tag.strip() != "")
                        common_tags.add(tag.strip());
                foreach(var item in items)
                {
                    var present = new Gee.HashSet<string>();
                    foreach(var tag in metadata.tags(item.file).split(","))
                        present.add(tag.strip());
                    for(int i = common_tags.size - 1; i >= 0; i--)
                        if(!present.contains(common_tags[i]))
                            common_tags.remove_at(i);
                }
                group.add(row("Common Tags", common_tags.size == 0 ? "None" : string.joinv(", ", common_tags.to_array())));
                var favorites = new Adw.SwitchRow();
                favorites.title = _("Favorite All Selected Items");
                bool all_favorites = true;
                foreach(var item in items)
                    if(!metadata.favorite(item.file))
                        all_favorites = false;
                favorites.active = all_favorites;
                group.add(favorites);
                favorites.notify["active"].connect(() => { foreach(var item in items)
                                                               metadata.set_favorite(item.file, favorites.active);
                    });
                var tags = new Adw.EntryRow();
                tags.title = _("Replace Tags on All Selected Items");
                tags.show_apply_button = true;
                tags.apply.connect(() => { foreach(var item in items)
                                               metadata.set_tags(item.file, tags.text);
                    });
                group.add(tags);
            }
            if (items.size == 1)
            {
                var item = items[0];
                group.add(row("Name", item.name));
                group.add(row("Location", item.file.get_parse_name()));
                group.add(row("Type", item.mime));
                var date = item.info.get_modification_date_time();
                if (date != null)
                    group.add(row("Modified", date.format("%c")));
                if (item.info.has_attribute("unix::mode"))
                    group.add(row("Permissions", "%04o".printf(item.info.get_attribute_uint32("unix::mode") & 07777)));
                if(item.info.has_attribute("owner::user"))
                    group.add(row("Owner", item.info.get_attribute_string("owner::user")));
                if(item.info.has_attribute("owner::group"))
                    group.add(row("Group", item.info.get_attribute_string("owner::group")));
                if(item.info.has_attribute("selinux::context"))
                    group.add(row("SELinux Context", item.info.get_attribute_string("selinux::context") ?? "Unavailable"));
                var created = item.info.get_creation_date_time();
                if(created != null)
                    group.add(row("Created", created.format("%c")));
                var accessed = item.info.get_access_date_time();
                if(accessed != null)
                    group.add(row("Accessed", accessed.format("%c")));
                if (Paths.is_symlink(item.info))
                    group.add(row("Link target", item.info.get_symlink_target() ?? "Unavailable"));
                var favorite = new Adw.SwitchRow();
                favorite.title = _("Favorite");
                favorite.active = metadata.favorite(item.file);
                favorite.notify["active"].connect(() => metadata.set_favorite(item.file, favorite.active));
                group.add(favorite);
                var tags = new Adw.EntryRow();
                tags.title = _("Tags (comma separated)");
                tags.text = metadata.tags(item.file);
                tags.show_apply_button = true;
                tags.apply.connect(() => metadata.set_tags(item.file, tags.text));
                group.add(tags);
            }
            dialog.present(parent);
        }
        static Adw.ActionRow row(string title, string value)
        {
            var row = new Adw.ActionRow();
            row.title = title;
            row.subtitle = value;
            row.subtitle_selectable = true;
            return row;
        }
    }
}
