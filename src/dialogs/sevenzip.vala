namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/sevenzip.ui")]
    public class SevenZipDialog : Adw.PreferencesDialog {
        private bool template_disposing;

        [GtkChild] private unowned Gtk.Button browse;
        [GtkChild] private unowned Adw.SwitchRow encrypted;
        [GtkChild] private unowned Adw.ComboRow format;
        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Adw.SpinRow level;
        [GtkChild] private unowned Adw.EntryRow name;
        [GtkChild] private unowned Adw.PreferencesPage page;
        [GtkChild] private unowned Adw.SpinRow size;
        [GtkChild] private unowned Gtk.Button start;
        [GtkChild] private unowned Adw.ActionRow target;
        public SevenZipDialog(Gtk.Window parent, Gee.List<FileItem> selection, File folder, OperationManager operations)
        {
            var captured = new Gee.ArrayList<File>(); foreach (var item in selection) captured.add(item.file);

            string[] formats = {"zip", "7z", "tar", "tar.gz", "tar.bz2", "tar.xz", "tar.zst"};



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
              target.subtitle = folder.get_parse_name();

            File destination = folder;
            browse.clicked.connect(() => {
                var dialog = new Gtk.FileDialog(); dialog.title = _("Archive Destination");
                dialog.select_folder.begin(parent, null, (obj, res) => {
                    try { destination = dialog.select_folder.end(res); target.subtitle = destination.get_parse_name(); }
                    catch (Error e) { if (!(e is Gtk.DialogError.DISMISSED)) Dialogs.error(parent, e.message); }
                });
            });

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
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(SevenZipDialog));
            }
            base.dispose();
        }
    }
}
