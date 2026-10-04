namespace MajorisFiles {
    public class Browser : Gtk.Box {
        public DirectoryModel directory = new DirectoryModel();
        public History history = new History();
        public SearchController search = new SearchController();
        SearchQuery search_query = new SearchQuery();
        public string saved_query() { search_query.text = search_entry.text; return search_query.serialize(); }
        public Gtk.MultiSelection selection;
        public File location {
            get {
                return directory.location;
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
        public signal void error(string message);
        Gtk.CustomFilter filter;
        Gtk.CustomSorter sorter;
        Gtk.FilterListModel filtered;
        Gtk.SortListModel sorted;
        Gtk.Stack views = new Gtk.Stack();
        Gtk.ListBox sidebar = new Gtk.ListBox();
        Gtk.Label status = new Gtk.Label("");
        Gtk.Box columns = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 1);
        PreviewPane gallery_preview = new PreviewPane();
        Gtk.Stack location_bar = new Gtk.Stack();
        Gtk.Box breadcrumbs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Box searches;
        Gtk.Paned sidebar_pane;
        public int sidebar_width { get { return sidebar_pane.position; } set { sidebar_pane.position = value.clamp(120, 420); } }
        Gtk.DropDown modes;
        bool chooser_mode;
        public signal void open_in_tab(File file);
        bool recursive;
        bool search_results;
        Gtk.ToggleButton recursive_button;
        bool ascending = true;
        string sort_key = "Name";
        File? initial_selection;
        Gee.ArrayList<File> remembered_selection = new Gee.ArrayList<File>();
        uint navigation_generation;
        ThumbnailService thumbnails = new ThumbnailService();
        Gee.HashMap<Gtk.ListItem, Cancellable> thumbnail_jobs = new Gee.HashMap<Gtk.ListItem, Cancellable>();
        uint sidebar_generation;
        public Browser(MetadataStore metadata, Places places, bool chooser_mode = false)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            this.metadata = metadata;
            this.places = places;
            this.chooser_mode=chooser_mode;
            filter = new Gtk.CustomFilter((obj) => { var item = (FileItem)obj;
                                                     return (show_hidden || !item.info.get_is_hidden() || (initial_selection != null && initial_selection.equal(item.file))) && (!folders_only || item.navigable || item.info.get_is_symlink()) && (chooser_filter == null || chooser_filter.matches(item)) && (recursive || search_query.matches(item, metadata));
                });
            sorter = new Gtk.CustomSorter((a, b) => { var x = (FileItem)a;
                                                      var y = (FileItem)b;
                                                      if (x.directory != y.directory)
                                                          return x.directory ? -1 : 1;
                                                      int result;
                                                      if (sort_key == "Size")
                                                          result = x.bytes < y.bytes ? -1 : x.bytes == y.bytes ? 0 : 1;
                                                      else if (sort_key == "Modified")
                                                      {
                                                          uint64 ax = x.info.get_attribute_uint64("time::modified"), by = y.info.get_attribute_uint64("time::modified");
                                                          result = ax < by ? -1 : ax == by ? 0 : 1;
                                                      }
                                                      else if (sort_key == "Type")
                                                          result = strcmp(x.mime, y.mime);
                                                      else result = Paths.natural_compare(x.name, y.name);
                                                      return ascending ? result : -result;
                });
            filtered = new Gtk.FilterListModel(directory.items, filter);
            sorted = new Gtk.SortListModel(filtered, sorter);
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
            path.activate.connect(() => navigate(Paths.parse(path.text)));
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
            modes = new Gtk.DropDown.from_strings(chooser_mode ? new string[]{"Grid","List"} : new string[]{"Grid", "List", "Columns", "Gallery"});
            modes.tooltip_text = "View";
            modes.notify["selected"].connect(() => set_view(new string[] {"Grid", "List", "Columns", "Gallery"}
                [modes.selected]));
            toolbar.append(modes);
            append(toolbar);
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
            searches.append(button("view-filter-symbolic", "Search Filters", () => {
                search_query.text = search_entry.text;
                var dialog = new SearchFilters(search_query);
                dialog.applied.connect((query) => { search_query = query; run_search(); });
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
            list.append_column(new Gtk.ColumnViewColumn("Size", text_factory((item) => item.directory ? "—" : Paths.size(item.bytes))));
            list.append_column(new Gtk.ColumnViewColumn("Type", text_factory((item) => ContentType.get_description(item.mime))));
            list.append_column(new Gtk.ColumnViewColumn("Modified", text_factory((item) => { var date = item.info.get_modification_date_time();
                                                                                             return date == null ? "" : date.format("%x %X");
                })));
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
            status.halign = Gtk.Align.START;
            status.margin_start = 12;
            append(status);
            selection.selection_changed.connect(() => { selection_changed();
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
            directory.resetting.connect((target) => { remembered_selection.clear();
                                                      if(target.equal(location))
                                                          foreach(var item in selected())
                                                              remembered_selection.add(item.file);
                });
            directory.failed.connect((message) => error(message));
            directory.loaded.connect(() => { update_status();
                                             restore_selection();
                                             if (view_mode == "Columns")
                                                 build_columns();
                });
            search.found.connect((item) => directory.items.append(item));
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
                        selection.select_all();
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
        }
        void build_breadcrumbs(File file)
        {
            while(breadcrumbs.get_first_child() != null)
                breadcrumbs.remove(breadcrumbs.get_first_child());
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
        public void set_sort(string key, bool ascending)
        {
            sort_key = key;
            this.ascending = ascending;
            sorter.changed(Gtk.SorterChange.DIFFERENT);
        }
        public void set_view(string mode, bool remember = true)
        {
            if(chooser_mode && mode!="Grid" && mode!="List") mode="Grid";
            if(view_mode==mode) return;
            view_mode = mode;
            views.visible_child_name = mode;
            if(remember) metadata.set_state("view:"+location.get_uri(),mode);
            modes.selected=mode=="Grid" ? 0 : mode=="List" ? 1 : mode=="Columns" ? 2 : 3;
            if (mode == "Columns")
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
            }
        }
        public void navigate(File file, bool record = true)
        {
            navigation_generation++;
            search_results = false;
            search.cancellable.cancel();
            search_query = new SearchQuery();
            search_entry.text = "";
            path.text = file.get_parse_name();
            if (record)
                history.visit(file);
            initial_selection = null;
            build_breadcrumbs(file);
            set_view(metadata.state("view:"+file.get_uri(),"Grid"),false);
            if (file.get_uri() == "majoris:///favorites")
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
                        try { search_query = SearchQuery.deserialize(saved.query); }
                        catch(Error e) { error(e.message); return; }
                        search_entry.text = search_query.text;
                        recursive_button.active = true;
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
            location_changed(file);
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
                        if(file.equal(remembered)) {
                            selection.select_item(i, false);
                            break;
                        }
            }
        }
        public Gee.ArrayList<FileItem> selected()
        {
            var result = new Gee.ArrayList<FileItem>();
            var bits = selection.get_selection();
            var iterator = Gtk.BitsetIter();
            uint position;
            if (iterator.init_first(bits, out position))
                do {
                    result.add((FileItem)selection.get_item(position));
                } while (iterator.next(out position));
            return result;
        }
        void activate_position(uint position)
        {
            var item = (FileItem)selection.get_item(position);
            activate_item.begin(item);
        }
        async void activate_item(FileItem item) {
            if(item.directory) { navigate(item.file); return; }
            try {
                if(item.info.get_file_type()==FileType.MOUNTABLE) { var target=yield item.file.mount_mountable(MountMountFlags.NONE,new Gtk.MountOperation(get_root() as Gtk.Window),null); navigate(target); return; }
                if(item.info.get_file_type()==FileType.SHORTCUT) { var target=item.info.get_attribute_string("standard::target-uri"); if(target!=null) { navigate(File.new_for_uri(target)); return; } }
                if(item.info.get_is_symlink()) { var info=yield item.file.query_info_async("standard::type",FileQueryInfoFlags.NONE,Priority.DEFAULT,null); if(info.get_file_type()==FileType.DIRECTORY) { navigate(item.file); return; } }
                activated(item);
            } catch(Error e) { error(e.message); }
        }
        void update_status()
        {
            status.label = "%u items · %d selected".printf(sorted.get_n_items(), selected().size);
        }
        void run_search()
        {
            search.cancellable.cancel();
            search_query.text = search_entry.text;
            if (recursive && search_query.active)
            {
                search_results = true;
                directory.cancel();
                directory.items.remove_all();
                search.search.begin(location, search_query, metadata, (obj, res) => { try { search.search.end(res);
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
        }
        void build_columns()
        {
            while (columns.get_first_child() != null)
                columns.remove(columns.get_first_child());
            append_column(location, directory.items);
        }
        void append_column(File folder, GLib.ListStore items)
        {
            var selected = new Gtk.SingleSelection(items);
            var list = new Gtk.ListView(selected, factory(false));
            list.width_request = 220;
            var scroll = scrolled(list);
            scroll.hexpand = false;
            columns.append(scroll);
            selected.notify["selected-item"].connect(() => { var item = selected.selected_item as FileItem;
                                                             if (item == null)
                                                                 return;
                                                             while (scroll.get_next_sibling() != null)
                                                                 columns.remove(scroll.get_next_sibling());
                                                             if (item.directory)
                                                                 load_column.begin(item.file, scroll);
                                                             else { preview.visible = true;
                                                                    preview.show_item.begin(item);
                                                             }
                });
            list.activate.connect((position) => { var item = items.get_item(position) as FileItem;
                                                  if (item != null && !item.directory)
                                                      activated(item);
                });
        }
        async void load_column(File folder, Gtk.Widget anchor)
        {
            var model = new DirectoryModel();
            yield model.open(folder, get_root() as Gtk.Window);
            if (anchor.get_parent() != columns)
            {
                model.cancel();
                return;
            }
            append_column(folder, model.items);
            model.cancel();
        }
        delegate string ItemText(FileItem item);
        Gtk.SignalListItemFactory text_factory(owned ItemText text)
        {
            var factory = new Gtk.SignalListItemFactory();
            factory.setup.connect((obj) => ((Gtk.ListItem)obj).child = new Gtk.Label(""));
            factory.bind.connect((obj) => { var li = (Gtk.ListItem)obj;
                                            ((Gtk.Label)li.child).label = text((FileItem)li.item);
                });
            return factory;
        }
        Gtk.SignalListItemFactory factory(bool grid)
        {
            var f = new Gtk.SignalListItemFactory();
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
                                       li.child = box;
                });
            f.bind.connect((obj) => { var li = (Gtk.ListItem)obj;
                                      var item = (FileItem)li.item;
                                      var box = (Gtk.Box)li.child;
                                      var image = (Gtk.Image)box.get_first_child();
                                      image.set_from_gicon(item.info.get_icon());
                                      ((Gtk.Label)image.get_next_sibling()).label = item.name;
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
            return f;
        }
        public void cancel()
        {
            navigation_generation++;
            foreach(var token in thumbnail_jobs.values)
                token.cancel();
            directory.cancel();
            search.cancellable.cancel();
            preview.cancel();
            gallery_preview.cancel();
        }
    }
}
