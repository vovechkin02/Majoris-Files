namespace MajorisFiles {
    public class ChecksumDialog : Adw.PreferencesDialog {
        File file;
        Gtk.Window parent_window;
        OperationManager operations;
        Adw.ComboRow algorithm = new Adw.ComboRow();
        Adw.EntryRow expected = new Adw.EntryRow();
        Adw.ActionRow result = new Adw.ActionRow();
        Cancellable token = new Cancellable();
        Gtk.Button calculate = new Gtk.Button.with_label("Calculate / Verify");
        Gtk.Button load = new Gtk.Button.with_label("Load Checksum File…");
        public ChecksumDialog(Gtk.Window parent, File file, OperationManager operations)
        {
            title = "Checksums";
            parent_window = parent;
            this.file = file;
            this.operations = operations;
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            group.title = file.get_basename();
            page.add(group);
            add(page);
            algorithm.title = "Algorithm";
            algorithm.model = new Gtk.StringList({"SHA-256", "SHA-512"});
            group.add(algorithm);
            expected.title = "Expected Checksum (optional)";
            group.add(expected);
            result.title = "Result";
            result.subtitle_selectable = true;
            group.add(result);
            group.add(load);
            group.add(calculate);
            calculate.clicked.connect(() => run.begin());
            load.clicked.connect(() => load_file.begin());
            closed.connect(() => token.cancel());
            present(parent);
        }
        async void load_file()
        {
            try {
                var chooser = new Gtk.FileDialog();
                chooser.title = "Select Checksum File";
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
    }
}
