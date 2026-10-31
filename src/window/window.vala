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
        ExtensionManager extension_manager;
        Adw.TabPage? menu_page;
        public Browser? current {
            get {
                return tabs.selected_page == null ? null : tabs.selected_page.child as Browser;
            }
        }
        public FilesWindow(Gtk.Application app, MetadataStore metadata, Places places, OperationManager operations, File? initial = null, bool blank = false)
        {
            Object(application: app, title: _("Files"), default_width: 1100, default_height: 740);
            this.metadata = metadata;
            this.places = places;
            this.operations = operations;
            operations.renamed.connect((source, result) => {
                for (int i = 0; i < tabs.n_pages; i++)
                    ((Browser)tabs.get_nth_page(i).child).reconcile_history_rename(source, result);
            });
            operations.conflict_presentation = (dialog, source, destination) => ConflictThumbnails.attach(dialog, source, destination, metadata);
            extension_manager = ExtensionManager.get_default(metadata);
            foreach(var extension in extension_manager.extensions)if("nearby" in extension.capabilities)providers.register_nearby(new ExternalNearby(extension));
            foreach (var extension in extension_manager.extensions) providers.register_provider(extension);
            metadata.changed.connect(()=>{for(int i=0;i<tabs.n_pages;i++){ var browser=(Browser)tabs.get_nth_page(i).child; extension_manager.columns.begin(browser); tabs.get_nth_page(i).title = location_title(browser.location); }});
            close_request.connect(() => { for(int i = 0; i < tabs.n_pages; i++)
                                              ((Browser)tabs.get_nth_page(i).child).cancel();
                                          return false;
                });
            providers.register_provider(new ScriptActions(metadata));
            providers.register_provider(new DiskImageActions());
            providers.register_provider(new DesktopActions());
            var provider_action = new SimpleAction("provider-action", VariantType.STRING);
            provider_action.activate.connect((target) => {
                providers.execute.begin(target.get_string(), current.selected(), this, (obj, res) => { try { providers.execute.end(res);
                                                                                                       }
                                                                                                       catch(Error e) { if(!(e is IOError.CANCELLED) && !(e is Gtk.DialogError.DISMISSED))
                                                                                                                            Dialogs.error(this, e.message);
                                                                                                       }
                    });
            });
            add_action(provider_action);
            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            header.title_widget = new Adw.WindowTitle("Files", "");
            header.pack_start(Browser.button("tab-new-symbolic", _("New Tab"), () => new_tab(current.location)));
            var progress = new Gtk.MenuButton();
            MenuPresentation.button(progress);
            progress.icon_name = "folder-download-symbolic";
            progress.tooltip_text = _("File Operations");
            var popover = new Gtk.Popover();
            popover.has_arrow = false;
            var jobs = new Gtk.ListBox();
            jobs.selection_mode = Gtk.SelectionMode.NONE;
            jobs.bind_model(operations.jobs, (obj) => { var job = (Job)obj;
                                                        var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
                                                        var label = new Gtk.Label(job.error != "" ? job.error : job.current == "" ? job.title : job.current);
                                                        var bar = new Gtk.ProgressBar();
                                                        bar.fraction = job.progress;
                                                        var cancel = new Gtk.Button.with_label(_("Cancel"));
                                                        cancel.sensitive = !job.done;
                                                        cancel.clicked.connect(() => job.cancellable.cancel());
                                                        var retry = new Gtk.Button.with_label(_("Retry Remaining Items"));
                                                        retry.visible = job.can_retry;
                                                        retry.clicked.connect(() => operations.retry.begin(job, this, (obj, res) => {
                    try { operations.retry.end(res);
                    }
                    catch(Error e) { Dialogs.error(this, e.message);
                    }
                }));
                                                        box.append(label);
                                                        box.append(bar);
                                                        box.append(cancel);
                                                        box.append(retry);
                                                        job.notify.connect(() => { label.label = job.error != "" ? job.error : job.current;
                                                                                   if(job.cancelled)
                                                                                       label.label = _("Cancelled · ") + job.current;
                                                                                   bar.fraction = job.progress;
                                                                                   cancel.sensitive = !job.done;
                                                                                   retry.visible = job.can_retry;
                                                                                   retry.sensitive = !job.retrying;
                                                            });
                                                        return box;
                });
            popover.child = jobs;
            progress.popover = popover;
            header.pack_end(progress);
            var menu = new Menu();
            menu.append(_("Manage Tags…"), "win.manage-tags");
            menu.append("Shared Folders", "win.shared-folders");
            menu.append("Recover Previous Replaced Files…", "win.recover-replacements");
            menu.append("Recover Interrupted Batch Rename…", "win.recover-rename");
            foreach (var entry in new string[] {"New Window|app.new-window", "New Tab|win.new-tab", "Reopen Closed Tab|win.reopen", "Duplicate Tab|win.duplicate-tab", "New Folder|win.new-folder", "New Empty File|win.new-file", "Show Hidden Files|win.hidden", "Preview Pane|win.preview", "Sort by Name|win.sort-name", "Sort by Size|win.sort-size", "Sort by Modified|win.sort-modified", "Descending Order|win.descending", "Save Search|win.save-search", "Preferences|win.preferences", "Keyboard Shortcuts|win.shortcuts"})
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
            MenuPresentation.button(menu_button);
            menu_button.icon_name = "open-menu-symbolic";
            menu_button.menu_model = menu;
            header.pack_end(menu_button);
            toolbar.add_top_bar(header);
            var tabbar = new Adw.TabBar();
            tabbar.add_css_class("majoris-document-tabs");
            tabbar.view = tabs;
            tabbar.autohide = false;
            tabbar.expand_tabs = false;
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
            header.pack_end(Browser.button("view-grid-symbolic", _("Tab Overview"), () => overview.open = !overview.open));
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
            tabs.notify["selected-page"].connect(() => { for (int i = 0; i < tabs.n_pages; i++) { var browser = tabs.get_nth_page(i).child as Browser; if (browser != null && browser != current) browser.cancel_inline_rename(); } update_commands(); var recorder = app as SessionRecorder;
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
            action("preview", () => { if(current.narrow)
                                      {
                                          quick_preview();
                                          return;
                                      }
                                      current.preview.visible = !current.preview.visible;
                                      var chosen = current.selected();
                                      if (chosen.size > 0 && current.preview.visible)
                                          current.preview.show_item.begin(chosen[0]);
                });
            action("new-folder", () => create_folder.begin());
            action("new-file", () => create_file.begin());
            action("rename", () => rename.begin());
            var rename_keys = new Gtk.EventControllerKey();
            rename_keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            rename_keys.key_pressed.connect((key, code, mods) => {
                if (current == null || current.inline_rename == null) return false;
                Gtk.Entry? editor = null;
                for (var widget = get_focus(); widget != null; widget = widget.get_parent())
                    if (widget is Gtk.Entry) { editor = (Gtk.Entry)widget; break; }
                if (editor == null) return false;
                if (key == Gdk.Key.F2) { current.begin_inline_rename(); return true; }
                if (key == Gdk.Key.Escape) { current.cancel_inline_rename(); current.file_surface.grab_focus(); return true; }
                // Forward exactly once directly to the entry's native handlers.
                if (key == Gdk.Key.Tab || key == Gdk.Key.ISO_Left_Tab) { current.submit_inline_rename(); return false; }
                return rename_keys.forward(get_focus());
            });
            ((Gtk.Widget)this).add_controller(rename_keys);
            var rename_click = new Gtk.GestureClick();
            rename_click.button = 1;
            rename_click.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            rename_click.pressed.connect((n, x, y) => {
                if (current == null || current.inline_rename == null || current.inline_rename.pending) return;
                var picked = pick(x, y, Gtk.PickFlags.DEFAULT);
                for (var widget = picked; widget != null; widget = widget.get_parent())
                    if (widget is FilenameCell && ((FilenameCell)widget).transaction == current.inline_rename) return;
                current.submit_inline_rename();
            });
            ((Gtk.Widget)this).add_controller(rename_click);


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
                                             PropertiesDialog.present_selection(this, chosen, metadata);
                });
            action("source-folder", () => { var chosen = current.selected(); if (chosen.size == 1 && chosen[0].file.get_parent() != null) { var file = chosen[0].file; current.navigate(file.get_parent()); current.select_file(file); } });
            action("favorite", () => { bool all = true; foreach (var item in current.selected()) all = all && metadata.favorite(item.file);
                                       foreach (var item in current.selected()) metadata.set_favorite(item.file, !all);
                });
            action("open", () => { var items = current.selected(); if (items.size == 1) current.activate_item.begin(items[0]); });
            action("open-selected-tab", () => { var items = current.selected(); if (items.size == 1 && items[0].directory) new_tab(items[0].file); });
            action("tags", () => set_tags.begin());
            action("quick-preview", () => quick_preview());
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
            action("shortcuts", () => new ShortcutsDialog().present(this));
            app.set_accels_for_action("win.shortcuts", {"<Control>question"});
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
            // Let native toolbar controls handle Space instead of the global
            // file-preview accelerator. The existing action and shortcut remain.
            notify["focus-widget"].connect(() => {
                var preview_action = lookup_action("quick-preview") as SimpleAction;
                if (preview_action != null) preview_action.set_enabled(command_available("quick-preview"));
            });
            if (!blank)
                new_tab(initial ?? File.new_for_uri("recent:///"));
            close_request.connect(() => { for (int i = 0; i < tabs.n_pages; i++)
                                              ((Browser)tabs.get_nth_page(i).child).cancel();
                                          return false;
                });
        }
        void action(string name, owned Callback callback)
        {
            var a = new SimpleAction(name, null);
            a.activate.connect(() => { if (command_available(name)) callback(); });
            add_action(a);
        }
        public bool command_available(string name) {
            if (current == null) return false;
            if (name == "quick-preview") {
                for (var widget = get_focus(); widget != null; widget = widget.get_parent())
                    if (widget is Majoris.Ui.Toolbar) return false;
            }
            if (name in new string[] {"new-folder", "new-file", "paste", "split", "join", "duplicate-items", "folder-with-selection", "paste-link", "compress", "compress-sevenzip", "compress-encrypted", "extract", "extract-encrypted", "link", "templates"})
                return current.accepts_destination;
            int count = current.selected().size;
            if (name == "rename") return current.inline_rename != null ? !current.inline_rename.pending : count > 1 || current.can_inline_rename();
            if (name == "share-folder") return count == 1 && current.selected()[0].directory && current.selected()[0].file.is_native();
            if (name in new string[] {"cut", "copy", "trash", "delete", "favorite", "properties"}) return count > 0;
            return true;
        }
        public void update_commands() {
            if (current != null) {
                var share_menu = new Menu();
                if (command_available("share-folder")) share_menu.append(_("Share Folder…"), "win.share-folder");
                var provider_menu = providers.menu(current.selected(), true);
                if (provider_menu.get_n_items() > 0) share_menu.append_section(null, provider_menu);
                var existing = current.share_button.menu_model as Menu;
                if (existing == null) current.share_button.menu_model = share_menu;
                else if (!MenuPresentation.equal(existing, share_menu)) { existing.remove_all(); for (int i = 0; i < share_menu.get_n_items(); i++) existing.append_item(new MenuItem.from_model(share_menu, i)); }
                current.share_button.sensitive = share_menu.get_n_items() > 0 && current.selected().size > 0;
            }
            foreach (var name in new string[] {"new-folder", "new-file", "paste", "split", "join", "rename", "share-folder", "cut", "copy", "trash", "delete", "favorite", "properties", "quick-preview"}) {
                var command = lookup_action(name) as SimpleAction;
                if (command != null) command.set_enabled(command_available(name));
            }
        }
        string location_title(File file) {
            if (MetadataStore.is_tag_location(file)) { var tag = metadata.tag_at(file); return tag == null ? _("Deleted Tag") : tag.name; }
            if (file.has_uri_scheme("recent")) return _("Recent");
            if (file.get_uri() == "majoris:///favorites") return _("Favorites");
            if (file.equal(File.new_for_path(Environment.get_home_dir()))) return _("Home");
            return file.get_basename() ?? file.get_parse_name();
        }
        public void new_tab(File location)
        {
            var browser = new Browser(metadata, places);
            var page = tabs.append(browser);
            page.title = location_title(location);
            browser.location_changed.connect((file) => page.title = location_title(file));
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
            browser.link_requested.connect((files, target) => {
                var root = browser.get_root() as FilesWindow;
                if(root != null)
                    root.operations.run.begin(OperationKind.LINK, files, target, root);
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
            browser.rename_requested.connect((state) => commit_inline_rename.begin(browser, state));
            browser.selection_changed.connect(() => { var window = browser.get_root() as FilesWindow; if (window != null) window.update_commands(); });
            browser.location_changed.connect(() => { var window = browser.get_root() as FilesWindow; if (window != null) window.update_commands(); });
            browser.navigate(location);
            browser.open_in_tab.connect((file) => { var root = browser.get_root() as FilesWindow;
                                                    if(root != null)
                                                        root.new_tab(file);
                });
            var context = new Menu();
            var popup = new Gtk.PopoverMenu.from_model(context);
            popup.has_arrow = false;
            popup.set_parent(browser.file_surface);
            weak Gtk.Widget? context_focus = null;
            popup.closed.connect(() => { if (context_focus != null && context_focus.get_mapped()) context_focus.grab_focus(); });
            extension_manager.columns.begin(browser);
            var click = new Gtk.GestureClick();
            click.button = 3;
            click.pressed.connect((n, x, y) => {
                click.set_state(Gtk.EventSequenceState.CLAIMED);
                Gdk.Rectangle rect = {(int)x, (int)y, 1, 1};
                var root = browser.get_root() as FilesWindow;
                context.remove_all();
                popup.pointing_to = rect;
                browser.target_context(x, y);
                if (root != null) { context_focus = root.get_focus(); root.open_context.begin(context, browser, popup); }
            });
            browser.file_surface.add_controller(click);
            var context_keys = new Gtk.EventControllerKey();
            context_keys.propagation_phase = Gtk.PropagationPhase.CAPTURE;
            context_keys.key_pressed.connect((key, code, modifiers) => {
                if (key != Gdk.Key.Menu && !(key == Gdk.Key.F10 && (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0))
                    return false;
                var root = browser.get_root() as FilesWindow;
                if (root == null || root.get_focus() is Gtk.Editable || root.get_focus() is Gtk.TextView)
                    return false;
                Gdk.Rectangle rect = {browser.file_surface.get_width() / 2, browser.file_surface.get_height() / 3, 1, 1};
                popup.pointing_to = rect;
                context_focus = root.get_focus();
                root.open_context.begin(context, browser, popup);
                return true;
            });
            browser.file_surface.add_controller(context_keys);
        }
        uint context_generation;
        public void populate_context(Menu menu, Browser browser)
        {
            var selection = browser.selected();
            bool one = selection.size == 1;
            bool trash = browser.location.has_uri_scheme("trash");
            bool writable = browser.accepts_destination;
            if (selection.size == 0) {
                var creation = new Menu();
                if (trash) creation.append(_("Empty Trash"), "win.empty-trash");
                else if (writable) {
                    creation.append(_("New Folder…"), "win.new-folder");
                    creation.append(_("New File…"), "win.new-file");
                    var formats = get_clipboard().get_formats();
                    if (formats.contain_mime_type("text/uri-list") || formats.contain_mime_type("x-special/gnome-copied-files") || formats.contain_gtype(typeof(Gdk.FileList)))
                        creation.append(_("Paste"), "win.paste");
                }
                MenuPresentation.section(menu, creation);
                var display = new Menu();
                display.append_submenu(_("Sort By…"), browser.sort_menu());
                display.append_submenu(_("Group By…"), browser.group_menu());
                display.append_submenu(_("View…"), browser.view_menu());
                MenuPresentation.section(menu, display);
                var location = new Menu(); location.append(_("Refresh"), "context.refresh");
                if (browser.location.is_native()) location.append(_("Open in Terminal"), "win.terminal");
                MenuPresentation.section(menu, location);
                return;
            }
            if (trash) {
                var recovery = new Menu(); recovery.append(_("Restore"), "win.restore"); recovery.append(_("Delete Permanently"), "win.delete");
                MenuPresentation.section(menu, recovery);
            } else {
                var opening = new Menu();
                if (one) {
                    opening.append(_("Open"), "win.open");
                    if (selection[0].directory) opening.append(_("Open in New Tab"), "win.open-selected-tab");
                    else {
                        opening.append(_("Open With…"), "win.open-with");
                        if (browser.supports_preview(selection[0])) opening.append(_("Preview"), "win.quick-preview");
                        if (writable && new ArchivePreview().supports(selection[0])) opening.append(_("Extract…"), "win.extract");
                    }
                }
                MenuPresentation.section(menu, opening);
                var editing = new Menu();
                bool mutable = true;
                foreach (var item in selection) if (item.info.has_attribute("access::can-delete") && !item.info.get_attribute_boolean("access::can-delete")) mutable = false;
                if (mutable) editing.append(_("Cut"), "win.cut");
                editing.append(_("Copy"), "win.copy");
                if (mutable) {
                    editing.append(one ? _("Rename") : _("Batch Rename…"), one ? "win.rename" : "win.batch-rename");
                    editing.append(_("Move to Trash"), "win.trash");
                }
                MenuPresentation.section(menu, editing);
                var organisation = new Menu(); bool all = true;
                foreach (var item in selection) all = all && metadata.favorite(item.file);
                organisation.append(all ? _("Remove from Favorites") : _("Add to Favorites"), "win.favorite");
                organisation.append(_("Tags…"), "win.tags");
                if (one && PropertiesDialog.shareable(selection[0])) organisation.append(_("Share…"), "win.share-folder");
                MenuPresentation.section(menu, organisation);
                var more = new Menu(); var files = new Menu();
                files.append(_("Copy To…"), "win.copy-to");
                if (mutable) files.append(_("Move To…"), "win.move-to");
                if (writable) {
                    files.prepend(_("Duplicate"), "win.duplicate-items");
                    if (mutable) files.append(_("New Folder with Selection…"), "win.folder-with-selection");
                    if (one && selection[0].file.is_native()) files.append(_("Create Link…"), "win.link");
                }
                if (browser.virtual_collection && one) files.append(_("Open Source Folder"), "win.source-folder");
                MenuPresentation.section(more, files);
                var tools = new Menu();
                if (writable) tools.append(_("Compress…"), "win.compress");
                if (one && selection[0].info.get_file_type() == FileType.REGULAR) {
                    tools.append(_("Checksums…"), "win.checksum");
                    if (writable) {
                        tools.append(_("Split File…"), "win.split");
                        bool joinable = selection[0].name.has_suffix(".parts.json");
                        try { SplitService.raw_name(selection[0].file); joinable = true; } catch (Error e) {}
                        if (joinable) tools.append(_("Join Split File…"), "win.join");
                    }
                }
                MenuPresentation.section(more, tools);
                var quick = new Menu();
                if (one && ImageRotation.supports(selection[0]) && mutable) {
                    quick.append(_("Rotate Clockwise"), "win.rotate-clockwise");
                    quick.append(_("Rotate Counterclockwise"), "win.rotate-counterclockwise");
                }
                var extensions = new Menu();
                if (quick.get_n_items() > 0) extensions.append_submenu(_("Quick Actions…"), quick);
                var user = providers.menu(selection);
                if (user.get_n_items() > 0) extensions.append_submenu(_("User Actions…"), user);
                MenuPresentation.section(more, extensions);
                if (one) {
                    var cloud = new Menu(); var state = CloudFiles.get_default().peek(selection[0].file);
                    if (state != null) {
                        if ("pin" in state.capabilities) cloud.append(_("Make Available Offline"), "win.cloud-pin");
                        if ("evict" in state.capabilities) cloud.append(_("Free Local Space"), "win.cloud-evict");
                        if ("retry" in state.capabilities) cloud.append(_("Retry Cloud Sync"), "win.cloud-retry");
                    }
                    MenuPresentation.section(more, cloud);
                }
                if (more.get_n_items() > 0) { var secondary = new Menu(); secondary.append_submenu(_("More Actions…"), more); MenuPresentation.section(menu, secondary); }
            }
            var properties = new Menu(); properties.append(_("Properties"), "win.properties"); MenuPresentation.section(menu, properties);
        }
        async void open_context(Menu menu, Browser browser, Gtk.Popover popup)
        {
            uint generation = ++context_generation;
            var selection = browser.selected(); var location = browser.location;
            menu.remove_all(); populate_context(menu, browser); popup.popup();
            if (selection.size == 0) return;
            yield extension_manager.prepare(selection);
            if (generation != context_generation || browser.get_root() != this || !popup.visible || !browser.location.equal(location)) return;
            var current = browser.selected();
            if (current.size != selection.size) return;
            for (int i = 0; i < current.size; i++) if (!current[i].file.equal(selection[i].file)) return;
            menu.remove_all(); populate_context(menu, browser);
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
            if(current == null || !current.accepts_destination)
                return;
            var destination = current.location;
            try {
                var content = yield FileClipboard.read(get_clipboard());
                if(content.files.size > 0)
                    if (current.location.equal(destination) && current.accepts_destination) yield operations.run(content.cut ? OperationKind.MOVE : OperationKind.COPY, content.files, destination, this);
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
            if (current.selected().size > 1) { lookup_action("batch-rename").activate(null); return; }
            current.begin_inline_rename();
        }
        async void commit_inline_rename(Browser browser, InlineRename state)
        {
            try {
                // Validate identity after model refreshes, before warnings and mutation.
                var info = yield state.item.file.query_info_async("id::file,standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                var identity = state.item.info.get_attribute_string("id::file");
                if (identity != null && identity != info.get_attribute_string("id::file"))
                    throw new IOError.NOT_FOUND("The original item has changed. Cancel and select it again.");
                if (state.cancelled || browser.inline_rename != state) return;
                if (!state.item.directory && InlineRename.extension(state.item.name) != InlineRename.extension(state.proposed) && metadata.state("extension-warning", "true") == "true") {
                    if (!(yield Dialogs.confirm(this, "Change File Extension?", "Changing the extension can change which application opens this file.", "Rename"))) {
                        browser.retry_inline_rename(state, ""); return;
                    }
                }
                if (state.cancelled || browser.inline_rename != state) return;
                // Confirmation can remain open while the directory changes.
                info = yield state.item.file.query_info_async("id::file", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                if (state.cancelled || browser.inline_rename != state) return;
                if (identity != null && identity != info.get_attribute_string("id::file"))
                    throw new IOError.NOT_FOUND("The original item has changed. Cancel and select it again.");
                var result = yield operations.rename(state.item.file, state.proposed);
                browser.finish_inline_rename(state, result);
            } catch (Error e) {
                browser.retry_inline_rename(state, e.message);
            }
        }
        async void permanent_delete()
        {
            var files = selected_files();
            if (files.size > 0 && (metadata.state("confirm-delete", "true") != "true" || (yield Dialogs.confirm(this, "Permanently delete selected items?", "This cannot be undone.", "Delete"))))
                operations.run.begin(OperationKind.DELETE, files, null, this);
        }
        async void set_tags() {
            var items = current.selected(); if (items.size > 0) new TagAssignmentDialog(metadata, items).present(this);
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
            var pane = new PreviewPane(metadata);
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
            new ChecksumDialog(this, items[0].file, operations);
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
            new PreferencesDialog(metadata).present(this);
        }
    }
}
