namespace MajorisFiles {
    public class SevenZipDialog : Adw.PreferencesDialog {
        public SevenZipDialog(Gtk.Window parent, Gee.List<FileItem> selection, File folder, OperationManager operations)
        {
            title = "Create 7z Archive";
            var captured = new Gee.ArrayList<File>(); foreach (var item in selection) captured.add(item.file);
            var page = new Adw.PreferencesPage(); var group = new Adw.PreferencesGroup(); page.add(group); add(page);
            var name = new Adw.EntryRow(); name.title = _("Archive Filename"); name.text = "Archive.7z"; group.add(name);
            var size = new Adw.SpinRow.with_range(0, 1048576, 1); size.title = _("Volume Size (MiB; 0 for one file)"); group.add(size);
            var level = new Adw.SpinRow.with_range(0, 9, 1); level.title = _("Compression Level"); level.value = 5; group.add(level);
            var encrypted = new Adw.SwitchRow(); encrypted.title = _("Encrypt Contents and Filenames"); group.add(encrypted);
            var target = new Adw.ActionRow(); target.title = _("Destination"); target.subtitle = folder.get_parse_name(); group.add(target);
            var browse = new Gtk.Button.with_label(_("Choose Destination…")); group.add(browse);
            File destination = folder;
            browse.clicked.connect(() => {
                var dialog = new Gtk.FileDialog(); dialog.title = _("Archive Destination");
                dialog.select_folder.begin(parent, null, (obj, res) => {
                    try { destination = dialog.select_folder.end(res); target.subtitle = destination.get_parse_name(); }
                    catch (Error e) { if (!(e is Gtk.DialogError.DISMISSED)) Dialogs.error(parent, e.message); }
                });
            });
            var start = new Gtk.Button.with_label(_("Create Archive")); start.add_css_class("suggested-action"); group.add(start);
            start.clicked.connect(() => {
                if (!Paths.valid_name(name.text) || !name.text.has_suffix(".7z")) { Dialogs.error(parent, _("Choose a .7z filename")); return; }
                start.sensitive = false;
                create.begin(parent, captured, destination.get_child(name.text), (uint64)size.value * 1024 * 1024, (uint)level.value, encrypted.active, operations, start);
            });
            present(parent);
        }
        async void create(Gtk.Window parent, Gee.List<File> sources, File output, uint64 size, uint level, bool encrypted, OperationManager operations, Gtk.Button start)
        {
            string? password = null;
            if (encrypted) {
                password = yield Dialogs.password(parent, "Encrypt 7z Archive", true);
                if (password == null) { start.sensitive = true; return; }
            }
            var job = operations.start("Create 7z Archive"); job.parent = parent;
            close();
            try { yield SevenZip.create(sources, output, size, level, password, job); operations.finish(job); }
            catch (Error e) { operations.finish(job, e); Dialogs.error(parent, e.message); }
        }
    }
}
