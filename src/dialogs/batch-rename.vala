namespace MajorisFiles {
    public class BatchRenameDialog : Adw.PreferencesDialog {
        Gtk.Window parent_window;
        OperationManager operations;
        Gee.ArrayList<FileItem> items = new Gee.ArrayList<FileItem>();
        Gee.ArrayList<FileItem> original_order = new Gee.ArrayList<FileItem>();
        Gee.ArrayList<string> names = new Gee.ArrayList<string>();
        Gee.HashMap<string, Gee.HashMap<string, string>> metadata = new Gee.HashMap<string, Gee.HashMap<string, string>>();
        Adw.ComboRow mode = new Adw.ComboRow();
        Adw.ComboRow order = new Adw.ComboRow();
        Adw.EntryRow pattern = new Adw.EntryRow();
        Adw.EntryRow replacement = new Adw.EntryRow();
        Adw.SpinRow start = new Adw.SpinRow.with_range(0, 1000000000, 1);
        Adw.SpinRow digits = new Adw.SpinRow.with_range(1, 12, 1);
        Adw.SwitchRow descending = new Adw.SwitchRow();
        Adw.PreferencesGroup preview = new Adw.PreferencesGroup();
        Gee.ArrayList<Adw.ActionRow> rows = new Gee.ArrayList<Adw.ActionRow>();
        Gtk.Button apply = new Gtk.Button.with_label(_("Rename Files"));
        Cancellable token = new Cancellable();
        uint generation;
        public BatchRenameDialog(Gtk.Window parent, Gee.List<FileItem> selection, OperationManager operations)
        {
            title = "Batch Rename"; parent_window = parent; this.operations = operations;
            items.add_all(selection);
            original_order.add_all(selection);
            var page = new Adw.PreferencesPage(); var group = new Adw.PreferencesGroup(); page.add(group); add(page);
            mode.title = _("Mode"); mode.model = new Gtk.StringList({"Find and Replace", "Add Text Before", "Add Text After", "Format / Template", "Automatic Numbering", "Date Insertion", "Metadata Insertion"}); mode.selected = 3; group.add(mode);
            pattern.title = _("Pattern / Text"); pattern.text = "{stem} - {counter}{extension}"; group.add(pattern);
            replacement.title = _("Replace With"); group.add(replacement);
            start.title = _("Starting Number"); start.value = 1; group.add(start);
            digits.title = _("Minimum Digits"); digits.value = 3; group.add(digits);
            descending.title = _("Descending Numbering"); group.add(descending);
            order.title = _("Order Before Numbering"); order.model = new Gtk.StringList({"Selection Order", "Filename", "Modified Date", "Created Date"}); group.add(order);
            group.description = _("Templates: {original}, {stem}, {extension}, {counter}, {created}, {modified}, {camera}, {artist}, {album}, {track}, {title}, {season}, {episode}. Missing metadata blocks renaming.");
            preview.title = _("Before → After"); page.add(preview); group.add(apply);
            mode.notify["selected"].connect(() => {
                if (mode.selected == 5) pattern.text = "{modified} - {stem}{extension}";
                if (mode.selected == 6) pattern.text = "{artist} - {title}{extension}";
                update.begin();
            });
            pattern.changed.connect(() => update.begin()); replacement.changed.connect(() => update.begin());
            start.notify["value"].connect(() => update.begin()); digits.notify["value"].connect(() => update.begin());
            descending.notify["active"].connect(() => update.begin()); order.notify["selected"].connect(() => update.begin());
            apply.clicked.connect(() => execute.begin()); closed.connect(() => token.cancel());
            update.begin(); present(parent);
        }
        async void update()
        {
            uint current = ++generation;
            apply.sensitive = false;
            if (items.size == 0 || items.size > 1000) { preview.description = _("Select between 1 and 1,000 items"); return; }
            var sorted = new Gee.ArrayList<FileItem>(); sorted.add_all(original_order);
            if (order.selected > 0) sorted.sort((a, b) => {
                if (order.selected == 1) return Paths.natural_compare(a.name, b.name);
                string attr = order.selected == 2 ? "time::modified" : "time::created";
                uint64 first = a.info.get_attribute_uint64(attr), second = b.info.get_attribute_uint64(attr);
                return first == second ? Paths.natural_compare(a.name, b.name) : first < second ? -1 : 1;
            });
            var results = new Gee.ArrayList<string>(); var occupied = new Gee.HashSet<string>();
            var sources = new Gee.HashSet<string>(); foreach (var item in sorted) sources.add(item.file.get_uri());
            bool valid = true;
            var descriptions = new Gee.ArrayList<string>();
            for (int i = 0; i < sorted.size; i++) {
                var item = sorted[i]; string result;
                try {
                    if (mode.selected >= 3 && (pattern.text.contains("{artist}") || pattern.text.contains("{album}") || pattern.text.contains("{title}") || pattern.text.contains("{camera}") || pattern.text.contains("{track}") || pattern.text.contains("{season}") || pattern.text.contains("{episode}")) && !metadata.has_key(item.file.get_uri())) {
                        preview.description = _("Reading selected-file metadata…");
                        try { metadata[item.file.get_uri()] = yield RichMetadata.load(item, token); }
                        catch (Error e) { if (token.is_cancelled()) return; metadata[item.file.get_uri()] = new Gee.HashMap<string, string>(); }
                    }
                    result = RenamePlan.name(item, mode.selected, pattern.text, replacement.text, (int)start.value + (descending.active ? sorted.size - 1 - i : i), (int)digits.value, metadata[item.file.get_uri()]);
                    if (!occupied.add(result)) throw new FileError.CONFLICT("Duplicate output name: " + result);
                    var target = item.file.get_parent().get_child(result);
                    try { yield target.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token); if (!sources.contains(target.get_uri())) throw new FileError.CONFLICT("Destination already exists: " + result); }
                    catch (IOError.NOT_FOUND e) {}
                }
                catch (Error e) { result = "Cannot rename: " + e.message; valid = false; }
                results.add(result); descriptions.add(item.name);
                if (token.is_cancelled() || current != generation) return;
            }
            foreach (var row in rows) preview.remove(row); rows.clear();
            for (int i = 0; i < results.size; i++) { var row = new Adw.ActionRow(); row.title = descriptions[i]; row.subtitle = results[i]; row.subtitle_selectable = true; preview.add(row); rows.add(row); }
            items = sorted; names = results;
            preview.description = valid ? "All names are valid. Destinations are checked again when applying." : "Resolve invalid names, collisions or missing metadata before applying.";
            apply.sensitive = valid;
        }
        async void execute()
        {
            apply.sensitive = false;
            var files = new Gee.ArrayList<File>(); foreach (var item in items) files.add(item.file);
            try { yield operations.batch_rename(files, names, parent_window); close(); }
            catch (Error e) { Dialogs.error(parent_window, e.message); update.begin(); }
        }
    }
}
