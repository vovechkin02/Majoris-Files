namespace MajorisFiles {
    public class ExtraActions : Object {
        FilesWindow window;
        OperationManager operations;
        MetadataStore metadata;
        Browser current {
            get {
                return window.current;
            }
        }
        public ExtraActions(FilesWindow window, OperationManager operations, MetadataStore metadata)
        {
            this.window = window;
            this.operations = operations;
            this.metadata = metadata;
            action("rotate-clockwise", () => rotate_image.begin(true));
            action("rotate-counterclockwise", () => rotate_image.begin(false));
            action("cloud-pin", () => cloud_operation.begin("pin"));
            action("cloud-evict", () => cloud_operation.begin("evict"));
            action("cloud-retry", () => cloud_operation.begin("retry"));
            action("shared-folders", () => new SharedFoldersDialog(window));
            action("copy-to", () => transfer_to.begin(false));
            action("move-to", () => transfer_to.begin(true));
            action("duplicate-items", () => duplicate_items.begin());
            action("folder-with-selection", () => folder_with_selection.begin());
            action("paste-link", () => paste_link.begin());
            action("recover-replacements", () => recover_replacements.begin());
            action("recover-rename",()=>recover_rename.begin());
            action("compress", () => compress.begin());
            action("compress-sevenzip", () => { var items = current.selected(); if (items.size > 0) new SevenZipDialog(window, items, current.location, operations); });
            action("compress-encrypted", () => compress.begin(true));
            action("extract", () => extract.begin());
            action("extract-encrypted", () => extract.begin(true));
            action("share-folder", () => { var items = current.selected();
                                           if (items.size == 1 && items[0].directory)
                                               new SharingDialog(window, items[0].file);
                });
            action("restore", () => restore.begin());
            action("empty-trash", () => empty_trash.begin());
            action("terminal", () => terminal.begin());
            action("open-with", () => open_with.begin());
            action("associations", () => { var items = current.selected();
                                           if(items.size == 1)
                                               new AssociationsDialog(window, items[0]);
                });
            action("custom-icon", () => custom_icon.begin(false));
            action("reset-icon", () => custom_icon.begin(true));
            action("link", () => link.begin());
            action("batch-rename", () => batch_rename.begin());
            action("templates", () => templates.begin());
            action("select-none", () => current.active_selection.unselect_all());
            action("invert-selection", () => { for (uint i = 0; i < current.active_selection.get_n_items(); i++)
                                               {
                                                   if (current.active_selection.is_selected(i))
                                                       current.active_selection.unselect_item(i);
                                                   else current.active_selection.select_item(i, false);
                                               }
                });
            action("select-pattern", () => select_pattern.begin());
            action("permissions", () => { var items = current.selected();
                                          if(items.size > 0)
                                              new PermissionsDialog(window, items);
                });
            action("smb-password", () => smb_password.begin());
            action("connect-server", () => connect_server.begin());
        }
        async void cloud_operation(string action_name)
        {
            var selected = current.selected();
            if (selected.size != 1) return;
            var provider = CloudFiles.get_default().provider(selected[0].file);
            if (provider == null) return;
            var job = new Job(action_name == "pin" ? _("Make Available Offline") : action_name == "evict" ? _("Free Local Space") : _("Retry Cloud Sync"));
            operations.jobs.append(job);
            try {
                yield provider.perform(selected[0].file, action_name, new ImportPolicy(metadata).maximum_bytes, job.cancellable, (fraction, message) => { job.progress = fraction < 0 ? 0 : fraction; job.current = message; });
                job.progress = 1;
            }
            catch (Error e) { job.error = e.message; job.cancelled = e is IOError.CANCELLED; }
            job.done = true;
        }
        async void rotate_image(bool clockwise) {
            var selected = current.selected(); if (selected.size != 1) return;
            try { yield ImageRotation.rotate(selected[0], clockwise, operations, window); }
            catch (Error e) { if (!(e is IOError.CANCELLED)) Dialogs.error(window, e.message); }
        }
        async void recover_replacements()
        {
            try { yield operations.replacements.reconcile(new Cancellable()); }
            catch (Error e) { Dialogs.error(window, e.message); return; }
            var pending = new Gee.ArrayList<ReplacementRecord>();
            foreach(var record in operations.replacements.records)if(record.phase!="history")pending.add(record);
            if (pending.size == 0) {
                Dialogs.error(window, _("There are no pending replacement recovery records."));
                return;
            }
            foreach (var record in pending)
                if (yield Dialogs.confirm(window, "Recover previous “" + record.target.get_basename() + "”?", "The preserved item will be restored without overwriting any current destination. If the name is occupied, a recovered-original name is used.\n" + record.backup.get_parse_name(), "Recover Previous Item")) {
                    try {
                        var restored = yield operations.replacements.restore(record, new Cancellable());
                        window.current.navigate(restored.get_parent());
                        window.current.select_file(restored);
                    }
                    catch (Error e) { Dialogs.error(window, e.message); }
                }
        }
        async void recover_rename(){
            if(!operations.rename_recovery.pending){Dialogs.error(window,_("There is no interrupted batch rename to recover."));return;}
            if(!(yield Dialogs.confirm(window,"Restore original batch names?","Restore the original names from the durable rename journal? Conflicting or externally replaced files will be preserved and reported.","Restore Names")))return;
            try{yield operations.rename_recovery.recover(new Cancellable());window.current.navigate(window.current.location,false);}catch(Error e){Dialogs.error(window,e.message);}
        }
        async File? destination_folder(string title)
        {
            try {
                var settings = new VariantBuilder(VariantType.VARDICT);
                settings.add("{sv}", "directory", new Variant.boolean(true));
                var options = new ChooserOptions(false, settings.end());
                options.initial = current.location;
                var chooser = new ChooserWindow(options, metadata, new Places());
                chooser.title = title;
                chooser.transient_for = window;
                File? result = null;
                SourceFunc resume = destination_folder.callback;
                chooser.completed.connect((code, value) => {
                    if (code == 0) result = File.new_for_uri(value.lookup_value("uris", null).get_child_value(0).get_string());
                    Idle.add((owned)resume);
                });
                chooser.present();
                yield;
                return result;
            }
            catch (Error e) { Dialogs.error(window, e.message); return null; }
        }
        Gee.ArrayList<File> files(Gee.List<FileItem> selection)
        {
            var result = new Gee.ArrayList<File>();
            foreach (var item in selection) result.add(item.file);
            return result;
        }
        async void transfer_to(bool move)
        {
            var selected = files(current.selected());
            if (selected.size == 0) return;
            var folder = yield destination_folder(move ? "Move To" : "Copy To");
            if (folder != null) yield operations.run(move ? OperationKind.MOVE : OperationKind.COPY, selected, folder, window);
        }
        async void duplicate_items()
        {
            var selection = current.selected();
            if (selection.size == 0) return;
            var folder = current.location;
            try {
                var names = new Gee.HashMap<string, string>();
                var reserved = new Gee.HashSet<string>();
                foreach (var item in selection) {
                    for (uint i = 1; ; i++) {
                        if (i > 10000) throw new FileError.CONFLICT("No free duplicate filename was found");
                        int dot = item.name.last_index_of(".");
                        if (item.directory || dot <= 0) dot = item.name.length;
                        string candidate = item.name.substring(0, dot) + " (copy %u)".printf(i) + item.name.substring(dot);
                        if (reserved.contains(candidate)) continue;
                        try { yield folder.get_child(candidate).query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null); }
                        catch (IOError.NOT_FOUND e) { reserved.add(candidate); names[item.file.get_uri()] = candidate; break; }
                    }
                }
                yield operations.run(OperationKind.COPY, files(selection), folder, window, null, names);
            }
            catch (Error e) { Dialogs.error(window, e.message); }
        }
        async void folder_with_selection()
        {
            var selected = files(current.selected());
            if (selected.size == 0) return;
            var parent = current.location;
            var name = yield Dialogs.prompt(window, "New Folder with Selection", "New Folder");
            if (name == null) return;
            try {
                string group = Uuid.string_random();
                yield operations.new_folder(parent, name, group);
                yield operations.run(OperationKind.MOVE, selected, parent.get_child(name), window, group);
            }
            catch (Error e) { Dialogs.error(window, e.message); }
        }
        async void paste_link()
        {
            try {
                var target = current.location;
                if (!target.is_native()) throw new FileError.UNSUPPORTED("Symbolic links require a compatible local destination");
                var clipboard = yield FileClipboard.read(window.get_clipboard());
                yield operations.run(OperationKind.LINK, clipboard.files, target, window);
            }
            catch (Error e) { Dialogs.error(window, e.message); }
        }
        void action(string name, owned Callback callback)
        {
            var action = new SimpleAction(name, null);
            action.activate.connect(() => callback());
            window.add_action(action);
        }
        async void compress(bool encrypted = false)
        {
            var items = current.selected();
            if (items.size == 0)
                return;
            var name = yield Dialogs.prompt(window, "Compress — filename (.zip, .7z, .tar, .tar.gz, .tar.bz2, .tar.xz, .tar.zst)", "Archive.zip");
            if (name == null)
                return;
            string format = "";
            foreach (var suffix in new string[] {"tar.gz", "tar.bz2", "tar.xz", "tar.zst", "zip", "7z", "tar"})
                if (name.has_suffix("." + suffix))
                {
                    format = suffix;
                    break;
                }
            if (!Paths.valid_name(name) || format == "")
            {
                Dialogs.error(window, _("Choose a supported archive extension"));
                return;
            }
            string? password = null;
            if(encrypted)
            {
                if(format != "zip")
                {
                    Dialogs.error(window, _("Encrypted creation currently requires a .zip filename"));
                    return;
                }
                password = yield Dialogs.password(window, "Create AES-256 ZIP", true, "File contents are encrypted. ZIP entry names remain visible.");
                if(password == null)
                    return;
            }
            var files = new Gee.ArrayList<File>();
            foreach (var item in items)
                files.add(item.file);
            var job = operations.start("Compress");
            try {
                yield ArchiveService.compress(files, current.location.get_child(name), format, job, password);
                operations.finish(job);
            }
            catch (Error e) {
                operations.finish(job, e);
                Dialogs.error(window, e.message);
            }
        }
        async void extract(bool encrypted = false)
        {
            var items = current.selected();
            if(items.size != 1 || items[0].directory)
                return;
            var name = yield Dialogs.prompt(window, "Extract to New Folder", items[0].name + " extracted");
            if(name == null)
                return;
            if(!Paths.valid_name(name))
            {
                Dialogs.error(window, _("Invalid folder name"));
                return;
            }
            string? password = null;
            if(encrypted)
            {
                password = yield Dialogs.password(window, "Extract Encrypted Archive");
                if(password == null)
                    return;
            }
            var job = operations.start("Extract");
            try {
                yield ArchiveService.extract(items[0].file, current.location.get_child(name), job, password);
                operations.finish(job);
            }
            catch(Error e) {
                operations.finish(job, e);
                Dialogs.error(window, e.message);
            }
        }
        async void restore()
        {
            foreach(var item in current.selected())
            {
                var original = item.info.get_attribute_byte_string("trash::orig-path");
                if(original == null)
                    continue;
                var destination = File.new_for_path(original);
                var parent = destination.get_parent();
                try {
                    yield parent.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
                }
                catch(Error e) {
                    ChooserOptions options;
                    try {
                        options = new ChooserOptions(false, new VariantBuilder(VariantType.VARDICT).end());
                    }
                    catch(Error e) {
                        Dialogs.error(window, e.message);
                        return;
                    }
                    options.directory = true;
                    var chooser = new ChooserWindow(options, metadata, new Places());
                    chooser.transient_for = window;
                    File? chosen = null;
                    SourceFunc resume = restore.callback;
                    chooser.completed.connect((code, result) => { if(code == 0)
                                                                      chosen = File.new_for_uri(result.lookup_value("uris", null).get_child_value(0).get_string());
                                                                  Idle.add((owned)resume);
                        });
                    chooser.present();
                    yield;
                    if(chosen == null)
                        return;
                    parent = chosen;
                }
                var files = new Gee.ArrayList<File>();
                files.add(item.file);
                operations.run.begin(OperationKind.MOVE, files, parent, window);
            }
        }
        async void empty_trash()
        {
            if(!(yield Dialogs.confirm(window, "Empty Trash?", "All items in Trash will be permanently deleted.", "Empty Trash")))
                return;
            var model = new DirectoryModel();
            yield model.open(File.new_for_uri("trash:///"), window);
            var files = new Gee.ArrayList<File>();
            for(uint i = 0; i < model.items.get_n_items(); i++)
                files.add(((FileItem)model.items.get_item(i)).file);
            model.cancel();
            operations.run.begin(OperationKind.DELETE, files, null, window);
        }
        async void terminal()
        {
            try {
                var items = current.selected();
                var folder = items.size == 1 && items[0].directory ? items[0].file : current.location;
                if(!folder.is_native())
                    throw new FileError.UNSUPPORTED("A local folder is required");
                var process = new Subprocess.newv({"xdg-terminal-exec", "--dir=" + folder.get_path()}, SubprocessFlags.NONE);
                yield process.wait_check_async(null);
            }
            catch(Error e) {
                Dialogs.error(window, _("The configured Majoris terminal could not be opened: ") + e.message);
            }
        }
        async void open_with()
        {
            var items = current.selected();
            if(items.size != 1)
                return;
            var launcher = new Gtk.FileLauncher(items[0].file);
            launcher.always_ask = true;
            try {
                yield launcher.launch(window, null);
            }
            catch(Error e) {
                if(!(e is IOError.CANCELLED))
                    Dialogs.error(window, e.message);
            }
        }
        async void link()
        {
            var items = current.selected();
            if(items.size != 1 || !items[0].file.is_native())
                return;
            var name = yield Dialogs.prompt(window, "Create Link", items[0].name + " link");
            if(name == null)
                return;
            try {
                if(!Paths.valid_name(name))
                    throw new FileError.INVALID("Invalid name");
                var names = new Gee.HashMap<string, string>();
                names[items[0].file.get_uri()] = name;
                yield operations.run(OperationKind.LINK, files(items), current.location, window, null, names);
            }
            catch(Error e) {
                Dialogs.error(window, e.message);
            }
        }
        async void custom_icon(bool reset)
        {
            var items = current.selected();
            if(items.size == 0)
                return;
            try {
                string uri = "";
                if(!reset)
                {
                    var dialog = new Gtk.FileDialog();
                    dialog.title = _("Choose Custom Icon");
                    var filter = new Gtk.FileFilter();
                    filter.name = "Images";
                    filter.add_mime_type("image/*");
                    var filters = new GLib.ListStore(typeof(Gtk.FileFilter));
                    filters.append(filter);
                    dialog.filters = filters;
                    var icon = yield dialog.open(window, null);
                    if(!icon.is_native())
                        throw new FileError.UNSUPPORTED("Custom icons must be local images");
                    uri = icon.get_uri();
                }
                foreach(var item in items)
                {
                    var info = new FileInfo();
                    info.set_attribute_string("metadata::custom-icon", uri);
                    yield item.file.set_attributes_async(info, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null, null);
                }
                current.navigate(current.location, false);
            }
            catch(Error e) {
                if(!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED))
                    Dialogs.error(window, e.message);
            }
        }
        async void batch_rename()
        {
            var items = current.selected();
            if (items.size > 0) new BatchRenameDialog(window, items, operations);
        }
        async void templates()
        {
            var path = Environment.get_user_special_dir(UserDirectory.TEMPLATES);
            if(path == null)
                return;
            ChooserOptions options;
            try {
                options = new ChooserOptions(false, new VariantBuilder(VariantType.VARDICT).end());
            }
            catch(Error e) {
                Dialogs.error(window, e.message);
                return;
            }
            options.initial = File.new_for_path(path);
            var chooser = new ChooserWindow(options, metadata, new Places());
            chooser.title = _("New Document from Template");
            chooser.transient_for = window;
            chooser.completed.connect((code, result) => { if(code != 0)
                                                              return;
                                                          var files = new Gee.ArrayList<File>();
                                                          files.add(File.new_for_uri(result.lookup_value("uris", null).get_child_value(0).get_string()));
                                                          operations.run.begin(OperationKind.COPY, files, current.location, window);
                });
            chooser.present();
        }
        async void select_pattern()
        {
            var pattern = yield Dialogs.prompt(window, "Select by Filename Pattern", "*");
            if(pattern == null)
                return;
            current.active_selection.unselect_all();
            for(uint i = 0; i < current.active_selection.get_n_items(); i++)
                if(PatternSpec.match_simple(pattern, ((FileItem)current.active_selection.get_item(i)).name))
                    current.active_selection.select_item(i, false);
        }
        async void smb_password()
        {
            var dialog = new Adw.AlertDialog(_("SMB Account Password"), "Set a password for network access to your local account.");
            var password = new Gtk.PasswordEntry();
            dialog.extra_child = password;
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("set", _("Set Password"));
            if((yield dialog.choose(window, null)) != "set")
                return;
            try {
                SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                yield helper.provision_password(password.text);
                password.text = "";
            }
            catch(Error e) {
                password.text = "";
                Dialogs.error(window, e.message);
            }
        }
        async void connect_server()
        {
            var uri = yield Dialogs.prompt(window, "Connect to Server — SMB, SFTP, FTP, or WebDAV", "smb://");
            if(uri == null)
                return;
            var file = Paths.parse(uri);
            if(file.is_native() || !uri.contains("://"))
            {
                Dialogs.error(window, _("Enter a server URI"));
                return;
            }
            current.navigate(file);
        }
    }
}
