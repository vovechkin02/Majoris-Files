namespace MajorisFiles {
    public interface SessionRecorder : Object {
        public abstract void queue_session_save();
    }
    public class FilesWindow : Adw.ApplicationWindow {
        public Adw.TabView tabs = new Adw.TabView();
        MetadataStore metadata;
        Places places;
        OperationManager operations;
        Gee.ArrayList<File> closed = new Gee.ArrayList<File>();
        ExtraActions extra;
        QuickActionRegistry providers = new QuickActionRegistry();
        Adw.TabPage? menu_page;
        public Browser? current {
            get {
                return tabs.selected_page == null ? null : tabs.selected_page.child as Browser;
            }
        }
        public FilesWindow(Gtk.Application app, MetadataStore metadata, Places places, OperationManager operations, File? initial = null, bool blank = false)
        {
            Object(application: app, title: "Files", default_width: 1100, default_height: 740);
            this.metadata = metadata;
            this.places = places;
            this.operations = operations;
            close_request.connect(() => { for(int i = 0; i < tabs.n_pages; i++)
                                              ((Browser)tabs.get_nth_page(i).child).cancel();
                                          return false;
                });
            providers.register_provider(new ScriptActions(metadata));
            providers.register_provider(new DiskImageActions());
            var provider_action = new SimpleAction("provider-action", VariantType.STRING);
            provider_action.activate.connect((target) => {
                providers.execute.begin(target.get_string(), current.selected(), this, (obj, res) => { try { providers.execute.end(res);
                                                                                                       }
                                                                                                       catch(Error e) { Dialogs.error(this, e.message);
                                                                                                       }
                    });
            });
            add_action(provider_action);
            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.title_widget = new Adw.WindowTitle("Files", "");
            header.pack_start(Browser.button("tab-new-symbolic", "New Tab", () => new_tab(current.location)));
            var progress = new Gtk.MenuButton();
            progress.icon_name = "folder-download-symbolic";
            progress.tooltip_text = "File Operations";
            var popover = new Gtk.Popover();
            var jobs = new Gtk.ListBox();
            jobs.selection_mode = Gtk.SelectionMode.NONE;
            jobs.bind_model(operations.jobs, (obj) => { var job = (Job)obj;
                                                        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
                                                        var label = new Gtk.Label(job.title);
                                                        var bar = new Gtk.ProgressBar();
                                                        var cancel = new Gtk.Button.with_label("Cancel");
                                                        cancel.clicked.connect(() => job.cancellable.cancel());
                                                        box.append(label);
                                                        box.append(bar);
                                                        box.append(cancel);
                                                        job.notify.connect(() => { label.label = job.error != "" ? job.error : job.current;
                                                                                   bar.fraction = job.progress;
                                                                                   cancel.sensitive = !job.done;
                                                            });
                                                        return box;
                });
            popover.child = jobs;
            progress.popover = popover;
            header.pack_end(progress);
            var menu = new Menu();
            foreach (var entry in new string[] {"New Window|app.new-window", "New Tab|win.new-tab", "Reopen Closed Tab|win.reopen", "Duplicate Tab|win.duplicate-tab", "New Folder|win.new-folder", "New Empty File|win.new-file", "Show Hidden Files|win.hidden", "Preview Pane|win.preview", "Sort by Name|win.sort-name", "Sort by Size|win.sort-size", "Sort by Modified|win.sort-modified", "Descending Order|win.descending", "Bookmarks: Add Current Folder|win.bookmark", "Save Search|win.save-search", "Preferences|win.preferences"})
            {
                var parts = entry.split("|", 2);
                menu.append(parts[0], parts[1]);
            }
            foreach(var entry in new string[] {"Connect to Server|win.connect-server", "New Document from Template|win.templates", "Batch Rename|win.batch-rename", "Create Link|win.link", "Select by Pattern|win.select-pattern", "Invert Selection|win.invert-selection", "Select None|win.select-none", "Restore from Trash|win.restore", "Empty Trash|win.empty-trash", "Open in Terminal|win.terminal", "SMB Account Password|win.smb-password"})
            {
                var parts = entry.split("|", 2);
                menu.append(parts[0], parts[1]);
            }
            var menu_button = new Gtk.MenuButton();
            menu_button.icon_name = "open-menu-symbolic";
            menu_button.menu_model = menu;
            header.pack_end(menu_button);
            toolbar.add_top_bar(header);
            var tabbar = new Adw.TabBar();
            tabbar.view = tabs;
            var tab_menu = new Menu();
            foreach(var entry in new string[] {"Duplicate|win.tab-duplicate", "Pin / Unpin|win.tab-pin", "Move Left|win.tab-left", "Move Right|win.tab-right", "Move to New Window|win.tab-detach", "Close Other Tabs|win.tab-close-others", "Close Tabs to the Right|win.tab-close-right", "Close|win.tab-close"})
            {
                var parts = entry.split("|");
                tab_menu.append(parts[0], parts[1]);
            }
            tabs.menu_model = tab_menu;
            tabs.setup_menu.connect((page) => menu_page = page);
            action("tab-duplicate", () => { var page = menu_page ?? tabs.selected_page;
                                            if(page != null)
                                            {
                                                var browser = (Browser)page.child;
                                                new_tab(browser.directory.location);
                                                current.set_view(browser.view_mode);
                                            }
                });
            action("tab-pin", () => { var page = menu_page ?? tabs.selected_page;
                                      if(page != null)
                                          tabs.set_page_pinned(page, !page.pinned);
                });
            action("tab-left", () => { var page = menu_page ?? tabs.selected_page;
                                       if(page != null)
                                           tabs.reorder_backward(page);
                });
            action("tab-right", () => { var page = menu_page ?? tabs.selected_page;
                                        if(page != null)
                                            tabs.reorder_forward(page);
                });
            action("tab-close", () => { var page = menu_page ?? tabs.selected_page;
                                        if(page != null)
                                            tabs.close_page(page);
                });
            action("tab-close-others", () => { var page = menu_page ?? tabs.selected_page;
                                               if(page != null)
                                                   tabs.close_other_pages(page);
                });
            action("tab-close-right", () => { var page = menu_page ?? tabs.selected_page;
                                              if(page != null)
                                                  tabs.close_pages_after(page);
                });
            action("tab-detach", () => {
                var page = menu_page ?? tabs.selected_page;
                if(page == null)
                    return;
                var window = new FilesWindow(app, metadata, places, operations, null, true);
                tabs.transfer_page(page, window.tabs, 0);
                window.present();
                if(tabs.n_pages == 0)
                    close();
            });
            toolbar.add_top_bar(tabbar);
            toolbar.content = tabs;
            var overview = new Adw.TabOverview();
            overview.view = tabs;
            overview.child = toolbar;
            content = overview;
            header.pack_end(Browser.button("view-grid-symbolic", "Tab Overview", () => overview.open = !overview.open));
            tabs.close_page.connect((page) => { var browser = page.child as Browser;
                                                if (browser != null)
                                                {
                                                    closed.add(browser.location);
                                                    browser.cancel();
                                                }
                                                tabs.close_page_finish(page, true);
                                                if (tabs.n_pages == 0)
                                                    close();
                                                return true;
                });
            tabs.create_window.connect(() => { var window = new FilesWindow(app, metadata, places, operations, null, true);
                                               window.present();
                                               return window.tabs;
                });
            tabs.notify["selected-page"].connect(() => { var recorder = app as SessionRecorder;
                                                         if(recorder != null)
                                                             recorder.queue_session_save();
                });
            action("new-tab", () => new_tab(current.location));
            action("close-tab", () => tabs.close_page(tabs.selected_page));
            action("reopen", () => { if (closed.size > 0)
                                         new_tab(closed.remove_at(closed.size - 1));
                });
            action("duplicate-tab", () => new_tab(current.location));
            action("hidden", () => { current.show_hidden = !current.show_hidden;
                                     current.refilter();
                });
            action("preview", () => { current.preview.visible = !current.preview.visible;
                                      var chosen = current.selected();
                                      if (chosen.size > 0 && current.preview.visible)
                                          current.preview.show_item.begin(chosen[0]);
                });
            action("new-folder", () => create_folder.begin());
            action("new-file", () => create_file.begin());
            action("rename", () => rename.begin());
            action("trash", () => operations.run.begin(OperationKind.TRASH, selected_files(), null, this));
            action("delete", () => permanent_delete.begin());
            action("copy", () => copy(false));
            action("cut", () => copy(true));
            action("paste", () => paste.begin());
            action("undo", () => operations.undo.begin(this, (obj, res) => { try { operations.undo.end(res);
                                                                             }
                                                                             catch (Error e) { Dialogs.error(this, e.message);
                                                                             }
                }));
            action("redo", () => operations.redo.begin((obj, res) => { try { operations.redo.end(res);
                                                                       }
                                                                       catch (Error e) { Dialogs.error(this, e.message);
                                                                       }
                }));
            action("properties", () => { var chosen = current.selected();
                                         if (chosen.size > 0)
                                             Dialogs.show_properties(this, chosen, metadata);
                });
            action("favorite", () => { foreach (var item in current.selected())
                                           metadata.set_favorite(item.file, !metadata.favorite(item.file));
                });
            action("tags", () => set_tags.begin());
            action("quick-preview", () => quick_preview());
            action("bookmark", () => places.add_bookmark.begin(current.location, (obj, res) => { try { places.add_bookmark.end(res);
                                                                                                 }
                                                                                                 catch (Error e) { Dialogs.error(this, e.message);
                                                                                                 }
                }));
            action("save-search", () => save_search.begin());
            action("sort-name", () => current.set_sort("Name", true));
            action("sort-size", () => current.set_sort("Size", true));
            action("sort-modified", () => current.set_sort("Modified", true));
            action("descending", () => current.set_sort("Name", false));
            action("checksum", () => checksum.begin());
            action("split", () => { var items = current.selected();
                                    if(items.size == 1 && !items[0].directory)
                                        new SplitDialog(this, items[0], current.location, operations);
                });
            action("join", () => join.begin());
            action("preferences", () => preferences());
            action("manage-tags", () => new TagsDialog(metadata).present(this));
            string[] names = {
                "new-tab", "close-tab", "reopen", "hidden", "new-folder", "rename", "trash", "delete", "copy", "cut", "paste", "undo", "redo", "properties", "quick-preview"
            };
            string[] shortcuts = {
                "<Control>t", "<Control>w", "<Control><Shift>t", "<Control>h", "<Control><Shift>n", "F2", "Delete", "<Shift>Delete", "<Control>c", "<Control>x", "<Control>v", "<Control>z", "<Control><Shift>z", "<Alt>Return", "space"
            };
            for (int i = 0; i < names.length; i++)
                app.set_accels_for_action("win." + names[i], {shortcuts[i]});
            extra = new ExtraActions(this, operations, metadata);
            if (!blank)
                new_tab(initial ?? File.new_for_uri("majoris:///home"));
            close_request.connect(() => { for (int i = 0; i < tabs.n_pages; i++)
                                              ((Browser)tabs.get_nth_page(i).child).cancel();
                                          return false;
                });
        }
        void action(string name, owned Callback callback)
        {
            var a = new SimpleAction(name, null);
            a.activate.connect(() => callback());
            add_action(a);
        }
        public void new_tab(File location)
        {
            var browser = new Browser(metadata, places);
            var page = tabs.append(browser);
            page.title = location.get_basename() ?? "Files";
            browser.location_changed.connect((file) => page.title = file.get_basename() ?? file.get_parse_name());
            browser.session_changed.connect(() => { var root = browser.get_root() as FilesWindow;
                                                    var recorder = root == null ? null : root.application as SessionRecorder;
                                                    if(recorder != null)
                                                        recorder.queue_session_save();
                });
            browser.error.connect((message) => { var root = browser.get_root() as Gtk.Window;
                                                 if(root != null)
                                                     Dialogs.error(root, message);
                });
            browser.transfer_requested.connect((files, target, move) => { var root = browser.get_root() as FilesWindow;
                                                                          if(root != null)
                                                                              root.operations.run.begin(move ? OperationKind.MOVE : OperationKind.COPY, files, target, root);
                });
            browser.activated.connect((item) => {
                var root = browser.get_root() as FilesWindow;
                if(root == null)
                    return;
                FileLaunch.open.begin(item, root, (obj, res) => { try { FileLaunch.open.end(res);
                                                                        Gtk.RecentManager.get_default().add_item(item.file.get_uri());
                                                                        root.metadata.record_open(item.file);
                                                                  }
                                                                  catch (Error e) { if(!(e is IOError.CANCELLED) && !(e is Gtk.DialogError.DISMISSED))
                                                                                        Dialogs.error(root, e.message);
                                                                  }
                    });
            });
            tabs.selected_page = page;
            browser.navigate(location);
            browser.open_in_tab.connect((file) => { var root = browser.get_root() as FilesWindow;
                                                    if(root != null)
                                                        root.new_tab(file);
                });
            var context = new Menu();
            foreach (var entry in new string[] {"Open Preview|win.quick-preview", "Cut|win.cut", "Copy|win.copy", "Paste|win.paste", "Rename|win.rename", "Favorite|win.favorite", "Tags|win.tags", "Calculate SHA-256|win.checksum", "Split File|win.split", "Join Split File|win.join", "Move to Trash|win.trash", "Properties|win.properties"})
            {
                var parts = entry.split("|", 2);
                context.append(parts[0], parts[1]);
            }
            context.append("Open With…", "win.open-with");
            context.append("Default Application…", "win.associations");
            context.append("Custom Icon…", "win.custom-icon");
            context.append("Reset Icon", "win.reset-icon");
            var quick = new Menu();
            quick.append("Compress…", "win.compress");
            quick.append("Create Encrypted ZIP…", "win.compress-encrypted");
            quick.append("Extract…", "win.extract");
            quick.append("Extract with Password…", "win.extract-encrypted");
            quick.append("Split File…", "win.split");
            quick.append("Join Split File…", "win.join");
            context.append_submenu("Quick Actions", quick);
            context.append("Share Folder…", "win.share-folder");
            context.append("Permissions…", "win.permissions");
            var popup = new Gtk.PopoverMenu.from_model(context);
            var extensions = new Menu();
            context.append_submenu("User Actions", extensions);
            popup.set_parent(browser);
            var click = new Gtk.GestureClick();
            click.button = 3;
            click.pressed.connect((n, x, y) => { Gdk.Rectangle rect = {(int)x, (int)y, 1, 1};
                                                 var root = browser.get_root() as FilesWindow;
                                                 extensions.remove_all();
                                                 if(root != null)
                                                     extensions.append_section(null, root.providers.menu(browser.selected()));
                                                 popup.pointing_to = rect;
                                                 popup.popup();
                });
            browser.add_controller(click);
        }
        Gee.ArrayList<File> selected_files()
        {
            var files = new Gee.ArrayList<File>();
            foreach (var item in current.selected())
                files.add(item.file);
            return files;
        }
        void copy(bool cut)
        {
            FileClipboard.publish(get_clipboard(), selected_files(), cut);
        }
        async void paste()
        {
            if(current == null)
                return;
            var destination = current.location;
            try {
                var content = yield FileClipboard.read(get_clipboard());
                if(content.files.size > 0)
                    yield operations.run(content.cut ? OperationKind.MOVE : OperationKind.COPY, content.files, destination, this);
            }
            catch(Error e) {
                Dialogs.error(this, e.message);
            }
        }
        async void create_folder()
        {
            var name = yield Dialogs.prompt(this, "New Folder");
            if (name == null)
                return;
            try {
                yield operations.new_folder(current.location, name);
            }
            catch (Error e) {
                Dialogs.error(this, e.message);
            }
        }
        async void create_file()
        {
            var name = yield Dialogs.prompt(this, "New Empty File");
            if (name == null)
                return;
            try {
                if (!Paths.valid_name(name))
                    throw new FileError.INVALID("Invalid filename");
                var stream = yield current.location.get_child(name).create_async(FileCreateFlags.NONE, Priority.DEFAULT, null);
                yield stream.close_async(Priority.DEFAULT, null);
            }
            catch (Error e) {
                Dialogs.error(this, e.message);
            }
        }
        async void rename()
        {
            var chosen = current.selected();
            if (chosen.size != 1)
                return;
            var name = yield Dialogs.prompt(this, "Rename", chosen[0].name);
            if (name == null)
                return;
            try {
                yield operations.rename(chosen[0].file, name);
            }
            catch (Error e) {
                Dialogs.error(this, e.message);
            }
        }
        async void permanent_delete()
        {
            var files = selected_files();
            if (files.size > 0 && (yield Dialogs.confirm(this, "Permanently delete selected items?", "This cannot be undone.", "Delete")))
                operations.run.begin(OperationKind.DELETE, files, null, this);
        }
        async void set_tags()
        {
            var items = current.selected();
            var tags = yield Dialogs.prompt(this, "Tags (comma separated)", items.size == 1 ? metadata.tags(items[0].file) : "");
            if (tags != null)
                foreach (var item in items)
                    metadata.set_tags(item.file, tags);
        }
        async void save_search()
        {
            var name = yield Dialogs.prompt(this, "Save Search");
            if (name != null && name.strip() != "")
                metadata.save_search(name, current.location, current.saved_query());
        }
        void quick_preview()
        {
            var items = current.selected();
            if (items.size == 0)
                return;
            var initial = items[0];
            int index = 0;
            if(items.size == 1)
            {
                items.clear();
                for(uint i = 0; i < current.active_selection.get_n_items(); i++)
                {
                    var item = (FileItem)current.active_selection.get_item(i);
                    if(item.file.equal(initial.file))
                        index = items.size;
                    items.add(item);
                }
            }
            var window = new Adw.Window();
            window.title = initial.name;
            window.transient_for = this;
            window.default_width = 720;
            window.default_height = 560;
            var pane = new PreviewPane();
            window.content = pane;
            pane.show_item.begin(initial);
            var keys = new Gtk.EventControllerKey();
            keys.key_pressed.connect((key, code, mods) => { if (key == Gdk.Key.Escape || key == Gdk.Key.space)
                                                            {
                                                                pane.cancel();
                                                                window.close();
                                                                return true;
                                                            }
                                                            if (key == Gdk.Key.Right || key == Gdk.Key.Left)
                                                            {
                                                                index = (index + (key == Gdk.Key.Right ? 1 : -1) + items.size) % items.size;
                                                                window.title = items[index].name;
                                                                pane.show_item.begin(items[index]);
                                                                return true;
                                                            }
                                                            return false;
                });
            ((Gtk.Widget)window).add_controller(keys);
            window.close_request.connect(() => { pane.cancel();
                                                 return false;
                });
            window.present();
        }
        async void checksum()
        {
            var items = current.selected();
            if (items.size != 1 || items[0].directory)
                return;
            var job = operations.start("SHA-256");
            try {
                var hash = yield SplitService.checksum(items[0].file, ChecksumType.SHA256, job.cancellable);
                operations.finish(job);
                var dialog = new Adw.AlertDialog("SHA-256", hash);
                dialog.add_response("close", "Close");
                dialog.present(this);
            }
            catch (Error e) {
                operations.finish(job, e);
            }
        }
        async void join()
        {
            var items = current.selected();
            if (items.size != 1)
                return;
            var file = items[0].file;
            var job = operations.start("Join Split File");
            try {
                if(!file.get_basename().has_suffix(".parts.json"))
                {
                    var manifest = file.get_parent().get_child(SplitService.raw_name(file) + ".parts.json");
                    bool exists = true;
                    try {
                        yield manifest.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, job.cancellable);
                    }
                    catch(IOError.NOT_FOUND e) {
                        exists = false;
                    }
                    if(exists)
                        file = manifest;
                    else {
                        if(!(yield Dialogs.confirm(this, "Join Without a Manifest?", "Part numbering and sizes will be checked, but the original checksum and final part count are unknown. Confirm that all parts are present.", "Join Parts")))
                        {
                            operations.finish(job);
                            return;
                        }
                        yield SplitService.join_raw(file, current.location, job);
                        operations.finish(job);
                        return;
                    }
                }
                yield SplitService.join(file, current.location, job);
                operations.finish(job);
            }
            catch (Error e) {
                operations.finish(job, e);
            }
        }
        void preferences()
        {
            var window = new Adw.PreferencesDialog();
            window.title = "Preferences";
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            group.title = "Browsing";
            var hidden = new Adw.SwitchRow();
            hidden.title = "Show Hidden Files";
            hidden.active = current.show_hidden;
            hidden.notify["active"].connect(() => { current.show_hidden = hidden.active;
                                                    current.refilter();
                });
            group.add(hidden);
            var notifications = new Adw.SwitchRow();
            notifications.title = "Notify About Background Operations";
            notifications.active = metadata.state("notifications", "true") == "true";
            notifications.notify["active"].connect(() => metadata.set_state("notifications", notifications.active ? "true" : "false"));
            group.add(notifications);
            var scripts = new Adw.SwitchRow();
            scripts.title = "Enable User Scripts";
            scripts.subtitle = Path.build_filename(Environment.get_user_data_dir(), "majoris-files", "scripts");
            scripts.active = metadata.state("scripts-enabled", "false") == "true";
            scripts.notify["active"].connect(() => metadata.set_state("scripts-enabled", scripts.active ? "true" : "false"));
            group.add(scripts);
            var restore = new Adw.SwitchRow();
            restore.title = "Restore Tabs After an Unexpected Exit";
            restore.active = metadata.state("restore-session", "true") == "true";
            restore.notify["active"].connect(() => metadata.set_state("restore-session", restore.active ? "true" : "false"));
            group.add(restore);
            page.add(group);
            window.add(page);
            var tags_button = new Gtk.Button.with_label("Manage Tags");
            tags_button.clicked.connect(() => new TagsDialog(metadata).present(this));
            group.add(tags_button);
            var home_group = new Adw.PreferencesGroup();
            home_group.title = "Home Sections";
            page.add(home_group);
            foreach(var entry in new string[] {"favorites|Favorites", "recent|Recent", "downloads|Recent Downloads", "recommended|Recommended"})
            {
                var parts = entry.split("|");
                string key = "home-" + parts[0];
                var toggle = new Adw.SwitchRow();
                toggle.title = parts[1];
                toggle.active = metadata.state(key, "true") == "true";
                toggle.notify["active"].connect(() => metadata.set_state(key, toggle.active ? "true" : "false"));
                home_group.add(toggle);
            }
            window.present(this);
        }
    }
}
