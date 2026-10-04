namespace MajorisFiles {
    public class Dialogs : Object {
        public static void error(Gtk.Widget parent, string message)
        {
            var dialog = new Adw.AlertDialog("Could not complete the action", message);
            dialog.add_response("close", "Close");
            dialog.present(parent);
        }
        public static async string? prompt(Gtk.Widget parent, string title, string initial = "")
        {
            var dialog = new Adw.AlertDialog(title, null);
            var entry = new Gtk.Entry();
            entry.text = initial;
            entry.activates_default = true;
            dialog.extra_child = entry;
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("apply", "Apply");
            dialog.default_response = "apply";
            dialog.close_response = "cancel";
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED);
            entry.grab_focus();
            return (yield dialog.choose(parent, null)) == "apply" ? entry.text : null;
        }
        public static async bool confirm(Gtk.Widget parent, string title, string body, string action)
        {
            var dialog = new Adw.AlertDialog(title, body);
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("apply", action);
            dialog.close_response = "cancel";
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.DESTRUCTIVE);
            return (yield dialog.choose(parent, null)) == "apply";
        }
        public static void show_properties(Gtk.Window parent, Gee.List<FileItem> items, MetadataStore metadata)
        {
            var dialog = new Adw.PreferencesDialog();
            dialog.title = "Properties";
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            page.add(group);
            dialog.add(page);
            uint64 size = 0;
            foreach (var item in items)
                size += item.bytes;
            group.add(row("Items", items.size.to_string()));
            group.add(row("Size", Paths.size(size) + " (" + size.to_string() + " bytes)"));
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
                if (item.info.get_is_symlink())
                    group.add(row("Link target", item.info.get_symlink_target() ?? "Unavailable"));
                var favorite = new Adw.SwitchRow();
                favorite.title = "Favorite";
                favorite.active = metadata.favorite(item.file);
                favorite.notify["active"].connect(() => metadata.set_favorite(item.file, favorite.active));
                group.add(favorite);
                var tags = new Adw.EntryRow();
                tags.title = "Tags (comma separated)";
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
