namespace MajorisFiles {
    public class SevenZipDialog : Adw.PreferencesDialog {
        public SevenZipDialog(Gtk.Window parent, Gee.List<FileItem> selection, File folder, OperationManager operations)
        {
            title = _("Compress");
            var captured = new Gee.ArrayList<File>(); foreach (var item in selection) captured.add(item.file);
            var page = new Adw.PreferencesPage(); var group = new Adw.PreferencesGroup(); page.add(group); add(page);
            var name = new Adw.EntryRow(); name.title = _("Archive Filename"); name.text = "Archive.zip"; group.add(name);
            string[] formats = {"zip", "7z", "tar", "tar.gz", "tar.bz2", "tar.xz", "tar.zst"};
            var format = new Adw.ComboRow(); format.title = _("Archive Format"); format.model = new Gtk.StringList(formats); group.add(format);
            var size = new Adw.SpinRow.with_range(0, 1048576, 1); size.title = _("Volume Size (MiB; 0 for one file)"); group.add(size);
            var level = new Adw.SpinRow.with_range(0, 9, 1); level.title = _("Compression Level"); level.value = 5; group.add(level);
            var encrypted = new Adw.SwitchRow(); encrypted.title = _("Encrypt Contents and Filenames"); group.add(encrypted);
            size.sensitive = false; level.sensitive = false;
            encrypted.title = _("Encrypt Contents (ZIP filenames remain visible)");
            string previous_format = "zip";
            format.notify["selected"].connect(() => {
                string suffix = formats[format.selected];
                string stem = name.text;
                if (stem.has_suffix("." + previous_format)) stem = stem.substring(0, stem.length - previous_format.length - 1);
                name.text = stem + "." + suffix; previous_format = suffix;
                bool seven = suffix == "7z"; size.sensitive = seven; level.sensitive = seven;
                encrypted.sensitive = seven || suffix == "zip";
                if (!encrypted.sensitive) encrypted.active = false;
                encrypted.title = seven ? _("Encrypt Contents and Filenames") : _("Encrypt Contents (ZIP filenames remain visible)");
            });
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
                string selected_format = formats[format.selected];
                if (!Paths.valid_name(name.text) || !name.text.has_suffix("." + selected_format)) { Dialogs.error(parent, _("Choose a filename matching the archive format")); return; }
                start.sensitive = false;
                create.begin(parent, captured, destination.get_child(name.text), selected_format, (uint64)size.value * 1024 * 1024, (uint)level.value, encrypted.active, operations, start);
            });
            present(parent);
        }
        async void create(Gtk.Window parent, Gee.List<File> sources, File output, string format, uint64 size, uint level, bool encrypted, OperationManager operations, Gtk.Button start)
        {
            string? password = null;
            if (encrypted) {
                password = yield Dialogs.password(parent, _("Encrypt Archive"), true);
                if (password == null) { start.sensitive = true; return; }
            }
            var job = operations.start(_("Compress")); job.parent = parent;
            close();
            try { if (format == "7z") yield SevenZip.create(sources, output, size, level, password, job);
                else yield ArchiveService.compress(sources, output, format, job, password); operations.finish(job); }
            catch (Error e) { operations.finish(job, e); Dialogs.error(parent, e.message); }
        }
    }
}
