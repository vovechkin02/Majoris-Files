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
            action("compress", () => compress.begin());
            action("extract", () => extract.begin());
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
        void action(string name, owned Callback callback)
        {
            var action = new SimpleAction(name, null);
            action.activate.connect(() => callback());
            window.add_action(action);
        }
        async void compress()
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
                Dialogs.error(window, "Choose a supported archive extension");
                return;
            }
            var files = new Gee.ArrayList<File>();
            foreach (var item in items)
                files.add(item.file);
            var job = operations.start("Compress");
            try {
                yield ArchiveService.compress(files, current.location.get_child(name), format, job);
                operations.finish(job);
            }
            catch (Error e) {
                operations.finish(job, e);
                Dialogs.error(window, e.message);
            }
        }
        async void extract()
        {
            var items = current.selected();
            if(items.size != 1 || items[0].directory)
                return;
            var name = yield Dialogs.prompt(window, "Extract to New Folder", items[0].name + " extracted");
            if(name == null)
                return;
            if(!Paths.valid_name(name))
            {
                Dialogs.error(window, "Invalid folder name");
                return;
            }
            var job = operations.start("Extract");
            try {
                yield ArchiveService.extract(items[0].file, current.location.get_child(name), job);
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
                Dialogs.error(window, "The configured Majoris terminal could not be opened: " + e.message);
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
                yield current.location.get_child(name).make_symbolic_link_async(items[0].file.get_path(), Priority.DEFAULT, null);
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
                    dialog.title = "Choose Custom Icon";
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
            if(items.size == 0)
                return;
            var pattern = yield Dialogs.prompt(window, "Batch Rename — {original}, {counter}, {date}", "{original} - {counter}");
            if(pattern == null)
                return;
            var names = new Gee.ArrayList<string>();
            var seen = new Gee.HashSet<string>();
            var preview = new StringBuilder();
            int counter = 1;
            foreach(var item in items)
            {
                var date = item.info.get_modification_date_time();
                string name = pattern.replace("{original}", item.name).replace("{counter}", "%03d".printf(counter++)).replace("{date}", date == null ? "" : date.format("%Y-%m-%d"));
                if(!Paths.valid_name(name) || !seen.add(name))
                {
                    Dialogs.error(window, "The pattern produces an invalid or duplicate name");
                    return;
                }
                names.add(name);
                if(counter <= 20)
                    preview.append(item.name + " → " + name + "\n");
            }
            if(!(yield Dialogs.confirm(window, "Apply Batch Rename?", preview.str, "Rename")))
                return;
            try {
                foreach(var item in items)
                    if(!item.file.get_parent().equal(items[0].file.get_parent()))
                        throw new FileError.INVALID("Batch rename requires a shared folder");
                var folder = items[0].file.get_parent();
                foreach(var name in names)
                {
                    bool occupied = false;
                    try {
                        yield folder.get_child(name).query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
                        occupied = true;
                    }
                    catch(IOError.NOT_FOUND e) {}
                    if(occupied)
                    {
                        bool ours = false;
                        foreach(var item in items)
                            if(item.file.get_basename() == name)
                                ours = true;
                        if(!ours)
                            throw new FileError.CONFLICT("Destination already exists: " + name);
                    }
                }
                var temp = new Gee.ArrayList<File>();
                try {
                    foreach(var item in items)
                    {
                        var moved = yield item.file.set_display_name_async(".majoris-rename-" + Uuid.string_random(), Priority.DEFAULT, null);
                        temp.add(moved);
                    }
                    for(int i = 0; i < temp.size; i++)
                    {
                        var result = yield temp[i].set_display_name_async(names[i], Priority.DEFAULT, null);
                        metadata.relocate(items[i].file, result);
                        temp[i] = result;
                    }
                }
                catch(Error e) {
                    for(int i = 0; i < temp.size; i++)
                    {
                        try {
                            yield temp[i].set_display_name_async(items[i].file.get_basename(), Priority.DEFAULT, null);
                        }
                        catch(Error rollback) {}
                    }
                    throw e;
                }
            }
            catch(Error e) {
                Dialogs.error(window, e.message);
            }
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
            chooser.title = "New Document from Template";
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
            var dialog = new Adw.AlertDialog("SMB Account Password", "Set a password for network access to your local account.");
            var password = new Gtk.PasswordEntry();
            dialog.extra_child = password;
            dialog.add_response("cancel", "Cancel");
            dialog.add_response("set", "Set Password");
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
                Dialogs.error(window, "Enter a server URI");
                return;
            }
            current.navigate(file);
        }
    }
}
