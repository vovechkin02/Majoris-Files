namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/chooser.ui")]
    public class ChooserWindow : Adw.Window {
        private bool template_disposing;
        public Browser browser;
        OperationManager creation_operations;
        public ChooserOptions options;
        public signal void completed(uint response, Variant results);
        [GtkChild] private unowned Gtk.Entry filename;
        [GtkChild] private unowned Gtk.Button accept;
        [GtkChild] private unowned Gtk.DropDown filters;
        bool finished;
        bool accepting;
        uint location_generation;
        VolumeMonitor volumes;
        ulong mount_removed;
        Cancellable token = new Cancellable();
        Gee.HashMap<string, Gtk.Widget> choice_widgets = new Gee.HashMap<string, Gtk.Widget>();
        ChooserState state;
        MetadataStore metadata;
        [GtkChild] private unowned Gtk.ProgressBar transfer_progress;
        [GtkChild] private unowned Gtk.Box box;
        [GtkChild] private unowned Gtk.Label filename_label;
        [GtkChild] private unowned Gtk.Button new_folder;
        [GtkChild] private unowned Gtk.Button preview_button;
        [GtkChild] private unowned Gtk.Button cancel_button;
        [GtkChild] private unowned Gtk.Label summary;
        public ChooserWindow(ChooserOptions options, MetadataStore metadata, Places places, string application_id = "")
        {
            Object(title: options.save ? "Save As" : (options.directory ? "Select Folder" : "Open"), default_width: 960, default_height: 660, modal: options.modal);
            this.options = options;
            this.metadata = metadata;
            creation_operations = new OperationManager(metadata);
            volumes = VolumeMonitor.get();
            mount_removed = volumes.mount_removed.connect((mount) => {
                var root = mount.get_root();
                bool affected = browser.location.equal(root) || browser.location.has_prefix(root);
                foreach (var item in browser.selected())
                    affected = affected || item.file.equal(root) || item.file.has_prefix(root);
                if (!finished && affected)
                {
                    location_generation++;
                    token.cancel();
                    token = new Cancellable();
                    browser.cancel();
                    browser.selection.unselect_all();
                    browser.navigate(File.new_for_path(Environment.get_home_dir()));
                    Dialogs.error(this, _("The device or network location was disconnected. Select the file again after reconnecting, or choose another location."));
                }
            });
            state = new ChooserState(metadata, application_id);
            state.apply(options);
            browser = new Browser(metadata, places, true);
            default_width = state.dimension("width", 960, 560, 2400);
            default_height = state.dimension("height", 660, 400, 1600);
            browser.sidebar_width = state.dimension("sidebar-width", 180, 120, 420);
            browser.folders_only = options.directory;
            browser.rename_requested.connect((state) => rename_created.begin(state));
            new_folder.clicked.connect(() => create_folder.begin());
            browser.location_changed.connect(() => new_folder.sensitive = browser.accepts_destination);
            browser.directory.loaded.connect(() => new_folder.sensitive = browser.accepts_destination);
            preview_button.clicked.connect(() => {
                browser.preview.visible = !browser.preview.visible;
                var chosen = browser.selected();
                if (chosen.size > 0 && browser.preview.visible) browser.preview.show_item.begin(chosen[0]);
            });
            box.prepend(browser);
            filename_label.visible = filename.visible = options.save && !options.save_many;
            filename.text = options.current_name;
            filename.activate.connect(() => accept_selection.begin());
            filters.visible = options.filters.size > 0;
            if (options.filters.size > 0) {
                string[] names = {};
                foreach (var filter in options.filters) names += filter.name;
                filters.model = new Gtk.StringList(names);
                filters.selected = options.selected_filter;
                filters.notify["selected"].connect(() => {
                    options.selected_filter = filters.selected;
                    browser.chooser_filter = options.filters[(int)filters.selected];
                    browser.refilter();
                });
                browser.chooser_filter = options.filters[(int)filters.selected];
            }
            cancel_button.clicked.connect(() => finish(1, new VariantBuilder(VariantType.VARDICT).end()));
            accept.label = options.accept_label != "" ? options.accept_label : (options.save ? _("Save") : options.directory ? _("Select") : _("Open"));
            accept.clicked.connect(() => accept_selection.begin());
            summary.visible = options.save_many;
            summary.label = _("Choose a destination folder for %u files. Existing files are kept; conflicting names receive a number.").printf(options.filenames.size);
            add_choices(box);
            browser.error.connect((message) => { Dialogs.error(this, message);
                });
            browser.activated.connect((item) => { if (options.save)
                                                      filename.text = item.name;
                                                  else { browser.select_file(item.file);
                                                         accept_selection.begin();
                                                  }
                });
            browser.selection_changed.connect(() => { var chosen = browser.selected();
                                                      if (!options.multiple && chosen.size > 1)
                                                          browser.selection.select_item(browser.selection.get_selection().get_minimum(), true);
                });
            browser.preview.visible = state.get("preview", "false") == "true";
            initialize.begin();
            close_request.connect(() => { finish(1, new VariantBuilder(VariantType.VARDICT).end());
                                          return true;
                });
            var keys = new Gtk.EventControllerKey();
            keys.key_pressed.connect((key, code, mods) => {
                                                            if (browser.inline_rename != null) return false;
                                                            if (key == Gdk.Key.Escape)
                                                            {
                                                                finish(1, new VariantBuilder(VariantType.VARDICT).end());
                                                                return true;
                                                            }
                                                            if (key == Gdk.Key.Return && !filename.has_focus && !browser.path.has_focus && !browser.search_entry.has_focus)
                                                            {
                                                                accept_selection.begin();
                                                                return true;
                                                            }
                                                            if (key == Gdk.Key.space && !filename.has_focus && !browser.path.has_focus && !browser.search_entry.has_focus)
                                                            {
                                                                browser.preview.visible = !browser.preview.visible;
                                                                var chosen = browser.selected();
                                                                if (chosen.size > 0 && browser.preview.visible)
                                                                    browser.preview.show_item.begin(chosen[0]);
                                                                return true;
                                                            }
                                                            return false;
                });
            ((Gtk.Widget)this).add_controller(keys);
        }
        async void initialize()
        {
            accept.sensitive = false;
            File? candidate = options.initial;
            while(candidate != null && !finished)
            {
                try {
                    var info = yield candidate.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                    if(info.get_file_type() == FileType.DIRECTORY)
                        break;
                }
                catch(IOError.NOT_MOUNTED e) {
                    break;
                }
                catch(IOError.CANCELLED e) {
                    return;
                }
                catch(IOError.NOT_FOUND e) {}
                catch(Error e) {
                    if(!finished)
                        Dialogs.error(this, e.message);
                    break;
                }
                candidate = candidate.get_parent();
            }
            if(finished)
                return;
            browser.navigate(candidate ?? File.new_for_path(Environment.get_home_dir()));
            browser.set_view(state.get("view", "Grid"), false);
            if(options.current_file != null)
                browser.select_file(options.current_file);
            accept.sensitive = true;
        }
        public void cancel_request()
        {
            finish(1, new VariantBuilder(VariantType.VARDICT).end());
        }
        void finish(uint response, Variant results)
        {
            if (finished)
                return;
            finished = true;
            volumes.disconnect(mount_removed);
            state.set("view", browser.view_mode);
            state.set("preview", browser.preview.visible ? "true" : "false");
            state.set("sidebar-width", browser.sidebar_width.to_string());
            if(get_width() > 0 && get_height() > 0)
            {
                state.set("width", get_width().to_string());
                state.set("height", get_height().to_string());
            }
            if(response == 0 && !browser.location.has_uri_scheme("majoris") && !browser.location.has_uri_scheme("recent"))
                state.set(options.save ? "save-location" : "open-location", browser.location.get_uri());
            token.cancel();
            browser.cancel();
            completed(response, results);
            destroy();
        }
        async void rename_created(InlineRename state) {
            try {
                var info = yield state.item.file.query_info_async("id::file", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                if (state.cancelled || browser.inline_rename != state) return;
                var identity = state.item.info.get_attribute_string("id::file");
                if (identity != null && identity != info.get_attribute_string("id::file"))
                    throw new IOError.NOT_FOUND("The created folder has been replaced; select it again.");
                var result = yield creation_operations.rename(state.item.file, state.proposed);
                browser.finish_inline_rename(state, result);
            } catch (Error e) { browser.retry_inline_rename(state, e.message); }
        }
        async void create_folder() {
            if (!browser.accepts_destination || finished) return;
            var parent = browser.location;
            var context = browser.active_selection;
            uint epoch = browser.start_creation();
            try {
                var file = yield creation_operations.create_default(parent, true);
                if (!finished) yield browser.edit_created(file, parent, epoch, context);
            } catch (Error e) { if (!finished) Dialogs.error(this, e.message); }
        }

        public async void accept_selection()
        {
            if (finished || accepting)
                return;
            if (browser.inline_rename != null) {
                browser.submit_inline_rename();
                if (browser.inline_rename != null) return;
            }
            accepting = true;
            uint generation = location_generation;
            var selection_token = token;
            accept.sensitive = false;
            try {
                var files = new Gee.ArrayList<File>();
                var filter = options.filters.size > 0 ? options.filters[(int)options.selected_filter] : null;
                if (options.save_many)
                {
                    var chosen = browser.selected();
                    if (chosen.size > 1)
                        throw new FileError.INVALID("Select one destination folder");
                    var folder = chosen.size == 1 ? chosen[0].file : browser.location;
                    if (folder.has_uri_scheme("majoris") || folder.has_uri_scheme("recent")) throw new FileError.INVALID(_("Choose a real writable folder."));
                    files = yield options.destinations(folder, token);
                }
                else if (options.save)
                {
                    if (!browser.accepts_destination) throw new FileError.INVALID(_("Choose a real writable folder to save your file."));
                    string name = filter == null ? filename.text : filter.filename(filename.text);
                    if (!Paths.valid_name(name))
                        throw new FileError.INVALID("Enter a valid filename");
                    var parent = yield browser.location.query_info_async("standard::type,access::can-write", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                    if (parent.get_file_type() != FileType.DIRECTORY || (parent.has_attribute("access::can-write") && !parent.get_attribute_boolean("access::can-write")))
                        throw new FileError.INVALID("This folder is not writable");
                    var target = browser.location.get_child(name);
                    bool exists = false;
                    try {
                        var info = yield target.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                        if (info.get_file_type() == FileType.DIRECTORY)
                            throw new FileError.INVALID("The name belongs to a folder");
                        exists = true;
                    }
                    catch (IOError.NOT_FOUND e) {}
                    if (exists && !(yield Dialogs.confirm(this, "“" + name + "” already exists.", "Replacing it will overwrite the existing file.", "Replace")))
                    {
                        accepting = false;
                        accept.sensitive = true;
                        return;
                    }
                    files.add(target);
                }
                else {
                    var chosen = browser.selected();
                    if (options.directory && chosen.size == 0) {
                        if (browser.virtual_collection) throw new FileError.INVALID(_("Select a real folder."));
                        files.add(browser.location);
                    }
                    foreach (var item in chosen)
                    {
                        transfer_progress.visible = true;
                        yield CloudFiles.get_default().materialize(item.file, new ImportPolicy(metadata).maximum_bytes, token, (fraction, message) => {
                            transfer_progress.fraction = fraction < 0 ? 0 : fraction;
                            transfer_progress.text = message;
                        });
                        transfer_progress.visible = false;
                        var info = yield item.file.query_info_async("standard::type,access::can-read", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                        if ((info.get_file_type() == FileType.DIRECTORY) != options.directory)
                            throw new FileError.INVALID(options.directory ? "Select a folder" : "Select a file");
                        if(info.has_attribute("access::can-read") && !info.get_attribute_boolean("access::can-read"))
                            throw new FileError.INVALID("The selected item is not readable");
                        if (filter != null && !filter.matches(item))
                            throw new FileError.INVALID("The selection does not match the file type");
                        files.add(item.file);
                    }
                    if (files.size == 0 || (!options.multiple && files.size != 1))
                        throw new FileError.INVALID("Select a file");
                    foreach (var file in files)
                        yield file.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                }
                string[] uris = {};
                foreach (var file in files)
                {
                    var path = file.get_path();
                    if (path == null && !options.save && !options.directory)
                    {
                        if (!(yield Dialogs.confirm(this, "Download a local copy?", "This location cannot be shared directly with the requesting application. Download a separate, retained local copy using your remote download preferences? Changes to it will not update the remote original. The document portal controls the requesting application's access.", "Download Copy")))
                            throw new IOError.CANCELLED("Download declined");
                        selection_token.set_error_if_cancelled();
                        transfer_progress.visible = true;
                        path = (yield ChooserImport.download(file, selection_token, null, new ImportPolicy(metadata), (done, total) => {
                            transfer_progress.fraction = total == 0 ? 0 : (double)done / total;
                            transfer_progress.text = "Downloading %s / %s".printf(Paths.size(done), Paths.size(total));
                        })).get_path();
                        transfer_progress.visible = false;
                    }
                    if (path == null)
                        throw new FileError.UNSUPPORTED(options.save ? "This remote destination has no local GVfs bridge. Reconnect it with GVfs/FUSE before saving so writes reach the intended folder." : "This location has no local GVfs bridge. Copy the file to a local folder before selecting it. The document portal cannot grant access to this remote URI.");
                    // The default GVfs implementation maps a FUSE pathname
                    // back to its remote URI. The document portal needs the
                    // actual file: bridge URI, not that reverse translation.
                    uris += Vfs.get_local().get_file_for_path(path).get_uri();
                }
                selection_token.set_error_if_cancelled();
                if (!finished && generation == location_generation)
                    finish(0, ChooserOptions.response(uris, filter, choice_results()));
            }
            catch (Error e) {
                if (!finished && !(e is IOError.CANCELLED))
                    Dialogs.error(this, e.message);
            }
            accepting = false;
            transfer_progress.visible = false;
            if (!finished)
                accept.sensitive = true;
        }
        void add_choices(Gtk.Box box)
        {
            if (options.choices == null)
                return;
            for (size_t i = 0; i < options.choices.n_children(); i++)
            {
                var choice = options.choices.get_child_value(i);
                string id = choice.get_child_value(0).get_string();
                string label = choice.get_child_value(1).get_string();
                var values = choice.get_child_value(2);
                string initial = choice.get_child_value(3).get_string();
                if (values.n_children() == 0)
                {
                    var check = new Gtk.CheckButton.with_label(label);
                    check.active = initial == "true";
                    box.append(check);
                    choice_widgets[id] = check;
                }
                else {
                    string[] labels = {};
                    uint selected = 0;
                    for (size_t j = 0; j < values.n_children(); j++)
                    {
                        var pair = values.get_child_value(j);
                        labels += pair.get_child_value(1).get_string();
                        if (pair.get_child_value(0).get_string() == initial)
                            selected = (uint)j;
                    }
                    var row = new ChooserChoiceRow(); row.label.label = label;
                    var combo = row.combo; combo.model = new Gtk.StringList(labels);
                    combo.selected = selected;
                    box.append(row);
                    choice_widgets[id] = combo;
                }
            }
        }
        Variant choice_results()
        {
            var result = new VariantBuilder(new VariantType("a(ss)"));
            if (options.choices != null)
                for (size_t i = 0; i < options.choices.n_children(); i++)
                {
                    var choice = options.choices.get_child_value(i);
                    string id = choice.get_child_value(0).get_string();
                    var widget = choice_widgets[id];
                    string value;
                    if (widget is Gtk.CheckButton)
                        value = ((Gtk.CheckButton)widget).active ? "true" : "false";
                    else value = choice.get_child_value(2).get_child_value(((Gtk.DropDown)widget).selected).get_child_value(0).get_string();
                    result.add("(ss)", id, value);
                }
            return result.end();
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                finished = true;
                if (browser != null) browser.cancel();
                if (token != null) token.cancel();
                content = null;
                dispose_template(typeof(ChooserWindow));
            }
            base.dispose();
        }
    }
}
