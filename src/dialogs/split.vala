namespace MajorisFiles {
    public class SplitDialog : Adw.PreferencesDialog {
        FileItem item;
        File destination;
        Gtk.Window owner_window;
        OperationManager operations;
        Adw.ComboRow method = new Adw.ComboRow();
        Adw.ComboRow units = new Adw.ComboRow();
        Gtk.SpinButton amount = new Gtk.SpinButton.with_range(1, 1000000000, 1);
        Adw.ActionRow estimate = new Adw.ActionRow();
        Cancellable token = new Cancellable();
        Adw.SwitchRow manifest = new Adw.SwitchRow();
        public SplitDialog(Gtk.Window owner_window, FileItem item, File destination, OperationManager operations)
        {
            this.owner_window = owner_window;
            this.item = item;
            this.destination = destination;
            this.operations = operations;
            title = "Split File";
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            page.add(group);
            add(page);
            var source = new Adw.ActionRow();
            source.title = item.name;
            source.subtitle = Paths.size(item.bytes);
            group.add(source);
            var target = new Adw.ActionRow();
            target.title = "Destination";
            target.subtitle = destination.get_parse_name();
            var choose = new Gtk.Button.with_label("Choose…");
            target.add_suffix(choose);
            group.add(target);
            choose.clicked.connect(() => choose_destination.begin(target));
            method.title = "Split By";
            method.model = new Gtk.StringList({"Part Size", "Number of Parts", "Destination Filesystem Limit"});
            group.add(method);
            var preset = new Adw.ComboRow();
            preset.title = "Preset";
            preset.model = new Gtk.StringList({"Custom", "25 MB", "100 MB", "500 MB", "1 GB", "2 GB", "4 GB"});
            group.add(preset);
            var value = new Adw.ActionRow();
            value.title = "Amount";
            amount.value = 2048;
            amount.digits = 0;
            value.add_suffix(amount);
            group.add(value);
            units.title = "Size Unit";
            units.model = new Gtk.StringList({"Bytes", "KiB", "MiB", "GiB"});
            units.selected = 2;
            group.add(units);
            preset.notify["selected"].connect(() => {
                if(preset.selected == 0)
                    return;
                uint64[] sizes = {0, 25000000, 100000000, 500000000, 1000000000, 2000000000, 4000000000};
                method.selected = 0;
                units.selected = 0;
                amount.value = sizes[preset.selected];
                update_estimate.begin();
            });
            // Decimal presets may exceed the custom unit's initial spin range.
            amount.set_range(1, 4000000000);
            estimate.title = "Estimated Output";
            group.add(estimate);
            var explanation = new Adw.ActionRow();
            explanation.title = "Original kept";
            explanation.subtitle = "Parts are streamed to new files. Existing outputs are never overwritten. Up to 10,000 parts.";
            group.add(explanation);
            manifest.title = "Include SHA-256 Manifest";
            manifest.subtitle = "Recommended: verifies every part and the reconstructed file. Without it, missing final parts cannot be detected.";
            manifest.active = true;
            group.add(manifest);
            var start = new Gtk.Button.with_label("Split File");
            start.add_css_class("suggested-action");
            group.add(start);
            start.clicked.connect(() => split.begin(start));
            amount.value_changed.connect(() => update_estimate.begin());
            units.notify["selected"].connect(() => update_estimate.begin());
            method.notify["selected"].connect(() => { units.sensitive = method.selected == 0;
                                                      amount.sensitive = method.selected != 2;
                                                      preset.sensitive = method.selected == 0;
                                                      update_estimate.begin();
                });
            closed.connect(() => token.cancel());
            update_estimate.begin();
            present(owner_window);
        }
        async void choose_destination(Adw.ActionRow row)
        {
            try {
                var chooser = new Gtk.FileDialog();
                chooser.title = "Split Destination";
                chooser.initial_folder = destination;
                destination = yield chooser.select_folder(owner_window, token);
                row.subtitle = destination.get_parse_name();
                update_estimate.begin();
            }
            catch(Error e) {
                if(!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED))
                    Dialogs.error(owner_window, e.message);
            }
        }
        async uint64 piece_size() throws Error
        {
            uint64 value = (uint64)amount.value;
            if(method.selected == 1)
                return Paths.split_size(item.bytes, value);
            if(method.selected == 2)
            {
                var fs = yield destination.query_filesystem_info_async("filesystem::type", Priority.DEFAULT, token);
                uint64 limit = Paths.max_file_size(fs.get_attribute_string("filesystem::type") ?? "");
                return limit == uint64.MAX ? 2147483648 : limit - 1048576;
            }
            uint64[] multipliers = {
                1, 1024, 1048576, 1073741824
            };
            if(value == 0 || value > uint64.MAX / multipliers[units.selected])
                throw new FileError.INVALID("Invalid part size");
            return value * multipliers[units.selected];
        }
        async void update_estimate()
        {
            try {
                uint64 size = yield piece_size();
                if(token.is_cancelled())
                    return;
                uint64 count = item.bytes / size + (item.bytes % size == 0 ? 0 : 1);
                estimate.subtitle = "%" + uint64.FORMAT + " parts · up to %s each";
                estimate.subtitle = estimate.subtitle.printf(count, Paths.size(size));
            }
            catch(Error e) {
                if(!token.is_cancelled())
                    estimate.subtitle = e.message;
            }
        }
        async void split(Gtk.Button start)
        {
            try {
                uint64 size = yield piece_size();
                uint64 count = item.bytes / size + (item.bytes % size == 0 ? 0 : 1);
                if(count > 10000 || count == 0)
                    throw new FileError.INVALID("Choose a size producing between 1 and 10,000 parts");
                if(count > 1000 && !(yield Dialogs.confirm(owner_window, "Create Many Parts?", "This will create " + count.to_string() + " part files and a manifest.", "Split")))
                    return;
                var file = item.file;
                var folder = destination;
                start.sensitive = false;
                var job = operations.start("Split File");
                job.parent = owner_window;
                close();
                try {
                    yield SplitService.split(file, folder, size, job, manifest.active);
                    operations.finish(job);
                }
                catch(Error e) {
                    operations.finish(job, e);
                }
            }
            catch(Error e) {
                if(!(e is IOError.CANCELLED))
                    Dialogs.error(owner_window, e.message);
                start.sensitive = true;
            }
        }
    }
}
