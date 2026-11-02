namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/checksum.ui")]
    public class ChecksumDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        File file;
        Gtk.Window parent_window;
        OperationManager operations;
        [GtkChild]
        private unowned Adw.ComboRow algorithm;
        [GtkChild]
        private unowned Adw.EntryRow expected;
        [GtkChild]
        private unowned Adw.ActionRow result;
        Cancellable token = new Cancellable();
        [GtkChild]
        private unowned Gtk.Button calculate;
        [GtkChild]
        private unowned Gtk.Button load;

        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Adw.PreferencesPage page;
        public ChecksumDialog(Gtk.Window parent, File file, OperationManager operations)
        {
            parent_window = parent;
            this.file = file;
            this.operations = operations;

            group.title = file.get_basename();



            calculate.clicked.connect(() => run.begin());
            load.clicked.connect(() => load_file.begin());
            closed.connect(() => token.cancel());
            present(parent);
        }
        async void load_file()
        {
            try {
                var chooser = new Gtk.FileDialog();
                chooser.title = _("Select Checksum File");
                var selected = yield chooser.open(parent_window, token);
                var input = yield selected.read_async(Priority.LOW, token);
                uint8[] data = new uint8[1024 * 1024 + 1];
                size_t count;
                try { yield input.read_all_async(data, Priority.LOW, token, out count); }
                catch (Error e) {
                    try { yield input.close_async(Priority.LOW, null); } catch (Error ignored) {}
                    throw e;
                }
                yield input.close_async(Priority.LOW, null);
                if (count >= data.length)
                    throw new FileError.INVALID("Checksum file exceeds 1 MiB");
                data[count] = 0;
                expected.text = SplitService.expected_checksum((string)data, file.get_basename(), algorithm.selected == 1 ? ChecksumType.SHA512 : ChecksumType.SHA256);
            }
            catch (Error e) {
                if (!token.is_cancelled() && !(e is Gtk.DialogError.DISMISSED))
                    result.subtitle = e.message;
            }
        }
        async void run()
        {
            calculate.sensitive = load.sensitive = algorithm.sensitive = expected.sensitive = false;
            var type = algorithm.selected == 1 ? ChecksumType.SHA512 : ChecksumType.SHA256;
            var job = operations.start(algorithm.selected == 1 ? "SHA-512" : "SHA-256");
            ulong cancelled = token.cancelled.connect(() => job.cancellable.cancel());
            try {
                string? wanted = expected.text.strip() == "" ? null : SplitService.expected_checksum(expected.text, file.get_basename(), type);
                var hash = yield SplitService.checksum(file, type, job.cancellable);
                result.subtitle = (wanted == null ? "" : wanted == hash ? "Checksum matches\n" : "CHECKSUM DOES NOT MATCH\n") + hash;
                operations.finish(job);
            }
            catch (Error e) { result.subtitle = e.message; operations.finish(job, e); }
            token.disconnect(cancelled);
            calculate.sensitive = load.sensitive = algorithm.sensitive = expected.sensitive = true;
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                if (token != null) token.cancel();
                dispose_template(typeof(ChecksumDialog));
            }
            base.dispose();
        }
    }
}
