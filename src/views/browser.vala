namespace MajorisFiles {
    public class Browser : Gtk.Box {
        public DirectoryModel directory = new DirectoryModel();
        public History history = new History();
        public SearchController search = new SearchController();
        SearchQuery search_query = new SearchQuery();
        public string saved_query()
        {
            search_query.text = search_entry.text;
            search_query.scope = everywhere ? "everywhere" : recursive ? "recursive" : "folder";
            return search_query.serialize();
        }
        public Gtk.MultiSelection selection;
        public Gtk.MultiSelection active_selection {
            get {
                return view_mode == "Columns" && column_selection != null ? column_selection : selection;
            }
        }
        public signal void transfer_requested(Gee.ArrayList<File> files, File target, bool move);
        public File location {
            owned get {
                if(directory.location.get_uri() == "majoris:///home")
                    return File.new_for_path(Environment.get_home_dir());
                return view_mode == "Columns" && column_folder != null ? column_folder : directory.location;
            }
        }
        public bool show_hidden = false;
        public ChooserFilter? chooser_filter;
        public bool folders_only;
        public string view_mode = "Grid";
        public MetadataStore metadata;
        public Places places;
        public PreviewPane preview = new PreviewPane();
        public Gtk.Entry path = new Gtk.Entry();
        public Gtk.SearchEntry search_entry = new Gtk.SearchEntry();
        public signal void activated(FileItem item);
        public signal void selection_changed();
        public signal void location_changed(File location);
        public signal void session_changed();
        public signal void error(string message);
        Gtk.CustomFilter filter;
        Gtk.CustomSorter sorter;
        Gtk.FilterListModel filtered;
        Gtk.SortListModel sorted;
        Gtk.Stack views = new Gtk.Stack();
        HomeView home;
        Gtk.ListBox sidebar = new Gtk.ListBox();
        Gtk.Label status = new Gtk.Label("");
        Adw.Banner location_error = new Adw.Banner("");
        Gtk.Box columns = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 1);
        Gtk.MultiSelection? column_selection;
        File? column_folder;
        Gee.ArrayList<DirectoryModel> column_models = new Gee.ArrayList<DirectoryModel>();
        Gee.HashMap<Gtk.Widget, Gtk.MultiSelection> column_selections = new Gee.HashMap<Gtk.Widget, Gtk.MultiSelection>();
        Gee.HashMap<Gtk.Widget, ulong?> column_handlers = new Gee.HashMap<Gtk.Widget, ulong?>();
        Gee.HashMap<Gtk.Widget, uint> column_generations = new Gee.HashMap<Gtk.Widget, uint>();
        Gee.HashMap<Gtk.Widget, DirectoryModel> pending_columns = new Gee.HashMap<Gtk.Widget, DirectoryModel>();
        Gee.HashMap<Gtk.Widget, DirectoryModel> loaded_columns = new Gee.HashMap<Gtk.Widget, DirectoryModel>();
        PreviewPane gallery_preview = new PreviewPane();
        Gtk.Stack location_bar = new Gtk.Stack();
        Gtk.Box breadcrumbs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Box searches;
        Gtk.Paned sidebar_pane;
        public int sidebar_width {
            get {
                return sidebar_pane.position;
            }
            set {
                sidebar_pane.position = value.clamp(120, 420);
            }
        }
        Gtk.DropDown modes;
        bool chooser_mode;
        public signal void open_in_tab(File file);
        bool recursive;
        bool everywhere;
        bool search_results;
        Gtk.ToggleButton recursive_button;
        bool ascending = true;
        string sort_key = "Name";
        bool folders_first = true;
        int icon_size = 64;
        bool selection_checkboxes;
        string caption_key = "None";
        Gee.HashMap<string, ColumnProvider> column_providers = new Gee.HashMap<string, ColumnProvider>();
        bool loading_display;
        public signal void display_changed();
        Gtk.ColumnView details;
        Gee.HashMap<string, Gtk.ColumnViewColumn> detail_columns = new Gee.HashMap<string, Gtk.ColumnViewColumn>();
        string[] column_titles = {
            "Name", "Size", "Type", "Modified", "Created", "Accessed", "Owner", "Group", "Permissions", "MIME Type", "Location", "Tags", "Favorite", "Trash Date"
        };
        File? initial_selection;
        Gee.ArrayList<File> remembered_selection = new Gee.ArrayList<File>();
        uint navigation_generation;
        uint scroll_restore;
        LocationSuggestions location_suggestions;
        Gtk.Popover completion_popup = new Gtk.Popover();
        Gtk.ListBox completion_list = new Gtk.ListBox();
        Cancellable completion_token = new Cancellable();
        uint completion_delay;
        ThumbnailService thumbnails = new ThumbnailService();
        Gee.HashMap<Gtk.ListItem, Cancellable> thumbnail_jobs = new Gee.HashMap<Gtk.ListItem, Cancellable>();
        uint sidebar_generation;
        public Browser(MetadataStore metadata, Places places, bool chooser_mode = false)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.metadata = metadata;
            this.places = places;
            this.chooser_mode = chooser_mode;
            metadata.changed.connect(() => display_changed());
            location_suggestions = new LocationSuggestions(metadata);
            home = new HomeView(metadata);
            views.add_named(home, "Home");
            home.activated.connect((item) => activate_item.begin(item));
            directory.items.items_changed.connect((position, removed, added) => {
                for(uint i = position; i < position + added; i++)
                    metadata.reconcile((FileItem)directory.items.get_item(i));
            });
            filter = new Gtk.CustomFilter((obj) => { var item = (FileItem)obj;
                                                     return (show_hidden || !item.info.get_is_hidden() || (initial_selection != null && initial_selection.equal(item.file))) && (!folders_only || item.navigable || item.info.get_is_symlink()) && (chooser_filter == null || chooser_filter.matches(item)) && (search_results || search_query.matches(item, metadata));
                });
            sorter = new Gtk.CustomSorter((a, b) => compare_items((FileItem)a, (FileItem)b));
            filtered = new Gtk.FilterListModel(directory.items, filter);
            sorted = new Gtk.SortListModel(filtered, sorter);
            sorted.items_changed.connect(() => update_status());
            selection = new Gtk.MultiSelection(sorted);
            var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            toolbar.margin_start = 8;
            toolbar.margin_end = 8;
            toolbar.margin_top = 6;
            toolbar.margin_bottom = 6;
            toolbar.append(button("go-previous-symbolic", "Back", () => { var file = history.back();
                                                                          if (file != null)
                                                                              navigate(file, false);
                }));
            toolbar.append(button("go-next-symbolic", "Forward", () => { var file = history.forward();
                                                                         if (file != null)
                                                                             navigate(file, false);
                }));
            toolbar.append(button("go-up-symbolic", "Parent Folder", () => { var parent = location.get_parent();
                                                                             if (parent != null)
                                                                                 navigate(parent);
                }));
            path.hexpand = true;
            path.placeholder_text = "Location or URI";
            path.tooltip_text = "Location (Ctrl+L)";
            path.activate.connect(() => { completion_popup.popdown();
                                          navigate(Paths.parse(path.text));
                });
            completion_popup.set_parent(path);
            completion_popup.autohide = false;
            completion_popup.has_arrow = false;
            completion_list.selection_mode = Gtk.SelectionMode.NONE;
            var suggestions_scroll = new Gtk.ScrolledWindow();
            suggestions_scroll.max_content_height = 280;
            suggestions_scroll.propagate_natural_height = true;
            suggestions_scroll.min_content_width = 380;
            suggestions_scroll.child = completion_list;
            completion_popup.child = suggestions_scroll;
            var completion_keys = new Gtk.EventControllerKey();
            completion_keys.key_pressed.connect((key) => {
                if(key == Gdk.Key.Down && completion_popup.visible)
                {
                    var row = completion_list.get_row_at_index(0);
                    if(row != null && row.child != null)
                    {
                        row.child.grab_focus();
                        return true;
                    }
                }
                if(key == Gdk.Key.Escape)
                    completion_popup.popdown();
                return false;
            });
            path.add_controller(completion_keys);
            path.changed.connect(() => {
                completion_token.cancel();
                if(completion_delay != 0)
                    Source.remove(completion_delay);
                completion_delay = 0;
                if(location_bar.visible_child_name != "entry")
                    return;
                completion_delay = Timeout.add(150, () => {
                    completion_delay = 0;
                    update_completion.begin();
                    return Source.REMOVE;
                });
            });
            location_bar.hexpand = true;
            location_bar.add_named(path, "entry");
            var crumbs_scroll = new Gtk.ScrolledWindow();
            crumbs_scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.NEVER);
            crumbs_scroll.set_child(breadcrumbs);
            location_bar.add_named(crumbs_scroll, "breadcrumbs");
            location_bar.visible_child_name = "breadcrumbs";
            toolbar.append(location_bar);
            toolbar.append(button("document-edit-symbolic", "Edit Location", () => edit_location()));
            toolbar.append(button("view-refresh-symbolic", "Reload", () => navigate(location, false)));
            toolbar.append(button("system-search-symbolic", "Search", () => { searches.visible = !searches.visible;
                                                                              if (searches.visible)
                                                                                  search_entry.grab_focus();
                }));
            modes = new Gtk.DropDown.from_strings(chooser_mode ? new string[] {"Grid", "List"}
                                                                                             : new string[] {"Grid", "List", "Columns", "Gallery"});
            modes.tooltip_text = "View";
            modes.notify["selected"].connect(() => set_view(new string[] {"Grid", "List", "Columns", "Gallery"}
                [modes.selected]));
            toolbar.append(modes);
            toolbar.append(button("preferences-system-symbolic", "View Settings", () => show_view_settings()));
            append(toolbar);
            location_error.button_label = "Retry";
            location_error.button_clicked.connect(() => navigate(directory.location, false));
            append(location_error);
            if(!metadata.available)
            {
                var banner = new Adw.Banner("Favorites, tags, and preferences are unavailable: " + metadata.storage_error);
                banner.revealed = true;
                banner.button_label = "Recover Metadata";
                banner.button_clicked.connect(() => recover_metadata.begin(banner));
                append(banner);
            }
            searches = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            search_entry.hexpand = true;
            searches.visible = false;
            searches.margin_start = 8;
            searches.margin_end = 8;
            searches.margin_bottom = 6;
            searches.append(search_entry);
            recursive_button = new Gtk.ToggleButton.with_label("Include Subfolders");
            recursive_button.toggled.connect(() => { recursive = recursive_button.active;
                                                     run_search();
                });
            searches.append(recursive_button);
            searches.append(button("globe-symbolic", "Search Home", () => {
                search_query.text = search_entry.text;
                var query = search_query;
                navigate(File.new_for_path(Environment.get_home_dir()));
                search_query = query;
                search_entry.text = query.text;
                searches.visible = true;
                recursive_button.active = true;
                run_search();
            }));
            searches.append(button("network-workgroup-symbolic", "Search Everywhere (Home and mounted locations)", () => {
                search_query.text = search_entry.text;
                var query = search_query;
                navigate(File.new_for_path(Environment.get_home_dir()));
                search_query = query;
                search_entry.text = query.text;
                searches.visible = true;
                everywhere = true;
                recursive_button.active = true;
                run_search();
            }));
            searches.append(button("view-filter-symbolic", "Search Filters", () => {
                search_query.text = search_entry.text;
                var dialog = new SearchFilters(search_query);
                dialog.applied.connect((query) => { search_query = query;
                                                    run_search();
                    });
                dialog.present(this);
            }));
            append(searches);
            search_entry.search_changed.connect(run_search);
            var body = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            sidebar_pane = body;
            body.vexpand = true;
            body.position = 180;
            body.shrink_start_child = true;
            var side_scroll = new Gtk.ScrolledWindow();
            side_scroll.set_child(sidebar);
            sidebar.selection_mode = Gtk.SelectionMode.NONE;
            sidebar.add_css_class("navigation-sidebar");
            body.start_child = side_scroll;
            sidebar.row_activated.connect((row) => { if (row.get_index() < places.entries.size)
                                                         open_place.begin(places.entries[row.get_index()]);
                });
            var side_menu = new Gtk.GestureClick();
            side_menu.button = 3;
            side_menu.pressed.connect((n, x, y) => { var row = sidebar.get_row_at_y((int)y);
                                                     if(row != null && row.get_index() < places.entries.size)
                                                         place_menu(places.entries[row.get_index()], x, y);
                });
            sidebar.add_controller(side_menu);
            places.changed.connect(rebuild_sidebar);
            rebuild_sidebar();
            var content = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            content.start_child = views;
            if(!chooser_mode)
                add_drop(views, () => location);
            content.end_child = preview;
            content.resize_start_child = true;
            content.shrink_start_child = false;
            preview.visible = false;
            body.end_child = content;
            append(body);
            var grid = new Gtk.GridView(selection, factory(true));
            grid.min_columns = 1;
            grid.max_columns = 16;
            grid.enable_rubberband = true;
            grid.activate.connect(activate_position);
            views.add_named(scrolled(grid), "Grid");
            var list = new Gtk.ColumnView(selection);
            list.show_column_separators = true;
            list.enable_rubberband = true;
            var name_column = new Gtk.ColumnViewColumn("Name", factory(false));
            name_column.expand = true;
            name_column.resizable = true;
            list.append_column(name_column);
            details = list;
            detail_columns["Name"] = name_column;
            name_column.notify["fixed-width"].connect(save_display);
            foreach(var title in column_titles)
            {
                if(title == "Name")
                    continue;
                string column_title = title;
                var column = new Gtk.ColumnViewColumn(title, text_factory((item) => column_text(item, column_title)));
                column.resizable = true;
                column.visible = title == "Size" || title == "Type" || title == "Modified";
                list.append_column(column);
                detail_columns[title] = column;
                column.notify["fixed-width"].connect(save_display);
            }
            list.activate.connect(activate_position);
            views.add_named(scrolled(list), "List");
            views.add_named(scrolled(columns), "Columns");
            var gallery = new Gtk.Box(Gtk.Orientation.VERTICAL, 8);
            gallery_preview.vexpand = true;
            gallery.append(gallery_preview);
            var strip = new Gtk.ListView(selection, factory(false));
            strip.activate.connect(activate_position);
            var strip_scroll = scrolled(strip);
            strip_scroll.height_request = 160;
            gallery.append(strip_scroll);
            views.add_named(gallery, "Gallery");
            foreach(var view in new string[] {"Grid", "List", "Columns"})
            {
                var scroll = (Gtk.ScrolledWindow)views.get_child_by_name(view);
                scroll.vadjustment.value_changed.connect(() => session_changed());
                scroll.hadjustment.value_changed.connect(() => session_changed());
            }
            strip_scroll.vadjustment.value_changed.connect(() => session_changed());
            status.halign = Gtk.Align.START;
            status.margin_start = 12;
            append(status);
            selection.selection_changed.connect(() => { selection_changed();
                                                        session_changed();
                                                        update_status();
                                                        var chosen = selected();
                                                        if (chosen.size > 0)
                                                        {
                                                            if (preview.visible)
                                                                preview.show_item.begin(chosen[0]);
                                                            if (view_mode == "Gallery")
                                                                gallery_preview.show_item.begin(chosen[0]);
                                                        }
                });
            directory.resetting.connect((target) => { location_error.revealed = false;
                                                      remembered_selection.clear();
                                                      if(target.equal(location))
                                                          foreach(var item in selected())
                                                              remembered_selection.add(item.file);
                });
            directory.failed.connect((message) => {
                location_error.title = "Cannot load " + directory.location.get_parse_name() + ": " + message;
                location_error.revealed = true;
            });
            directory.loaded.connect(() => { update_status();
                                             restore_selection();
                                             if (view_mode == "Columns")
                                                 build_columns();
                });
            search.found.connect((item) => directory.items.append(item));
            search.progress.connect((folders, skipped) => {
                if(search_results)
                    status.label = "%u results · %u folders scanned · %u unavailable".printf(sorted.get_n_items(), folders, skipped);
            });
            var keys = new Gtk.EventControllerKey();
            keys.key_pressed.connect((key, code, mods) => {
                if(key == Gdk.Key.Escape && location_bar.visible_child_name == "entry")
                {
                    location_bar.visible_child_name = "breadcrumbs";
                    return true;
                }
                if ((mods & Gdk.ModifierType.CONTROL_MASK) != 0)
                {
                    if (key == Gdk.Key.l)
                    {
                        edit_location();
                        return true;
                    }
                    if (key == Gdk.Key.f)
                    {
                        searches.visible = true;
                        search_entry.grab_focus();
                        return true;
                    }
                    if (key == Gdk.Key.h)
                    {
                        show_hidden = !show_hidden;
                        refilter();
                        return true;
                    }
                    if (key == Gdk.Key.a && !path.has_focus && !search_entry.has_focus)
                    {
                        active_selection.select_all();
                        return true;
                    }
                }
                if ((mods & Gdk.ModifierType.ALT_MASK) != 0)
                {
                    if (key == Gdk.Key.Left)
                    {
                        var file = history.back();
                        if (file != null)
                            navigate(file, false);
                        return true;
                    }
                    if (key == Gdk.Key.Right)
                    {
                        var file = history.forward();
                        if (file != null)
                            navigate(file, false);
                        return true;
                    }
                    if (key == Gdk.Key.Up)
                    {
                        var parent = location.get_parent();
                        if (parent != null)
                            navigate(parent);
                        return true;
                    }
                }
                return false;
            });
            add_controller(keys);
        }
        public static Gtk.Button button(string icon, string tooltip, owned Callback callback)
        {
            var b = new Gtk.Button.from_icon_name(icon);
            b.tooltip_text = tooltip;
            b.clicked.connect(() => callback());
            return b;
        }
        public static Gtk.ScrolledWindow scrolled(Gtk.Widget widget)
        {
            var scroll = new Gtk.ScrolledWindow();
            scroll.set_child(widget);
            scroll.hexpand = true;
            scroll.vexpand = true;
            return scroll;
        }
        async void open_place(Place place)
        {
            if(place.volume != null)
            {
                try {
                    yield place.volume.mount(MountMountFlags.NONE, new Gtk.MountOperation(get_root() as Gtk.Window), null);
                    var mount = place.volume.get_mount();
                    if(mount != null)
                        navigate(mount.get_root());
                }
                catch(Error e) {
                    error(e.message);
                }
            }
            else navigate(place.file);
        }
        void place_menu(Place place, double x, double y)
        {
            var menu = new Gtk.Popover();
            menu.set_parent(sidebar);
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 4);
            menu.child = box;
            Gdk.Rectangle rect = {
                (int)x, (int)y, 1, 1
            };
            menu.pointing_to = rect;
            menu.closed.connect(() => menu.unparent());
            var tab = new Gtk.Button.with_label("Open in New Tab");
            tab.clicked.connect(() => { open_in_tab(place.file);
                                        menu.popdown();
                });
            box.append(tab);
            if(place.bookmark)
            {
                var rename = new Gtk.Button.with_label("Rename Bookmark");
                rename.clicked.connect(() => { menu.popdown();
                                               rename_bookmark.begin(place);
                    });
                box.append(rename);
                var remove = new Gtk.Button.with_label("Remove Bookmark");
                remove.clicked.connect(() => { menu.popdown();
                                               places.edit_bookmark.begin(place.file, null, true, 0, (obj, res) => { try { places.edit_bookmark.end(res);
                                                                                                                     }
                                                                                                                     catch(Error e) { error(e.message);
                                                                                                                     }
                                                   });
                    });
                box.append(remove);
                foreach(int direction in new int[] {-1, 1})
                {
                    var move = new Gtk.Button.with_label(direction < 0 ? "Move Bookmark Up" : "Move Bookmark Down");
                    move.clicked.connect(() => { menu.popdown();
                                                 places.edit_bookmark.begin(place.file, null, false, direction, (obj, res) => { try { places.edit_bookmark.end(res);
                                                                                                                                }
                                                                                                                                catch(Error e) { error(e.message);
                                                                                                                                }
                                                     });
                        });
                    box.append(move);
                }
            }
            if(place.mount != null)
            {
                var eject = new Gtk.Button.with_label(place.mount.can_eject() ? "Eject" : "Unmount");
                eject.clicked.connect(() => { menu.popdown();
                                              unmount_place.begin(place);
                    });
                box.append(eject);
            }
            if(place.volume != null)
            {
                var mount = new Gtk.Button.with_label("Mount");
                mount.clicked.connect(() => { menu.popdown();
                                              open_place.begin(place);
                    });
                box.append(mount);
            }
            menu.popup();
        }
        async void rename_bookmark(Place place)
        {
            var name = yield Dialogs.prompt(this, "Rename Bookmark", place.label);
            if(name == null)
                return;
            try {
                yield places.edit_bookmark(place.file, name);
            }
            catch(Error e) {
                error(e.message);
            }
        }
        async void unmount_place(Place place)
        {
            try {
                var operation = new Gtk.MountOperation(get_root() as Gtk.Window);
                if(place.mount.can_eject())
                    yield place.mount.eject_with_operation(MountUnmountFlags.NONE, operation, null);
                else yield place.mount.unmount_with_operation(MountUnmountFlags.NONE, operation, null);
            }
            catch(Error e) {
                error(e.message);
            }
        }
        public void refilter()
        {
            filter.changed(Gtk.FilterChange.DIFFERENT);
        }
        public void edit_location()
        {
            location_bar.visible_child_name = "entry";
            path.grab_focus();
            path.select_region(0, -1);
            update_completion.begin();
        }
        async void update_completion()
        {
            completion_token.cancel();
            completion_token = new Cancellable();
            var token = completion_token;
            try {
                var suggestions = yield location_suggestions.suggest(path.text, location, token);
                if(token.is_cancelled() || location_bar.visible_child_name != "entry" || !get_mapped())
                    return;
                while(completion_list.get_first_child() != null)
                    completion_list.remove(completion_list.get_first_child());
                foreach(var file in suggestions)
                {
                    var row = new Gtk.Button.with_label(file.get_parse_name());
                    row.add_css_class("flat");
                    row.clicked.connect(() => { completion_popup.popdown();
                                                navigate(file);
                        });
                    completion_list.append(row);
                }
                if(suggestions.size > 0)
                    completion_popup.popup();
                else completion_popup.popdown();
            }
            catch(Error ignored) {}
        }
        void build_breadcrumbs(File file)
        {
            while(breadcrumbs.get_first_child() != null)
                breadcrumbs.remove(breadcrumbs.get_first_child());
            if(file.get_uri() == "majoris:///home")
            {
                var label = new Gtk.Label("Home");
                label.add_css_class("heading");
                breadcrumbs.append(label);
                location_bar.visible_child_name = "breadcrumbs";
                return;
            }
            var parents = new Gee.ArrayList<File>();
            File? part = file;
            while(part != null && parents.size < 64)
            {
                parents.insert(0, part);
                part = part.get_parent();
            }
            foreach(var parent in parents)
            {
                var crumb = new Gtk.Button.with_label(parent.equal(File.new_for_path(Environment.get_home_dir())) ? "Home" : parent.get_basename() ?? parent.get_parse_name());
                crumb.add_css_class("flat");
                crumb.tooltip_text = parent.get_parse_name();
                crumb.clicked.connect(() => navigate(parent));
                var middle = new Gtk.GestureClick();
                middle.button = 2;
                middle.pressed.connect(() => open_in_tab(parent));
                crumb.add_controller(middle);
                breadcrumbs.append(crumb);
            }
            location_bar.visible_child_name = "breadcrumbs";
        }
        Gtk.ScrolledWindow? current_scroll()
        {
            var child = views.get_child_by_name(view_mode);
            if(child is Gtk.ScrolledWindow)
                return (Gtk.ScrolledWindow)child;
            if(view_mode == "Gallery" && child != null)
                return child.get_last_child() as Gtk.ScrolledWindow;
            return null;
        }
        public string session_state()
        {
            var chosen = new VariantBuilder(new VariantType("as"));
            foreach(var item in selected())
                chosen.add("s", item.file.get_uri());
            var scroll = current_scroll();
            return new Variant("(sbb@asdd)", saved_query(), recursive, everywhere, chosen.end(), scroll == null ? 0.0 : scroll.hadjustment.value, scroll == null ? 0.0 : scroll.vadjustment.value).print(true);
        }
        public void restore_session_state(string saved) throws Error
        {
            var value = Variant.parse(new VariantType("(sbbasdd)"), saved);
            var query = SearchQuery.deserialize(value.get_child_value(0).get_string());
            var chosen = value.get_child_value(3);
            double horizontal = value.get_child_value(4).get_double(), vertical = value.get_child_value(5).get_double();
            if(chosen.n_children() > 10000 || !horizontal.is_finite() || !vertical.is_finite() || horizontal < 0 || vertical < 0)
                throw new FileError.INVALID("Invalid browsing state");
            remembered_selection.clear();
            for(size_t i = 0; i < chosen.n_children(); i++)
            {
                string uri = chosen.get_child_value(i).get_string();
                if(Uri.parse_scheme(uri) != null)
                    remembered_selection.add(File.new_for_uri(uri));
            }
            search_query = query;
            recursive = value.get_child_value(1).get_boolean();
            everywhere = value.get_child_value(2).get_boolean();
            search_entry.text = query.text;
            searches.visible = query.active;
            recursive_button.active = recursive;
            if(query.active)
                run_search();
            else refilter();
            restore_selection();
            if(scroll_restore != 0)
                remove_tick_callback(scroll_restore);
            uint frames = 0;
            scroll_restore = add_tick_callback(() => {
                if(directory.loading)
                    return Source.CONTINUE;
                var scroll = current_scroll();
                if(scroll != null)
                {
                    scroll.hadjustment.value = horizontal;
                    scroll.vadjustment.value = vertical;
                }
                if(++frames < 8)
                    return Source.CONTINUE;
                scroll_restore = 0;
                session_changed();
                return Source.REMOVE;
            });
        }
        string column_text(FileItem item, string key)
        {
            if(column_providers.has_key(key))
                return column_providers[key].text(item, metadata);
            if(key == "Name")
                return item.name;
            if(key == "Size")
                return item.directory ? "—" : Paths.size(item.bytes);
            if(key == "Type")
                return ContentType.get_description(item.mime);
            if(key == "MIME Type")
                return item.mime;
            if(key == "Location")
                return item.file.get_parent() == null ? item.file.get_parse_name() : item.file.get_parent().get_parse_name();
            if(key == "Tags")
                return metadata.tags(item.file);
            if(key == "Favorite")
                return metadata.favorite(item.file) ? "★" : "";
            if(key == "Owner" || key == "Group")
                return item.info.get_attribute_string(key == "Owner" ? "owner::user" : "owner::group") ?? "—";
            if(key == "Permissions")
                return item.info.has_attribute("unix::mode") ? "%04o".printf(item.info.get_attribute_uint32("unix::mode") & 07777) : "—";
            if(key == "Trash Date")
                return item.info.get_attribute_string("trash::deletion-date") ?? "—";
            var attribute = key == "Created" ? "time::created" : key == "Accessed" ? "time::access" : "time::modified";
            if(!item.info.has_attribute(attribute))
                return "—";
            return new DateTime.from_unix_local((int64)item.info.get_attribute_uint64(attribute)).format("%x %X");
        }
        int compare_items(FileItem x, FileItem y)
        {
            if(folders_first && x.directory != y.directory)
                return x.directory ? -1 : 1;
            int result;
            if(column_providers.has_key(sort_key))
                result = column_providers[sort_key].compare(x, y, metadata);
            else if(sort_key == "Size")
                result = x.bytes < y.bytes ? -1 : x.bytes == y.bytes ? 0 : 1;
            else if(sort_key == "Modified" || sort_key == "Created" || sort_key == "Accessed")
            {
                var attribute = sort_key == "Created" ? "time::created" : sort_key == "Accessed" ? "time::access" : "time::modified";
                uint64 first = x.info.get_attribute_uint64(attribute), second = y.info.get_attribute_uint64(attribute);
                result = first < second ? -1 : first == second ? 0 : 1;
            }
            else result = Paths.natural_compare(column_text(x, sort_key), column_text(y, sort_key));
            if(result == 0)
                result = Paths.natural_compare(x.name, y.name);
            return ascending ? result : -result;
        }
        void save_display()
        {
            if(details == null || loading_display)
                return;
            var columns_state = new VariantBuilder(new VariantType("a(sbi)"));
            for(uint i = 0; i < details.columns.get_n_items(); i++)
            {
                var column = (Gtk.ColumnViewColumn)details.columns.get_item(i);
                columns_state.add("(sbi)", column.title, column.visible, column.fixed_width);
            }
            metadata.set_state("display:" + directory.location.get_uri(), new Variant("(sbbib@a(sbi))", sort_key, ascending, folders_first, icon_size, selection_checkboxes, columns_state.end()).print(true));
            metadata.set_state("caption:" + directory.location.get_uri(), caption_key);
        }
        void load_display(File location)
        {
            loading_display = true;
            sort_key = "Name";
            ascending = true;
            folders_first = true;
            icon_size = 64;
            selection_checkboxes = false;
            caption_key = metadata.state("caption:" + location.get_uri(), "None");
            if(caption_key != "None" && !(caption_key in column_titles))
                caption_key = "None";
            foreach(var title in column_titles)
            {
                var column = detail_columns[title];
                if(column == null)
                    continue;
                column.visible = title == "Name" || title == "Size" || title == "Type" || title == "Modified";
                column.fixed_width = -1;
            }
            var saved = metadata.state("display:" + location.get_uri());
            if(saved != "")
            {
                try {
                    var value = Variant.parse(new VariantType("(sbbiba(sbi))"), saved);
                    var key = value.get_child_value(0).get_string();
                    if(key in column_titles)
                        sort_key = key;
                    ascending = value.get_child_value(1).get_boolean();
                    folders_first = value.get_child_value(2).get_boolean();
                    icon_size = value.get_child_value(3).get_int32().clamp(32, 128);
                    selection_checkboxes = value.get_child_value(4).get_boolean();
                    var columns_state = value.get_child_value(5);
                    var seen = new Gee.HashSet<string>();
                    for(size_t i = 0; i < columns_state.n_children(); i++)
                    {
                        var entry = columns_state.get_child_value(i);
                        var title = entry.get_child_value(0).get_string();
                        if(!detail_columns.has_key(title) || !seen.add(title))
                            continue;
                        var column = detail_columns[title];
                        column.visible = title == "Name" || entry.get_child_value(1).get_boolean();
                        column.fixed_width = entry.get_child_value(2).get_int32().clamp(-1, 2000);
                        details.remove_column(column);
                        details.insert_column((uint)seen.size - 1, column);
                    }
                }
                catch(Error e) {   /* Invalid preferences fall back to the defaults. */
                }
            }
            sorter.changed(Gtk.SorterChange.DIFFERENT);
            display_changed();
            loading_display = false;
        }
        public void show_view_settings()
        {
            var dialog = new Adw.PreferencesDialog();
            dialog.title = "View Settings";
            var page = new Adw.PreferencesPage();
            dialog.add(page);
            var group = new Adw.PreferencesGroup();
            group.title = "This Folder";
            page.add(group);
            var size = new Adw.ComboRow();
            size.title = "Icon Density";
            size.model = new Gtk.StringList({"Compact", "Standard", "Large"});
            size.selected = icon_size < 64 ? 0 : icon_size > 64 ? 2 : 1;
            group.add(size);
            var caption = new Adw.ComboRow();
            caption.title = "Grid Metadata Caption";
            string[] captions = {
                "None"
            };
            foreach(var key in column_titles)
                if(key != "Name")
                    captions += key;
            caption.model = new Gtk.StringList(captions);
            for(uint i = 0; i < captions.length; i++)
                if(captions[i] == caption_key)
                    caption.selected = i;
            group.add(caption);
            caption.notify["selected"].connect(() => { caption_key = captions[caption.selected];
                                                       display_changed();
                                                       save_display();
                });
            size.notify["selected"].connect(() => { icon_size = size.selected == 0 ? 32 : size.selected == 1 ? 64 : 128;
                                                    display_changed();
                                                    save_display();
                });
            var checkboxes = new Adw.SwitchRow();
            checkboxes.title = "Selection Checkboxes";
            checkboxes.active = selection_checkboxes;
            group.add(checkboxes);
            checkboxes.notify["active"].connect(() => { selection_checkboxes = checkboxes.active;
                                                        display_changed();
                                                        save_display();
                });
            var folders = new Adw.SwitchRow();
            folders.title = "Folders First";
            folders.active = folders_first;
            group.add(folders);
            folders.notify["active"].connect(() => { folders_first = folders.active;
                                                     sorter.changed(Gtk.SorterChange.DIFFERENT);
                                                     save_display();
                });
            var sort = new Adw.ComboRow();
            sort.title = "Sort By";
            sort.model = new Gtk.StringList(column_titles);
            for(uint i = 0; i < column_titles.length; i++)
                if(column_titles[i] == sort_key)
                    sort.selected = i;
            group.add(sort);
            sort.notify["selected"].connect(() => set_sort(column_titles[sort.selected], ascending));
            var direction = new Adw.SwitchRow();
            direction.title = "Descending Order";
            direction.active = !ascending;
            group.add(direction);
            direction.notify["active"].connect(() => set_sort(sort_key, !direction.active));
            var columns_group = new Adw.PreferencesGroup();
            columns_group.title = "List Columns";
            page.add(columns_group);
            for(uint i = 0; i < details.columns.get_n_items(); i++)
            {
                var column = (Gtk.ColumnViewColumn)details.columns.get_item(i);
                var row = new Adw.ActionRow();
                row.title = column.title;
                var toggle = new Gtk.Switch();
                toggle.valign = Gtk.Align.CENTER;
                toggle.active = column.visible;
                toggle.sensitive = column.title != "Name";
                row.add_suffix(toggle);
                toggle.notify["active"].connect(() => { column.visible = toggle.active;
                                                        save_display();
                    });
                var width = new Gtk.SpinButton.with_range(40, 1200, 10);
                width.valign = Gtk.Align.CENTER;
                width.value = column.fixed_width > 0 ? column.fixed_width : 160;
                width.tooltip_text = "Column Width (pixels)";
                row.add_suffix(width);
                width.value_changed.connect(() => { column.fixed_width = width.get_value_as_int();
                                                    save_display();
                    });
                var up = new Gtk.Button.from_icon_name("go-up-symbolic");
                up.valign = Gtk.Align.CENTER;
                up.tooltip_text = "Move Column Left";
                row.add_suffix(up);
                up.clicked.connect(() => {
                    for(uint j = 1; j < details.columns.get_n_items(); j++)
                        if(details.columns.get_item(j) == column)
                        {
                            details.remove_column(column);
                            details.insert_column(j - 1, column);
                            save_display();
                            break;
                        }
                });
                columns_group.add(row);
            }
            dialog.present(this);
        }
        public void set_sort(string key, bool ascending)
        {
            sort_key = key;
            this.ascending = ascending;
            sorter.changed(Gtk.SorterChange.DIFFERENT);
            save_display();
            session_changed();
        }
        public void register_column(ColumnProvider provider) throws Error
        {
            string title = provider.title;
            if(title == "" || title == "None" || title != title.strip() || title.contains("\n") || title.contains("\r") || title.length > 80 || !title.validate() || detail_columns.has_key(title))
                throw new FileError.INVALID("Column titles must be non-empty, single-line and unique");
            column_providers[title] = provider;
            column_titles += title;
            var column = new Gtk.ColumnViewColumn(title, text_factory((item) => provider.text(item, metadata)));
            column.resizable = true;
            column.visible = false;
            details.append_column(column);
            detail_columns[title] = column;
            column.notify["fixed-width"].connect(save_display);
            load_display(directory.location);
        }
        public void set_view(string mode, bool remember = true)
        {
            if(chooser_mode && mode != "Grid" && mode != "List")
                mode = "Grid";
            if(view_mode == mode)
                return;
            view_mode = mode;
            views.visible_child_name = directory.location.get_uri() == "majoris:///home" ? "Home" : mode;
            if(remember)
                metadata.set_state("view:" + location.get_uri(), mode);
            modes.selected = mode == "Grid" ? 0 : mode == "List" ? 1 : mode == "Columns" ? 2 : 3;
            session_changed();
            if (mode == "Columns" && directory.location.get_uri() != "majoris:///home")
                build_columns();
        }
        void rebuild_sidebar()
        {
            sidebar_generation++;
            while (sidebar.get_first_child() != null)
                sidebar.remove(sidebar.get_first_child());
            foreach (var place in places.entries)
            {
                var label = new Gtk.Label(place.label);
                label.halign = Gtk.Align.START;
                label.margin_start = 10;
                label.margin_end = 10;
                label.margin_top = 8;
                label.margin_bottom = 8;
                sidebar.append(label);
                if(!chooser_mode)
                    add_drop(label, () => place.file);
            }
        }
        public void navigate(File file, bool record = true)
        {
            completion_token.cancel();
            completion_popup.popdown();
            if(completion_delay != 0)
            {
                Source.remove(completion_delay);
                completion_delay = 0;
            }
            location_suggestions.remember(file);
            if(scroll_restore != 0)
            {
                remove_tick_callback(scroll_restore);
                scroll_restore = 0;
            }
            column_folder = null;
            column_selection = null;
            navigation_generation++;
            search_results = false;
            everywhere = false;
            search.cancellable.cancel();
            search_query = new SearchQuery();
            search_entry.text = "";
            path.text = file.get_parse_name();
            load_display(file);
            if (record)
                history.visit(file);
            initial_selection = null;
            build_breadcrumbs(file);
            set_view(metadata.state("view:" + file.get_uri(), "Grid"), false);
            modes.sensitive = file.get_uri() != "majoris:///home";
            if(file.get_uri() != "majoris:///home")
                views.visible_child_name = view_mode;
            home.cancel();
            if(file.get_uri() == "majoris:///home")
            {
                directory.virtual_location(file);
                views.visible_child_name = "Home";
                home.reload.begin();
            }
            else if (file.get_uri() == "majoris:///favorites")
            {
                directory.virtual_location(file);
                load_virtual.begin(metadata.favorites(), navigation_generation);
            }
            else if(file.get_uri().has_prefix("majoris:///tag/"))
            {
                directory.virtual_location(file);
                load_virtual.begin(metadata.tagged(Uri.unescape_string(file.get_uri().substring(15))), navigation_generation);
            }
            else if(file.get_uri().has_prefix("majoris:///search/"))
            {
                string name = Uri.unescape_string(file.get_uri().substring(18));
                foreach(var saved in metadata.saved_searches())
                    if(saved.name == name)
                    {
                        navigate(saved.location);
                        searches.visible = true;
                        try {
                            search_query = SearchQuery.deserialize(saved.query);
                        }
                        catch(Error e) {
                            error(e.message);
                            return;
                        }
                        search_entry.text = search_query.text;
                        everywhere = search_query.scope == "everywhere";
                        recursive = search_query.scope != "folder";
                        recursive_button.active = recursive;
                        run_search();
                        return;
                    }
            }
            else if (file.get_uri() == "recent:///")
            {
                directory.virtual_location(file);
                var files = new Gee.ArrayList<File>();
                foreach (var recent in Gtk.RecentManager.get_default().get_items())
                    files.add(File.new_for_uri(recent.get_uri()));
                load_virtual.begin(files, navigation_generation);
            }
            else directory.open.begin(file, get_root() as Gtk.Window);
            update_status();
            location_changed(file);
            session_changed();
        }
        async void load_virtual(Gee.List<File> files, uint epoch)
        {
            foreach (var file in files)
            {
                try {
                    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, null);
                    if (epoch != navigation_generation)
                        return;
                    directory.items.append(new FileItem(file, info));
                }
                catch (Error e) {}
            }
            update_status();
        }
        public void select_file(File file)
        {
            initial_selection = file;
            refilter();
            restore_selection();
        }
        void restore_selection()
        {
            for (uint i = 0; i < sorted.get_n_items(); i++)
            {
                var file = ((FileItem)sorted.get_item(i)).file;
                if(initial_selection != null && file.equal(initial_selection))
                {
                    selection.select_item(i, true);
                    return;
                }
                if(initial_selection == null)
                    foreach(var remembered in remembered_selection)
                        if(file.equal(remembered))
                        {
                            selection.select_item(i, false);
                            break;
                        }
            }
        }
        public Gee.ArrayList<FileItem> selected()
        {
            var result = new Gee.ArrayList<FileItem>();
            var active = active_selection;
            var bits = active.get_selection();
            var iterator = Gtk.BitsetIter();
            uint position;
            if (iterator.init_first(bits, out position))
                do {
                    result.add((FileItem)active.get_item(position));
                } while (iterator.next(out position));
            return result;
        }
        void activate_position(uint position)
        {
            var item = (FileItem)selection.get_item(position);
            activate_item.begin(item);
        }
        async void activate_item(FileItem item)
        {
            if(item.directory)
            {
                navigate(item.file);
                return;
            }
            try {
                if(item.info.get_file_type() == FileType.MOUNTABLE)
                {
                    var target = yield item.file.mount_mountable(MountMountFlags.NONE, new Gtk.MountOperation(get_root() as Gtk.Window), null);
                    navigate(target);
                    return;
                }
                if(item.info.get_file_type() == FileType.SHORTCUT)
                {
                    var target = item.info.get_attribute_string("standard::target-uri");
                    if(target != null)
                    {
                        navigate(File.new_for_uri(target));
                        return;
                    }
                }
                if(item.info.get_is_symlink())
                {
                    var info = yield item.file.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
                    if(info.get_file_type() == FileType.DIRECTORY)
                    {
                        navigate(item.file);
                        return;
                    }
                }
                activated(item);
            }
            catch(Error e) {
                error(e.message);
            }
        }
        void update_status()
        {
            if(directory.location.get_uri() == "majoris:///home")
            {
                status.label = "Local activity · nothing is uploaded";
                return;
            }
            var chosen = selected();
            uint64 bytes = 0;
            foreach(var item in chosen)
                if(!item.directory)
                    bytes += item.bytes;
            status.label = "%u items · %d selected".printf(sorted.get_n_items(), chosen.size) + (chosen.size > 0 ? " · " + Paths.size(bytes) : "") + (search_results ? " · %u folders scanned · %u unavailable".printf(search.scanned, search.unreadable) : "");
        }
        void run_search()
        {
            search.cancellable.cancel();
            search_query.text = search_entry.text;
            search_query.scope = everywhere ? "everywhere" : recursive ? "recursive" : "folder";
            if ((recursive || everywhere || search_query.content != "") && search_query.active)
            {
                search_results = true;
                directory.cancel();
                directory.items.remove_all();
                var roots = everywhere ? places.search_roots() : new Gee.ArrayList<File>();
                if(!everywhere)
                    roots.add(location);
                search.search_roots.begin(roots, search_query, metadata, recursive || everywhere, (obj, res) => { try { search.search_roots.end(res);
                                                                                                                        restore_selection();
                                                                                                                  }
                                                                                                                  catch (Error e) { if (!(e is IOError.CANCELLED))
                                                                                                                                        error(e.message);
                                                                                                                  }
                    });
            }
            else if (search_results)
            {
                search_results = false;
                directory.open.begin(location, get_root() as Gtk.Window);
            }
            refilter();
            session_changed();
        }
        void build_columns()
        {
            foreach(var model in column_models)
                model.cancel();
            column_models.clear();
            column_folder = null;
            column_selection = null;
            while (columns.get_first_child() != null)
                remove_column(columns.get_first_child());
            append_column(directory.location, sorted);
        }
        void remove_column(Gtk.Widget widget)
        {
            if(column_handlers.has_key(widget))
                column_selections[widget].disconnect(column_handlers[widget]);
            column_handlers.unset(widget);
            column_selections.unset(widget);
            column_generations.unset(widget);
            if(pending_columns.has_key(widget))
            {
                pending_columns[widget].cancel();
                column_models.remove(pending_columns[widget]);
                pending_columns.unset(widget);
            }
            if(loaded_columns.has_key(widget))
            {
                loaded_columns[widget].cancel();
                column_models.remove(loaded_columns[widget]);
                loaded_columns.unset(widget);
            }
            columns.remove(widget);
        }
        Gtk.Widget append_column(File folder, ListModel items)
        {
            var selected = items == sorted ? selection : new Gtk.MultiSelection(items);
            var list = new Gtk.ListView(selected, factory(false, selected));
            list.enable_rubberband = true;
            list.width_request = 220;
            var scroll = scrolled(list);
            scroll.hexpand = false;
            columns.append(scroll);
            column_selections[scroll] = selected;
            column_generations[scroll] = 0;
            column_handlers[scroll] = selected.selection_changed.connect(() => {
                if(view_mode != "Columns" || scroll.get_parent() != columns)
                    return;
                column_generations[scroll] = column_generations[scroll] + 1;
                if(pending_columns.has_key(scroll))
                {
                    pending_columns[scroll].cancel();
                    column_models.remove(pending_columns[scroll]);
                    pending_columns.unset(scroll);
                }
                column_selection = selected;
                column_folder = folder;
                selection_changed();
                session_changed();
                update_status();
                var chosen = this.selected();
                while (scroll.get_next_sibling() != null)
                    remove_column(scroll.get_next_sibling());
                if(chosen.size != 1)
                    return;
                var item = chosen[0];
                if (item.directory)
                    load_column.begin(item.file, scroll);
                else { preview.visible = true;
                       preview.show_item.begin(item);
                }
            });
            list.activate.connect((position) => { var item = items.get_item(position) as FileItem;
                                                  if (item != null)
                                                      activate_item.begin(item);
                });
            return scroll;
        }
        async void load_column(File folder, Gtk.Widget anchor)
        {
            var model = new DirectoryModel();
            uint generation = column_generations[anchor];
            pending_columns[anchor] = model;
            column_models.add(model);
            yield model.open(folder, get_root() as Gtk.Window);
            if (anchor.get_parent() != columns || !column_generations.has_key(anchor) || generation != column_generations[anchor] || !pending_columns.has_key(anchor) || pending_columns[anchor] != model)
            {
                model.cancel();
                column_models.remove(model);
                return;
            }
            pending_columns.unset(anchor);
            var child = append_column(folder, model.items);
            loaded_columns[child] = model;
        }
        delegate string ItemText(FileItem item);
        Gtk.SignalListItemFactory text_factory(owned ItemText text)
        {
            var factory = new Gtk.SignalListItemFactory();
            var handlers = new Gee.HashMap<Gtk.ListItem, ulong?>();
            factory.setup.connect((obj) => {
                var li = (Gtk.ListItem)obj;
                li.child = new Gtk.Label("");
                handlers[li] = metadata.changed.connect(() => {
                    if(li.item != null)
                        ((Gtk.Label)li.child).label = text((FileItem)li.item);
                });
            });
            factory.bind.connect((obj) => { var li = (Gtk.ListItem)obj;
                                            ((Gtk.Label)li.child).label = text((FileItem)li.item);
                });
            factory.teardown.connect((obj) => {
                var li = (Gtk.ListItem)obj;
                if(handlers.has_key(li))
                {
                    metadata.disconnect(handlers[li]);
                    handlers.unset(li);
                }
            });
            return factory;
        }
        Gtk.SignalListItemFactory factory(bool grid, Gtk.MultiSelection? row_selection = null)
        {
            var f = new Gtk.SignalListItemFactory();
            var display_handlers = new Gee.HashMap<Gtk.ListItem, ulong?>();
            f.setup.connect((obj) => { var li = (Gtk.ListItem)obj;
                                       var box = new Gtk.Box(grid ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL, 8);
                                       box.margin_start = 8;
                                       box.margin_end = 8;
                                       box.margin_top = 8;
                                       box.margin_bottom = 8;
                                       var icon = new Gtk.Image();
                                       icon.pixel_size = grid ? 64 : 24;
                                       box.append(icon);
                                       var label = new Gtk.Label("");
                                       label.ellipsize = Pango.EllipsizeMode.END;
                                       label.max_width_chars = grid ? 18 : 50;
                                       if (grid)
                                       {
                                           label.wrap = true;
                                           label.lines = 2;
                                       }
                                       else label.halign = Gtk.Align.START;
                                       box.append(label);
                                       var caption = new Gtk.Label("");
                                       caption.add_css_class("dim-label");
                                       caption.ellipsize = Pango.EllipsizeMode.END;
                                       caption.max_width_chars = 18;
                                       caption.visible = grid && caption_key != "None";
                                       if(grid)
                                           box.append(caption);
                                       var checkbox = new Gtk.CheckButton();
                                       checkbox.tooltip_text = "Select Item";
                                       box.append(checkbox);
                                       checkbox.toggled.connect(() => {
                    if(li.item == null || checkbox.active == li.selected)
                        return;
                    var model = row_selection ?? selection;
                    if(checkbox.active)
                        model.select_item(li.position, false);
                    else model.unselect_item(li.position);
                });
                                       li.notify["selected"].connect(() => checkbox.active = li.selected);
                                       display_handlers[li] = display_changed.connect(() => {
                    icon.pixel_size = grid ? icon_size : (icon_size > 64 ? 32 : 24);
                    int spacing = icon_size < 64 ? 4 : 8;
                    box.margin_top = spacing;
                    box.margin_bottom = spacing;
                    checkbox.visible = selection_checkboxes;
                    caption.visible = grid && caption_key != "None";
                    if(grid && li.item != null)
                        caption.label = column_text((FileItem)li.item, caption_key);
                });
                                       icon.pixel_size = grid ? icon_size : (icon_size > 64 ? 32 : 24);
                                       checkbox.visible = selection_checkboxes;
                                       li.child = box;
                                       var middle = new Gtk.GestureClick();
                                       middle.button = 2;
                                       middle.pressed.connect(() => { var item = li.item as FileItem;
                                                                      if(item != null && item.directory)
                                                                          open_in_tab(item.file);
                                           });
                                       box.add_controller(middle);
                                       var right = new Gtk.GestureClick();
                                       right.button = 3;
                                       right.pressed.connect(() => { if(li.item != null && !active_selection.is_selected(li.position))
                                                                         active_selection.select_item(li.position, true);
                                           });
                                       box.add_controller(right);
                                       if(!chooser_mode)
                                       {
                                           var drag = new Gtk.DragSource();
                                           drag.actions = Gdk.DragAction.COPY | Gdk.DragAction.MOVE;
                                           drag.prepare.connect(() => {
                        var item = li.item as FileItem;
                        if(item == null)
                            return null;
                        if(!active_selection.is_selected(li.position))
                            active_selection.select_item(li.position, true);
                        var files = new Gee.ArrayList<File>();
                        foreach(var chosen in selected())
                            files.add(chosen.file);
                        return FileClipboard.provider(files);
                    });
                                           box.add_controller(drag);
                                           add_drop(box, () => { var item = li.item as FileItem;
                                                                 return item != null && item.directory ? item.file : null;
                                               });
                                       }
                });
            f.bind.connect((obj) => { var li = (Gtk.ListItem)obj;
                                      var item = (FileItem)li.item;
                                      var box = (Gtk.Box)li.child;
                                      var image = (Gtk.Image)box.get_first_child();
                                      image.set_from_gicon(item.info.get_icon());
                                      ((Gtk.Label)image.get_next_sibling()).label = item.name;
                                      if(grid)
                                          ((Gtk.Label)image.get_next_sibling().get_next_sibling()).label = caption_key == "None" ? "" : column_text(item, caption_key);
                                      ((Gtk.CheckButton)box.get_last_child()).active = li.selected;
                                      box.tooltip_text = item.file.get_parse_name();
                                      var token = new Cancellable();
                                      thumbnail_jobs[li] = token;
                                      thumbnails.texture.begin(item, token, (service, res) => { try { var texture = thumbnails.texture.end(res);
                                                                                                      if (!token.is_cancelled() && li.item == item && texture != null)
                                                                                                          image.set_from_paintable(texture);
                                                                                                }
                                                                                                catch (Error e) {}
                                          });
                });
            f.unbind.connect((obj) => { var li = (Gtk.ListItem)obj;
                                        var token = thumbnail_jobs[li];
                                        if (token != null)
                                            token.cancel();
                                        thumbnail_jobs.unset(li);
                });
            f.teardown.connect((obj) => {
                var li = (Gtk.ListItem)obj;
                if(display_handlers.has_key(li))
                {
                    disconnect(display_handlers[li]);
                    display_handlers.unset(li);
                }
            });
            return f;
        }
        public void cancel()
        {
            while(columns.get_first_child() != null)
                remove_column(columns.get_first_child());
            completion_token.cancel();
            completion_popup.popdown();
            if(completion_delay != 0)
            {
                Source.remove(completion_delay);
                completion_delay = 0;
            }
            if(scroll_restore != 0)
            {
                remove_tick_callback(scroll_restore);
                scroll_restore = 0;
            }
            navigation_generation++;
            foreach(var model in column_models)
                model.cancel();
            column_models.clear();
            foreach(var token in thumbnail_jobs.values)
                token.cancel();
            directory.cancel();
            search.cancellable.cancel();
            preview.cancel();
            home.cancel();
            gallery_preview.cancel();
        }
        protected override void dispose()
        {
            cancel();
            if(completion_popup.get_parent() != null)
                completion_popup.unparent();
            base.dispose();
        }
        delegate File? DropFolder();
        async void recover_metadata(Adw.Banner banner)
        {
            if(!(yield Dialogs.confirm(get_root() as Gtk.Window, "Recover Metadata?", "Preserve the existing database as a recovery copy and create a fresh database? Files and folders are unaffected.", "Recover")))
                return;
            try {
                var backup = metadata.recover();
                banner.revealed = false;
                Dialogs.error(get_root() as Gtk.Window, "A fresh metadata database is ready. The previous database is preserved at " + backup);
            }
            catch(Error e) {
                error(e.message);
            }
        }
        void add_drop(Gtk.Widget widget, owned DropFolder folder)
        {
            var drop = new Gtk.DropTarget(typeof(Gdk.FileList), Gdk.DragAction.COPY | Gdk.DragAction.MOVE);
            uint spring = 0;
            drop.enter.connect(() => {
                var target = folder();
                if(target == null || target.has_uri_scheme("majoris") || target.has_uri_scheme("recent"))
                    return (Gdk.DragAction)0;
                if(widget != views)
                    spring = Timeout.add(900, () => { spring = 0;
                                                      if(widget.get_mapped())
                                                          navigate(target);
                                                      return Source.REMOVE;
                        });
                return Gdk.DragAction.COPY;
            });
            drop.leave.connect(() => { if(spring != 0)
                                       {
                                           Source.remove(spring);
                                           spring = 0;
                                       }
                });
            drop.drop.connect((value) => {
                if(spring != 0)
                {
                    Source.remove(spring);
                    spring = 0;
                }
                var target = folder();
                if(target == null || target.has_uri_scheme("majoris") || target.has_uri_scheme("recent"))
                    return false;
                var list = (Gdk.FileList)value.get_boxed();
                if(list == null)
                    return false;
                var files = new Gee.ArrayList<File>();
                foreach(var file in list.get_files())
                {
                    if(file.equal(target) || target.has_prefix(file))
                        return false;
                    files.add(file);
                }
                var drag = drop.current_drop == null ? null : drop.current_drop.get_drag();
                bool move = drag != null && drag.get_selected_action() == Gdk.DragAction.MOVE;
                transfer_requested(files, target, move);
                return files.size > 0;
            });
            widget.add_controller(drop);
        }
    }
}
