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
        public signal void link_requested(Gee.ArrayList<File> files, File target);
        public File location {
            owned get {
                if(directory.location.get_uri() == "majoris:///home")
                    return File.new_for_path(Environment.get_home_dir());
                return view_mode == "Columns" && column_folder != null ? column_folder : directory.location;
            }
        }
        public bool show_hidden = false;
        bool hidden_preference;
        bool click_preference;
        public ChooserFilter? chooser_filter;
        public bool folders_only;
        public string view_mode = "Grid";
        public MetadataStore metadata;
        public Places places;
        public Gtk.MenuButton share_button = new Gtk.MenuButton();
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
        Gtk.CustomSorter group_sorter;
        string group_key = "None";
        uint group_refresh;
        Cancellable column_sort_token=new Cancellable();
        bool column_sort_pending;
        uint column_model_revision;
        Variant? column_restore;
        bool applying_column_restore;
        string[] group_modes = {
            "None", "Type", "Modified Date", "Size", "Tags", "Recent Date"
        };
        Gtk.FilterListModel filtered;
        Gtk.SortListModel sorted;
        Gtk.Stack views = new Gtk.Stack();
        Gtk.Stack grid_views = new Gtk.Stack();
        GridRows grid_rows;
        Gtk.ListView grouped_grid;
        uint grid_anchor = uint.MAX;
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
        Gtk.Widget? breadcrumb_space;
        Gtk.Box breadcrumbs = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
        Gtk.Box searches;
        Gtk.Paned sidebar_pane;
        Adw.OverlaySplitView sidebar_overlay = new Adw.OverlaySplitView();
        Adw.BreakpointBin adaptive = new Adw.BreakpointBin();
        public bool narrow {
            get {
                return adaptive.current_breakpoint != null;
            }
        }
        public int sidebar_width {
            get {
                return sidebar_pane.position;
            }
            set {
                sidebar_pane.position = value.clamp(120, 420);
            }
        }
        Gtk.DropDown modes;
        Gee.HashMap<string, Gtk.ToggleButton> view_controls = new Gee.HashMap<string, Gtk.ToggleButton>();
        bool chooser_mode;
        public signal void open_in_tab(File file);
        bool recursive;
        bool everywhere;
        bool search_results;
        Gtk.ToggleButton recursive_button;
        bool ascending = true;
        string sort_key = "Name";
        bool rank_results = true;
        SharedFoldersState shares = SharedFoldersState.get_default();
        ulong shares_changed;
        ulong cloud_changed;
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
        ThumbnailService thumbnails;
        Gee.HashMap<Gtk.ListItem, Cancellable> thumbnail_jobs = new Gee.HashMap<Gtk.ListItem, Cancellable>();
        uint sidebar_generation;
        public Browser(MetadataStore metadata, Places places, bool chooser_mode = false)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 0);
            FilesTheme.ensure();
            this.metadata = metadata;
            CloudFiles.get_default().configure(metadata);
            notify["root"].connect(() => {
                if (get_root() != null && shares_changed == 0)
                    shares_changed = shares.changed.connect(() => display_changed());
                if (get_root() != null && cloud_changed == 0)
                    cloud_changed = CloudFiles.get_default().changed.connect(() => {
                        display_changed();
                        if (chooser_filter != null || search_query.active) refilter();
                    });
            });
            this.places = places;
            this.chooser_mode = chooser_mode;
            thumbnails = new ThumbnailService(metadata);
            show_hidden = metadata.state("show-hidden", "false") == "true";
            hidden_preference = show_hidden;
            click_preference = metadata.state("single-click", "false") == "true";
            preview = new PreviewPane(metadata);
            gallery_preview = new PreviewPane(metadata);
            Gtk.RecentManager.get_default().changed.connect(() => {
                if (directory.location.has_uri_scheme("recent")) refresh_collection();
            });
            metadata.changed.connect(() => {
                if (directory.location.get_uri() == "majoris:///favorites") refresh_collection();
                bool hidden = metadata.state("show-hidden", "false") == "true";
                if(hidden != hidden_preference)
                {
                    hidden_preference = hidden;
                    show_hidden = hidden;
                    refilter();
                }
                bool click = metadata.state("single-click", "false") == "true";
                if(click != click_preference)
                {
                    click_preference = click;
                    apply_click_mode(views);
                }
                display_changed();
                if(column_providers.has_key(sort_key)&&column_providers[sort_key] is ExternalColumn&&!((ExternalColumn)column_providers[sort_key]).sort_ready&&!column_sort_pending)set_sort(sort_key,ascending);
                if(group_key == "Tags" && group_refresh == 0)
                    group_refresh = Idle.add(() => { group_refresh = 0;
                                                     var chosen=selection_uris();
                                                     group_sorter.changed(Gtk.SorterChange.DIFFERENT);
                                                     restore_reordered(chosen);
                                                     return Source.REMOVE;
                        });
            });
            location_suggestions = new LocationSuggestions(metadata);
            directory.items.items_changed.connect((position, removed, added) => {
                column_model_revision++;
                for(uint i = position; i < position + added; i++)
                    metadata.reconcile((FileItem)directory.items.get_item(i));
            });
            filter = new Gtk.CustomFilter((obj) => { var item = (FileItem)obj;
                                                     return (show_hidden || !item.hidden || (initial_selection != null && initial_selection.equal(item.file))) && (!folders_only || item.navigable || Paths.is_symlink(item.info)) && (chooser_filter == null || chooser_filter.matches(item)) && (search_results || search_query.matches(item, metadata));
                });
            sorter = new Gtk.CustomSorter((a, b) => compare_items((FileItem)a, (FileItem)b));
            filtered = new Gtk.FilterListModel(directory.items, filter);
            sorted = new Gtk.SortListModel(filtered, sorter);
            group_sorter = new Gtk.CustomSorter((a, b) => FileGroups.compare((FileItem)a, (FileItem)b, group_key, metadata));
            sorted.items_changed.connect(() => update_status());
            selection = new Gtk.MultiSelection(sorted);
            var toolbar = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            toolbar.add_css_class("files-navigation");
            if (chooser_mode) {
            toolbar.append(button("sidebar-show-symbolic", _("Show or Hide Locations"), () => { if (narrow)
                                                                                              sidebar_overlay.show_sidebar = !sidebar_overlay.show_sidebar;
                                                                                          else sidebar_pane.start_child.visible = !sidebar_pane.start_child.visible;
                }));
            }
            toolbar.append(button("go-previous-symbolic", _("Back"), () => { var file = history.back();
                                                                          if (file != null)
                                                                              navigate(file, false);
                }));
            toolbar.append(button("go-next-symbolic", _("Forward"), () => { var file = history.forward();
                                                                         if (file != null)
                                                                             navigate(file, false);
                }));
            toolbar.append(button("go-up-symbolic", _("Parent Folder"), () => { var parent = location.get_parent();
                                                                             if (parent != null)
                                                                                 navigate(parent);
                }));
            toolbar.append(button("view-refresh-symbolic", _("Refresh"), () => navigate(directory.location, false)));
            path.hexpand = true;
            path.placeholder_text = _("Location or URI");
            path.tooltip_text = _("Location (Ctrl+L)");
            path.activate.connect(() => { completion_popup.popdown();
                                          var text = path.text.strip();
                                          if (text == "") return;
                                          var target = Uri.parse_scheme(text) == null && !Path.is_absolute(text) && !text.has_prefix("~") && accepts_destination
                                              ? location.resolve_relative_path(text) : Paths.parse(text);
                                          navigate(target);
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
                if(key == Gdk.Key.Escape) {
                    completion_popup.popdown();
                    path.text = directory.location.get_parse_name();
                    location_bar.visible_child_name = "breadcrumbs";
                    views.grab_focus();
                    return true;
                }
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
            location_bar.add_css_class("majoris-location-bar");
            path.add_css_class("majoris-location-entry");
            location_bar.notify["visible-child-name"].connect(() => {
                if (location_bar.visible_child_name == "entry")
                    location_bar.add_css_class("majoris-location-editing");
                else
                    location_bar.remove_css_class("majoris-location-editing");
            });
            var empty_space = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            empty_space.hexpand = true;
            empty_space.width_request = 32;
            var edit_click = new Gtk.GestureClick();
            edit_click.released.connect(() => edit_location());
            empty_space.add_controller(edit_click);
            // Reattached after each breadcrumb rebuild.
            breadcrumb_space = empty_space;
            search_entry.width_request = 200;
            search_entry.placeholder_text = _("Search files");
            toolbar.append(search_entry);
            append(toolbar);
            var commands = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            commands.add_css_class("files-commands");
            Gtk.MenuButton? sort_control = null;
            if (!chooser_mode) {
                string[] labels = {"New Folder", "Cut", "Copy", "Paste", "Rename", "Share", "Move to Trash"};
                string[] icons = {"folder-new-symbolic", "edit-cut-symbolic", "edit-copy-symbolic", "edit-paste-symbolic", "document-edit-symbolic", "emblem-shared-symbolic", "user-trash-symbolic"};
                string[] actions = {"new-folder", "cut", "copy", "paste", "rename", "share-folder", "trash"};
                for (int i = 0; i < actions.length; i++) {
                    var control = new Gtk.Button();
                    var face = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 5);
                    face.append(new Gtk.Image.from_icon_name(icons[i]));
                    if (i == 0) face.append(new Gtk.Label(_(labels[i])));
                    control.child = face;
                    control.tooltip_text = _(labels[i]);
                    control.update_property(Gtk.AccessibleProperty.LABEL, _(labels[i]), -1);
                    control.action_name = "win." + actions[i];
                    if (actions[i] == "share-folder") {
                        share_button.icon_name = "emblem-shared-symbolic";
                        share_button.tooltip_text = _("Share");
                        share_button.update_property(Gtk.AccessibleProperty.LABEL, _("Share"), -1);
                        commands.append(share_button);
                    } else commands.append(control);
                }
                var sort = new Gtk.MenuButton();
                sort.label = _("Sort");
                var sort_menu = new Menu();
                sort_menu.append(_("Name"), "win.sort-name");
                sort_menu.append(_("Size"), "win.sort-size");
                sort_menu.append(_("Modified"), "win.sort-modified");
                sort_menu.append(_("Descending Order"), "win.descending");
                sort.menu_model = sort_menu;
                sort_control = sort;
            }
            var spacer = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            spacer.hexpand = true;
            commands.append(spacer);
            if (sort_control != null) commands.append(sort_control);
            modes = new Gtk.DropDown.from_strings(chooser_mode ? new string[] {"Grid", "List"}
                                                                                             : new string[] {"Grid", "List", "Columns", "Gallery"});
            modes.tooltip_text = _("View");
            modes.notify["selected"].connect(() => set_view(new string[] {"Grid", "List", "Columns", "Gallery"}
                [modes.selected]));
            if (chooser_mode) commands.append(modes);
            else {
                string[] names = {"Grid", "List", "Columns", "Gallery"};
                string[] icons = {"view-grid-symbolic", "view-list-symbolic", "view-dual-symbolic", "view-paged-symbolic"};
                for (int i = 0; i < names.length; i++) {
                    string name = names[i];
                    var control = new Gtk.ToggleButton();
                    control.icon_name = icons[i];
                    control.tooltip_text = _(name);
                    control.update_property(Gtk.AccessibleProperty.LABEL, _(name), -1);
                    if (name != "Grid") control.set_group(view_controls["Grid"]);
                    control.active = name == view_mode;
                    view_controls[name] = control;
                    control.toggled.connect(() => { if (control.active) set_view(name); });
                    commands.append(control);
                }
            }
            commands.append(button("preferences-system-symbolic", _("View Settings"), () => show_view_settings()));
            if (!chooser_mode) {
                var preview_button = new Gtk.Button.from_icon_name("view-reveal-symbolic");
                preview_button.tooltip_text = _("Preview");
                preview_button.action_name = "win.preview";
                commands.append(preview_button);
            }
            append(commands);
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

            recursive_button = new Gtk.ToggleButton.with_label("Include Subfolders");
            recursive_button.toggled.connect(() => { recursive = recursive_button.active;
                                                     run_search();
                });
            searches.append(recursive_button);
            searches.append(button("globe-symbolic", _("Search Home"), () => {
                search_query.text = search_entry.text;
                var query = search_query;
                navigate(File.new_for_path(Environment.get_home_dir()));
                search_query = query;
                search_entry.text = query.text;
                searches.visible = true;
                recursive_button.active = true;
                run_search();
            }));
            searches.append(button("network-workgroup-symbolic", _("Search Everywhere (Home and mounted locations)"), () => {
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
            searches.append(button("view-filter-symbolic", _("Search Filters"), () => {
                search_query.text = search_entry.text;
                var dialog = new SearchFilters(search_query);
                dialog.applied.connect((query) => { search_query = query;
                                                    run_search();
                    });
                dialog.present(this);
            }));
            var search_options = new Gtk.MenuButton();
            search_options.icon_name = "view-filter-symbolic";
            search_options.tooltip_text = _("Search Options");
            var search_popover = new Gtk.Popover();
            searches.visible = true;
            searches.orientation = Gtk.Orientation.VERTICAL;
            search_popover.child = searches;
            search_options.popover = search_popover;
            toolbar.append(search_options);
            search_entry.search_changed.connect(run_search);
            var body = new Gtk.Paned(Gtk.Orientation.HORIZONTAL);
            sidebar_pane = body;
            body.vexpand = true;
            body.position = 180;
            body.shrink_start_child = true;
            var side_scroll = new Gtk.ScrolledWindow();
            side_scroll.set_child(sidebar);
            sidebar.selection_mode = Gtk.SelectionMode.SINGLE;
            sidebar.add_css_class("navigation-sidebar");
            sidebar.add_css_class("files-sidebar");
            sidebar.set_header_func((row, before) => {
                var place = places.entries[row.get_index()];
                string? section = place.section != "" && (before == null || places.entries[before.get_index()].section != place.section) ? _(place.section) : null;
                if (section != null) { var heading = new Gtk.Label(section); heading.halign = Gtk.Align.START; heading.add_css_class("files-section"); row.set_header(heading); }
                else row.set_header(null);
            });
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
            preview.visible = metadata.state("preview-pane-default", "false") == "true";
            body.end_child = content;
            sidebar_overlay.content = body;
            sidebar_overlay.collapsed = true;
            sidebar_overlay.show_sidebar = false;
            sidebar_overlay.min_sidebar_width = 180;
            sidebar_overlay.max_sidebar_width = 300;
            adaptive.child = sidebar_overlay;
            adaptive.vexpand = true;
            adaptive.width_request = 320;
            adaptive.height_request = 240;
            var breakpoint = new Adw.Breakpoint(Adw.BreakpointCondition.parse("max-width: 650px"));
            breakpoint.apply.connect(() => {
                body.start_child = null;
                sidebar_overlay.sidebar = side_scroll;
                side_scroll.visible = true;
                sidebar_overlay.collapsed = true;
                sidebar_overlay.show_sidebar = false;
            });
            breakpoint.unapply.connect(() => {
                sidebar_overlay.show_sidebar = false;
                sidebar_overlay.sidebar = null;
                sidebar_overlay.collapsed = true;
                body.start_child = side_scroll;
                side_scroll.visible = true;
            });
            breakpoint.add_setter(preview, "visible", false);
            breakpoint.add_setter(modes, "visible", false);
            if (chooser_mode) adaptive.add_breakpoint(breakpoint);
            append(adaptive);
            var grid = new Gtk.GridView(selection, factory(true));
            grid.min_columns = 1;
            grid.max_columns = 16;
            grid.enable_rubberband = true;
            grid.single_click_activate = metadata.state("single-click", "false") == "true";
            grid.activate.connect(activate_position);
            grid_views.add_named(grid, "plain");
            grid_rows = new GridRows(sorted, metadata);
            var rows_factory = new Gtk.SignalListItemFactory();
            rows_factory.bind.connect((obj) => {
                var li=(Gtk.ListItem)obj;var row=(GridRow)li.item;
                li.selectable=false;li.activatable=false;
                if(row.heading){
                    var label=new Gtk.Label(row.label);
                    label.halign=Gtk.Align.START;label.margin_start=16;label.margin_top=12;label.margin_bottom=6;
                    label.add_css_class("heading");label.update_property(Gtk.AccessibleProperty.LABEL,label.label,-1);
                    li.child=label;
                }else{
                    var slice=new GridSlice(selection,row.start,row.count);
                    var cells=new Gtk.GridView(slice,factory(true,slice));
                    cells.min_columns=grid_rows.columns;cells.max_columns=grid_rows.columns;
                    cells.single_click_activate=metadata.state("single-click","false")=="true";
                    cells.enable_rubberband=true;
                    cells.set_data<GridSlice>("majoris-grid-slice",slice);
                    cells.activate.connect((p)=>activate_position(slice.offset+p));
                    li.child=cells;
                }
            });
            rows_factory.unbind.connect((obj)=>{var li=(Gtk.ListItem)obj;if(li.child is Gtk.GridView){var cells=(Gtk.GridView)li.child;var slice=cells.get_data<GridSlice>("majoris-grid-slice");cells.model=null;if(slice!=null)slice.detach();}li.child=null;});
            grouped_grid=new Gtk.ListView(null,rows_factory);
            grid_views.add_named(grouped_grid,"grouped");
            grid_views.visible_child_name="plain";
            grid_views.add_tick_callback(()=>{
                if(grid_views.visible_child_name=="grouped"){
                    // Measure against the viewport, not the child's forced
                    // minimum width (which otherwise feeds back into columns).
                    var context=get_pango_context();var metrics=context.get_metrics(null,context.get_language());
                    int text_width=(int)(18L*metrics.get_approximate_char_width()/Pango.SCALE);
                    int cell_width=int.max(icon_size,text_width)+64;
                    int available=get_width()-(sidebar_pane.start_child==null?0:sidebar_pane.position)-(preview.visible?preview.get_width():0)-24;
                    grid_rows.resize((uint)int.max(1,available/cell_width));
                }
                return Source.CONTINUE;
            });
            views.add_named(scrolled(grid_views), "Grid");
            var list = new Gtk.ColumnView(selection);
            list.header_factory = group_headers();
            list.show_column_separators = true;
            list.enable_rubberband = true;
            list.single_click_activate = metadata.state("single-click", "false") == "true";
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
            strip.single_click_activate = metadata.state("single-click", "false") == "true";
            strip.header_factory = group_headers();
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
            status.halign = Gtk.Align.FILL;
            status.xalign = 0;
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
                location_error.title = _("Cannot load ") + directory.location.get_parse_name() + ": " + message;
                location_error.revealed = true;
            });
            directory.loaded.connect(() => { update_status();
                                             restore_selection();
                                             if(column_providers.has_key(sort_key)&&column_providers[sort_key] is ExternalColumn&&!column_sort_pending)set_sort(sort_key,ascending);
                                             if (view_mode == "Columns")
                                                 build_columns();
                });
            search.found.connect((item) => directory.items.append(item));
            search.progress.connect((folders, skipped) => {
                if(search_results)
                    status.label = _("%u results · %u folders scanned · %u unavailable").printf(sorted.get_n_items(), folders, skipped) + " · " + search.backend_status;
            });
            var keys = new Gtk.EventControllerKey();
            keys.key_pressed.connect((key, code, mods) => {
                if (key == Gdk.Key.F5) { navigate(directory.location, false); return true; }
                if(key == Gdk.Key.Escape && location_bar.visible_child_name == "entry")
                {
                    completion_popup.popdown();
                    path.text = directory.location.get_parse_name();
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
                    if (key == Gdk.Key.d) { edit_location(); return true; }
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
            b.update_property(Gtk.AccessibleProperty.LABEL,tooltip,-1);
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
            if(place.cloud != null && place.cloud.get_menu_model() != null && place.cloud.get_action_group() != null)
            {
                menu.insert_action_group("cloudprovider", place.cloud.get_action_group());
                var provider_menu = new Gtk.MenuButton();
                provider_menu.label = _("Cloud Account Actions");
                provider_menu.menu_model = place.cloud.get_menu_model();
                box.append(provider_menu);
            }
            Gdk.Rectangle rect = {
                (int)x, (int)y, 1, 1
            };
            menu.pointing_to = rect;
            menu.closed.connect(() => menu.unparent());
            var tab = new Gtk.Button.with_label(_("Open in New Tab"));
            tab.clicked.connect(() => { open_in_tab(place.file);
                                        menu.popdown();
                });
            box.append(tab);
            if(place.bookmark)
            {
                var rename = new Gtk.Button.with_label(_("Rename Bookmark"));
                rename.clicked.connect(() => { menu.popdown();
                                               rename_bookmark.begin(place);
                    });
                box.append(rename);
                var remove = new Gtk.Button.with_label(_("Remove Bookmark"));
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
                var mount = new Gtk.Button.with_label(_("Mount"));
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
            if(file.has_uri_scheme("recent") || file.get_uri() == "majoris:///favorites") {
                var crumb = new Gtk.Button.with_label(file.has_uri_scheme("recent") ? _("Recent") : _("Favorites"));
                crumb.add_css_class("majoris-location-crumb");
                crumb.add_css_class("majoris-location-current");
                crumb.clicked.connect(() => navigate(file));
                breadcrumbs.append(crumb);
                if (breadcrumb_space != null) breadcrumbs.append(breadcrumb_space);
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
                crumb.add_css_class("majoris-location-crumb");
                if (parent.equal(file)) crumb.add_css_class("majoris-location-current");
                crumb.tooltip_text = parent.get_parse_name();
                crumb.clicked.connect(() => navigate(parent));
                var middle = new Gtk.GestureClick();
                middle.button = 2;
                middle.pressed.connect(() => open_in_tab(parent));
                crumb.add_controller(middle);
                if (breadcrumbs.get_first_child() != null) {
                    var separator = new Gtk.Label("›");
                    separator.add_css_class("majoris-location-separator");
                    breadcrumbs.append(separator);
                }
                breadcrumbs.append(crumb);
            }
            if (breadcrumb_space != null) breadcrumbs.append(breadcrumb_space);
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
            string base_state = new Variant("(sbb@asdd)", saved_query(), recursive, everywhere, chosen.end(), scroll == null ? 0.0 : scroll.hadjustment.value, scroll == null ? 0.0 : scroll.vadjustment.value).print(true);
            if(view_mode != "Columns")
                return base_state;
            var chain = new VariantBuilder(new VariantType("a(sasdd)"));
            for(var widget = columns.get_first_child(); widget != null; widget = widget.get_next_sibling())
            {
                var model = column_selections[widget];
                var selected_uris = new VariantBuilder(new VariantType("as"));
                for(uint i = 0; i < model.get_n_items(); i++)
                    if(model.is_selected(i))
                        selected_uris.add("s", ((FileItem)model.get_item(i)).file.get_uri());
                var folder = loaded_columns.has_key(widget) ? loaded_columns[widget].location : directory.location;
                var column_scroll = (Gtk.ScrolledWindow)widget;
                chain.add("(s@asdd)", folder.get_uri(), selected_uris.end(), column_scroll.hadjustment.value, column_scroll.vadjustment.value);
            }
            return "columns-v1:" + new Variant("(s@a(sasdd))", base_state, chain.end()).print(true);
        }
        public void restore_session_state(string saved) throws Error
        {
            if(saved.length > 4 * 1024 * 1024)
                throw new FileError.INVALID("Browsing state is too large");
            string base_state = saved;
            Variant? pending_restore = null;
            column_restore = null;
            if(saved.has_prefix("columns-v1:"))
            {
                var wrapper = Variant.parse(new VariantType("(sa(sasdd))"), saved.substring(11));
                var chain = wrapper.get_child_value(1);
                if(chain.n_children() > 32)
                    throw new FileError.INVALID("Too many restored columns");
                File? previous = null;
                for(size_t i = 0; i < chain.n_children(); i++)
                {
                    var entry = chain.get_child_value(i);
                    string uri = entry.get_child_value(0).get_string();
                    double x = entry.get_child_value(2).get_double(), y = entry.get_child_value(3).get_double();
                    if(Uri.parse_scheme(uri) == null || !x.is_finite() || !y.is_finite() || x < 0 || y < 0 || entry.get_child_value(1).n_children() > 10000)
                        throw new FileError.INVALID("Invalid restored column");
                    var folder = File.new_for_uri(uri);
                    if(i == 0 && !folder.equal(directory.location))
                        throw new FileError.INVALID("Column root differs from session location");
                    if(previous != null && (folder.get_parent() == null || !folder.get_parent().equal(previous)))
                        throw new FileError.INVALID("Invalid column ancestry");
                    previous = folder;
                }
                pending_restore = chain;
                base_state = wrapper.get_child_value(0).get_string();
            }
            var value = Variant.parse(new VariantType("(sbbasdd)"), base_state);
            var query = SearchQuery.deserialize(value.get_child_value(0).get_string());
            var chosen = value.get_child_value(3);
            double horizontal = value.get_child_value(4).get_double(), vertical = value.get_child_value(5).get_double();
            if(chosen.n_children() > 10000 || !horizontal.is_finite() || !vertical.is_finite() || horizontal < 0 || vertical < 0)
                throw new FileError.INVALID("Invalid browsing state");
            column_restore = pending_restore;
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
            searches.visible = true;
            recursive_button.active = recursive;
            if(query.active)
                run_search();
            else refilter();
            restore_selection();
            if(view_mode == "Columns" && !directory.loading)
                build_columns();
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
            if (search_results && rank_results && x.relevance != y.relevance)
                return x.relevance > y.relevance ? -1 : 1;
            if(folders_first && x.directory != y.directory)
                return x.directory ? -1 : 1;
            int result;
            if(column_providers.has_key(sort_key))
                result = column_providers[sort_key].compare(x, y, metadata);
            else if(sort_key == "Size")
                result = x.bytes < y.bytes ? -1 : x.bytes == y.bytes ? 0 : 1;
            else if(sort_key == "Recent Date") {
                uint64 a = x.info.get_attribute_uint64("majoris::recent"), b = y.info.get_attribute_uint64("majoris::recent");
                result = a < b ? -1 : a == b ? 0 : 1;
            }
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
            if(details == null || loading_display || metadata.state("remember-folder-settings", "true") != "true")
                return;
            var columns_state = new VariantBuilder(new VariantType("a(sbi)"));
            for(uint i = 0; i < details.columns.get_n_items(); i++)
            {
                var column = (Gtk.ColumnViewColumn)details.columns.get_item(i);
                columns_state.add("(sbi)", column.title, column.visible, column.fixed_width);
            }
            metadata.set_state("display:" + directory.location.get_uri(), new Variant("(sbbib@a(sbi))", sort_key, ascending, folders_first, icon_size, selection_checkboxes, columns_state.end()).print(true));
            metadata.set_state("caption:" + directory.location.get_uri(), caption_key);
            metadata.set_state("group:" + directory.location.get_uri(), group_key);
        }
        void load_display(File location)
        {
            loading_display = true;
            sort_key = "Name";
            ascending = true;
            folders_first = metadata.state("default-folders-first", "true") == "true";
            string density = metadata.state("default-density", "Standard");
            icon_size = density == "Compact" ? 32 : density == "Large" ? 128 : 64;
            selection_checkboxes = metadata.state("default-checkboxes", "false") == "true";
            bool remember = metadata.state("remember-folder-settings", "true") == "true";
            group_key = remember ? metadata.state("group:" + location.get_uri(), "None") : "None";
            if(!(group_key in group_modes))
                group_key = "None";
            grid_rows.mode = group_key;
            sorted.section_sorter = group_key == "None" ? null : group_sorter;
            grid_views.visible_child_name = group_key == "None" ? "plain" : "grouped";
            grouped_grid.model = group_key == "None" || view_mode!="Grid" ? null : new Gtk.NoSelection(grid_rows);
            group_sorter.changed(Gtk.SorterChange.DIFFERENT);
            caption_key = remember ? metadata.state("caption:" + location.get_uri(), "None") : "None";
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
            var saved = remember ? metadata.state("display:" + location.get_uri()) : "";
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
                        uint position = (uint)seen.size - 1;
                        if (details.columns.get_item(position) != column) {
                            details.remove_column(column);
                            details.insert_column(position, column);
                        }
                    }
                }
                catch(Error e) {   /* Invalid preferences fall back to the defaults. */
                }
            }
            sorter.changed(Gtk.SorterChange.DIFFERENT);
            display_changed();
            loading_display = false;
            if(column_providers.has_key(sort_key)&&column_providers[sort_key] is ExternalColumn){string key=sort_key;sort_key="Name";column_sort_token.cancel();column_sort_token=new Cancellable();column_sort_pending=true;prepare_external_sort.begin(key,ascending,location,column_sort_token);}
        }
        public void show_view_settings()
        {
            var dialog = new Adw.PreferencesDialog();
            dialog.title = _("View Settings");
            var page = new Adw.PreferencesPage();
            dialog.add(page);
            var group = new Adw.PreferencesGroup();
            group.title = _("This Folder");
            page.add(group);
            var view = new Adw.ComboRow();
            view.title = _("View");
            string[] view_names = chooser_mode ? new string[] {
                "Grid", "List"
            }
                                                                               : new string[] {
                "Grid", "List", "Columns", "Gallery"
            };
            view.model = new Gtk.StringList(view_names);
            for(uint i = 0; i < view_names.length; i++)
                if(view_names[i] == view_mode)
                    view.selected = i;
            view.notify["selected"].connect(() => set_view(view_names[view.selected]));
            group.add(view);
            var size = new Adw.ComboRow();
            size.title = _("Icon Density");
            size.model = new Gtk.StringList({"Compact", "Standard", "Large"});
            size.selected = icon_size < 64 ? 0 : icon_size > 64 ? 2 : 1;
            group.add(size);
            var grouping = new Adw.ComboRow();
            grouping.title = _("Group By");
            grouping.model = new Gtk.StringList(group_modes);
            for(uint i = 0; i < group_modes.length; i++)
                if(group_modes[i] == group_key)
                    grouping.selected = i;
            group.add(grouping);
            grouping.notify["selected"].connect(() => set_group(group_modes[grouping.selected]));
            var caption = new Adw.ComboRow();
            caption.title = _("Grid Metadata Caption");
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
            checkboxes.title = _("Selection Checkboxes");
            checkboxes.active = selection_checkboxes;
            group.add(checkboxes);
            checkboxes.notify["active"].connect(() => { selection_checkboxes = checkboxes.active;
                                                        display_changed();
                                                        save_display();
                });
            var folders = new Adw.SwitchRow();
            folders.title = _("Folders First");
            folders.active = folders_first;
            group.add(folders);
            folders.notify["active"].connect(() => { folders_first = folders.active;
                                                     sorter.changed(Gtk.SorterChange.DIFFERENT);
                                                     save_display();
                });
            var sort = new Adw.ComboRow();
            sort.title = _("Sort By");
            sort.model = new Gtk.StringList(column_titles);
            for(uint i = 0; i < column_titles.length; i++)
                if(column_titles[i] == sort_key)
                    sort.selected = i;
            group.add(sort);
            sort.notify["selected"].connect(() => set_sort(column_titles[sort.selected], ascending));
            var direction = new Adw.SwitchRow();
            direction.title = _("Descending Order");
            direction.active = !ascending;
            group.add(direction);
            direction.notify["active"].connect(() => set_sort(sort_key, !direction.active));
            var columns_group = new Adw.PreferencesGroup();
            columns_group.title = _("List Columns");
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
                width.tooltip_text = _("Column Width (pixels)");
                row.add_suffix(width);
                width.value_changed.connect(() => { column.fixed_width = width.get_value_as_int();
                                                    save_display();
                    });
                var up = new Gtk.Button.from_icon_name("go-up-symbolic");
                up.valign = Gtk.Align.CENTER;
                up.tooltip_text = _("Move Column Left");
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
            column_sort_token.cancel();column_sort_token=new Cancellable();
            if(column_providers.has_key(key)&&column_providers[key] is ExternalColumn){column_sort_pending=true;prepare_external_sort.begin(key,ascending,directory.location,column_sort_token);return;}
            column_sort_pending=false;
            if(sort_key!=key&&column_providers.has_key(sort_key)&&column_providers[sort_key] is ExternalColumn)((ExternalColumn)column_providers[sort_key]).release_sort();
            var chosen=selection_uris();
            sort_key = key;
            this.ascending = ascending;
            sorter.changed(Gtk.SorterChange.DIFFERENT);
            restore_reordered(chosen);
            save_display();
            session_changed();
        }
        async void prepare_external_sort(string key,bool direction,File expected,Cancellable token){
            status.label=_("Preparing extension sort…");
            try{
                int64 deadline=get_monotonic_time()+30*1000000L;
                while(directory.loading||!directory.location.equal(expected)){token.set_error_if_cancelled();if(get_monotonic_time()>deadline)throw new IOError.TIMED_OUT("Folder did not finish loading for extension sorting");Timeout.add(50,()=>{prepare_external_sort.callback();return Source.REMOVE;});yield;}
                uint revision=column_model_revision;var column=(ExternalColumn)column_providers[key];yield column.prepare_sort(directory.items,token);token.set_error_if_cancelled();
                if(revision!=column_model_revision||!directory.location.equal(expected)){if(sort_key==key)set_sort("Name",direction);throw new IOError.BUSY("Folder changed while extension sort values were loading; choose the sort again");}
                var chosen=selection_uris();if(sort_key!=key&&column_providers.has_key(sort_key)&&column_providers[sort_key] is ExternalColumn)((ExternalColumn)column_providers[sort_key]).release_sort();
                sort_key=key;ascending=direction;sorter.changed(Gtk.SorterChange.DIFFERENT);restore_reordered(chosen);save_display();session_changed();
            }catch(Error e){if(!(e is IOError.CANCELLED))error(e.message);}
            finally{if(column_sort_token==token){column_sort_pending=false;update_status();}}
        }
        public void set_group(string mode)
        {
            if(!(mode in group_modes))
                return;
            var chosen=selection_uris();
            group_key = mode;
            grid_rows.mode = mode;
            sorted.section_sorter = mode == "None" ? null : group_sorter;
            grid_views.visible_child_name = mode == "None" ? "plain" : "grouped";
            grouped_grid.model = mode == "None" || view_mode!="Grid" ? null : new Gtk.NoSelection(grid_rows);
            group_sorter.changed(Gtk.SorterChange.DIFFERENT);
            restore_reordered(chosen);
            save_display();
            session_changed();
        }
        Gee.HashSet<string> selection_uris(){
            var result=new Gee.HashSet<string>();var iterator=Gtk.BitsetIter();uint position;
            if(iterator.init_first(selection.get_selection(),out position))do{var item=selection.get_item(position) as FileItem;if(item!=null)result.add(item.file.get_uri());}while(iterator.next(out position));return result;
        }
        void restore_reordered(Gee.HashSet<string> uris){
            var selected=new Gtk.Bitset.empty();var mask=new Gtk.Bitset.empty();mask.add_range(0,selection.get_n_items());
            for(uint i=0;i<selection.get_n_items();i++){var item=selection.get_item(i) as FileItem;if(item!=null&&uris.contains(item.file.get_uri()))selected.add(i);}
            selection.set_selection(selected,mask);grid_anchor=uint.MAX;
        }
        Gtk.SignalListItemFactory group_headers()
        {
            var headers = new Gtk.SignalListItemFactory();
            headers.setup.connect((obj) => {
                var label = new Gtk.Label("");
                label.halign = Gtk.Align.START;
                label.margin_start = 12;
                label.margin_top = 12;
                label.margin_bottom = 6;
                label.add_css_class("heading");
                ((Gtk.ListHeader)obj).child = label;
            });
            headers.bind.connect((obj) => {
                var header = (Gtk.ListHeader)obj;
                var label = (Gtk.Label)header.child;
                label.label = FileGroups.label((FileItem)header.item, group_key, metadata);
                label.visible = group_key != "None";
            });
            return headers;
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
        public string extension_columns_signature="";
        public bool has_column(string title){return detail_columns.has_key(title);}
        public void remove_extension_columns(Gee.Set<string> retained){
            var obsolete=new Gee.ArrayList<string>();foreach(var title in column_providers.keys)if(column_providers[title] is ExternalColumn&&!retained.contains(title))obsolete.add(title);
            foreach(var title in obsolete){if(sort_key==title)set_sort("Name",ascending);details.remove_column(detail_columns[title]);detail_columns.unset(title);column_providers.unset(title);var names=new Gee.ArrayList<string>();foreach(var name in column_titles)if(name!=title)names.add(name);column_titles=names.to_array();}
        }
        public void set_view(string mode, bool remember = true)
        {
            if(chooser_mode && mode != "Grid" && mode != "List")
                mode = "Grid";
            if(view_mode == mode)
                return;
            view_mode = mode;
            foreach (var name in view_controls.keys) view_controls[name].active = name == mode;
            grouped_grid.model = group_key == "None" || mode!="Grid" ? null : new Gtk.NoSelection(grid_rows);
            views.visible_child_name = mode == "Columns" && virtual_collection ? "List" : mode;
            if(remember && metadata.state("remember-folder-settings", "true") == "true")
                metadata.set_state("view:" + location.get_uri(), mode);
            modes.selected = mode == "Grid" ? 0 : mode == "List" ? 1 : mode == "Columns" ? 2 : 3;
            session_changed();
            if (mode == "Columns" && !virtual_collection)
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
                if(place.cloud != null)
                    label.tooltip_text = place.cloud.get_status_details();
                label.halign = Gtk.Align.START;
                label.margin_start = 10;
                label.margin_end = 10;
                label.margin_top = 8;
                label.margin_bottom = 8;
                var place_row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
                string icon_name = place.file.has_uri_scheme("recent") ? "document-open-recent-symbolic"
                    : place.file.get_uri() == "majoris:///favorites" ? "starred-symbolic"
                    : place.file.has_uri_scheme("trash") ? "user-trash-symbolic"
                    : place.file.has_uri_scheme("network") ? "network-workgroup-symbolic"
                    : place.mount != null || place.volume != null ? "drive-harddisk-symbolic"
                    : place.label == "Home" ? "user-home-symbolic" : "folder-symbolic";
                var icon = place.cloud != null && place.cloud.get_icon() != null
                    ? new Gtk.Image.from_gicon(place.cloud.get_icon()) : new Gtk.Image.from_icon_name(icon_name);
                icon.margin_start = 10;
                place_row.append(icon);
                label.hexpand = true;
                label.ellipsize = Pango.EllipsizeMode.END;
                place_row.append(label);
                sidebar.append(place_row);
                if (place.file.equal(directory.location)) sidebar.select_row(sidebar.get_row_at_index(places.entries.index_of(place)));
                if(!chooser_mode)
                    add_drop(label, () => place.file);
                if(place.bookmark)
                    add_bookmark_drag(label, place);
            }
        }
        void add_bookmark_drag(Gtk.Widget widget, Place place)
        {
            var drag = new Gtk.DragSource();
            drag.actions = Gdk.DragAction.MOVE;
            drag.prepare.connect(() => {
                var value = Value(typeof(Place));
                value.set_object(place);
                return new Gdk.ContentProvider.for_value(value);
            });
            widget.add_controller(drag);
            var drop = new Gtk.DropTarget(typeof(Place), Gdk.DragAction.MOVE);
            drop.drop.connect((value, x, y) => {
                var source = value.get_object() as Place;
                if(source == null || !source.bookmark)
                    return false;
                places.reorder_bookmark.begin(source.file, place.file, y >= widget.get_height() / 2.0, (obj, res) => {
                    try { places.reorder_bookmark.end(res);
                    }
                    catch(Error e) { error(e.message);
                    }
                });
                return true;
            });
            widget.add_controller(drop);
        }
        public bool accepts_destination {
            get { return !location.has_uri_scheme("majoris") && !location.has_uri_scheme("recent") && !location.has_uri_scheme("trash"); }
        }
        public bool virtual_collection {
            get { return directory.location.has_uri_scheme("recent") || directory.location.get_uri() == "majoris:///favorites"; }
        }
        public void navigate(File file, bool record = true)
        {
            // Migrate old saved Home Overview tabs into the new default collection.
            if (file.get_uri() == "majoris:///home") { navigate(File.new_for_uri("recent:///"), record); return; }
            location_bar.visible_child_name = "breadcrumbs";
            column_sort_token.cancel();column_sort_pending=false;
            if(narrow)
                sidebar_overlay.show_sidebar = false;
            column_restore = null;
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
            string recursive_policy = metadata.state("recursive-search", "Never");
            recursive = recursive_policy == "Always" || (recursive_policy == "Local" && file.is_native());
            if (file.has_uri_scheme("recent") || file.has_uri_scheme("majoris")) recursive = false;
            recursive_button.active = recursive;
            search.cancellable.cancel();
            search_query = new SearchQuery();
            search_entry.text = "";
            path.text = file.get_parse_name();
            if (file.has_uri_scheme("recent") || file.has_uri_scheme("majoris")) directory.virtual_location(file);
            load_display(file);
            if (file.has_uri_scheme("recent")) {
                set_group("Recent Date");
                sort_key = "Recent Date"; ascending = false;
                sorter.changed(Gtk.SorterChange.DIFFERENT);
            }
            if (file.has_uri_scheme("recent") || file.get_uri() == "majoris:///favorites") {
                caption_key = "Location";
                detail_columns["Location"].visible = true;
            }
            display_changed();
            if (record)
                history.visit(file);
            initial_selection = null;
            build_breadcrumbs(file);
            string default_view = metadata.state("default-view", "Grid");
            set_view(metadata.state("remember-folder-settings", "true") == "true" ? metadata.state("view:" + file.get_uri(), default_view) : default_view, false);
            modes.sensitive = file.get_uri() != "majoris:///home";
            views.visible_child_name = view_mode == "Columns" && virtual_collection ? "List" : view_mode;
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
                var files = ActivityFiles.recent();
                load_virtual.begin(files, navigation_generation);
            }
            else directory.open.begin(file, get_root() as Gtk.Window);
            update_status();
            for (int i = 0; i < places.entries.size; i++)
                if (places.entries[i].file.equal(file)) sidebar.select_row(sidebar.get_row_at_index(i));
            location_changed(file);
            session_changed();
        }
        uint collection_refresh;
        void refresh_collection() {
            if (collection_refresh != 0) return;
            collection_refresh = Idle.add(() => {
                collection_refresh = 0;
                if (!virtual_collection) return Source.REMOVE;
                var selected = selection_uris();
                navigation_generation++;
                directory.items.remove_all();
                var files = new Gee.ArrayList<File>();
                if (directory.location.has_uri_scheme("recent")) {
                    files.add_all(ActivityFiles.recent());
                } else files.add_all(metadata.favorites());
                load_virtual.begin(files, navigation_generation, (obj, res) => { load_virtual.end(res); restore_reordered(selected); });
                return Source.REMOVE;
            });
        }
        async void load_virtual(Gee.List<File> files, uint epoch)
        {
            var dates = new Gee.HashMap<string, int64?>();
            if (directory.location.has_uri_scheme("recent"))
                foreach (var recent in Gtk.RecentManager.get_default().get_items()) dates[recent.get_uri()] = recent.get_modified().to_unix();
            foreach (var file in files)
            {
                if (epoch != navigation_generation) return;
                try {
                    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, null);
                    if (epoch != navigation_generation)
                        return;
                    if (dates.has_key(file.get_uri())) info.set_attribute_uint64("majoris::recent", (uint64)dates[file.get_uri()]);
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
                if(Paths.is_symlink(item.info))
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
            var chosen = selected();
            uint64 bytes = 0;
            foreach(var item in chosen)
                if(!item.directory)
                    bytes += item.bytes;
            status.add_css_class("files-status");
            status.label = _("%u items · %d selected").printf(sorted.get_n_items(), chosen.size) + (chosen.size > 0 ? " · " + Paths.size(bytes) : "") + (search_results ? " · %u folders scanned · %u unavailable".printf(search.scanned, search.unreadable) : "");
        }
        void run_search()
        {
            rank_results = metadata.state("rank-search-results", "true") == "true";
            search.cancellable.cancel();
            search_query.text = search_entry.text;
            search_query.scope = everywhere ? "everywhere" : recursive ? "recursive" : "folder";
            if (!virtual_collection && (recursive || everywhere || search_query.content != "") && search_query.active)
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
            else if (search_results && !virtual_collection)
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
            var root = append_column(directory.location, sorted);
            if(!directory.loading)
                restore_column(root, directory.location);
        }
        void restore_column(Gtk.Widget widget, File folder)
        {
            if(column_restore == null)
                return;
            for(size_t i = 0; i < column_restore.n_children(); i++)
            {
                var entry = column_restore.get_child_value(i);
                if(entry.get_child_value(0).get_string() != folder.get_uri())
                    continue;
                var chosen = entry.get_child_value(1);
                var wanted = new Gee.HashSet<string>();
                for(size_t j = 0; j < chosen.n_children(); j++)
                    wanted.add(chosen.get_child_value(j).get_string());
                var model = column_selections[widget];
                applying_column_restore = true;
                model.unselect_all();
                for(uint j = 0; j < model.get_n_items(); j++)
                    if(wanted.contains(((FileItem)model.get_item(j)).file.get_uri()))
                        model.select_item(j, false);
                applying_column_restore = false;
                var scroll = (Gtk.ScrolledWindow)widget;
                double x = entry.get_child_value(2).get_double(), y = entry.get_child_value(3).get_double();
                uint frames = 0;
                widget.add_tick_callback(() => {
                    scroll.hadjustment.value = x;
                    scroll.vadjustment.value = y;
                    return ++frames < 8 ? Source.CONTINUE : Source.REMOVE;
                });
                return;
            }
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
            list.single_click_activate = metadata.state("single-click", "false") == "true";
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
                if(!applying_column_restore)
                    column_restore = null;
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
                else { preview.visible = !narrow;
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
            restore_column(child, folder);
        }
        delegate string ItemText(FileItem item);
        void apply_click_mode(Gtk.Widget widget)
        {
            bool single = metadata.state("single-click", "false") == "true";
            if(widget is Gtk.ListView)
                ((Gtk.ListView)widget).single_click_activate = single;
            if(widget is Gtk.GridView)
                ((Gtk.GridView)widget).single_click_activate = single;
            if(widget is Gtk.ColumnView)
                ((Gtk.ColumnView)widget).single_click_activate = single;
            for(var child = widget.get_first_child(); child != null; child = child.get_next_sibling())
                apply_click_mode(child);
        }
        string visible_name(FileItem item)
        {
            string name = item.name;
            if(!item.directory && metadata.state("show-extensions", "true") != "true")
            {
                int dot = name.last_index_of(".");
                if(dot > 0)
                    return name.substring(0, dot);
            }
            return name;
        }
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
        Gtk.SignalListItemFactory factory(bool grid, Gtk.SelectionModel? row_selection = null)
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
                                       var icon_area = new Gtk.Overlay(); icon_area.child = icon;
                                       var cloud_badge = new Gtk.Image(); cloud_badge.pixel_size = 16;
                                       cloud_badge.halign = Gtk.Align.END; cloud_badge.valign = Gtk.Align.END;
                                       cloud_badge.can_target = false; cloud_badge.visible = false;
                                       icon_area.add_overlay(cloud_badge); box.append(icon_area);
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
                                       caption.visible = grid && (caption_key != "None" || virtual_collection);
                                       if(grid)
                                           box.append(caption);
                                       var checkbox = new Gtk.CheckButton();
                                       checkbox.tooltip_text = _("Select Item");
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
                                       string thumbnail_settings = metadata.state("thumbnail-policy", "Local") + metadata.state("remote-thumbnail-limit", "8");
                                       display_handlers[li] = display_changed.connect(() => {
                    icon.pixel_size = grid ? icon_size : (icon_size > 64 ? 32 : 24);
                    int spacing = icon_size < 64 ? 4 : 8;
                    box.margin_top = spacing;
                    box.margin_bottom = spacing;
                    checkbox.visible = selection_checkboxes;
                    caption.visible = grid && (caption_key != "None" || virtual_collection);
                    if(grid && li.item != null)
                        caption.label = column_text((FileItem)li.item, caption_key);
                    if(li.item != null)
                        label.label = visible_name((FileItem)li.item);
                    if(li.item != null) cloud_badge_for(cloud_badge, (FileItem)li.item);
                    if (li.item != null && ((FileItem)li.item).directory)
                        icon.set_from_gicon(item_icon((FileItem)li.item));
                    string settings = metadata.state("thumbnail-policy", "Local") + metadata.state("remote-thumbnail-limit", "8");
                    if(settings != thumbnail_settings && li.item != null)
                    {
                        thumbnail_settings = settings;
                        refresh_thumbnail(li, icon, (FileItem)li.item);
                    }
                });
                                       icon.pixel_size = grid ? icon_size : (icon_size > 64 ? 32 : 24);
                                       checkbox.visible = selection_checkboxes;
                                       li.child = box;
                                       if(row_selection is GridSlice){
                                           var slice=(GridSlice)row_selection;
                                           var click=new Gtk.GestureClick();click.button=1;click.propagation_phase=Gtk.PropagationPhase.CAPTURE;
                                           click.pressed.connect(()=>{
                                               uint position=slice.offset+li.position;
                                               if((click.get_current_event_state()&Gdk.ModifierType.SHIFT_MASK)!=0&&grid_anchor!=uint.MAX){
                                                   uint start=uint.min(position,grid_anchor),end=uint.max(position,grid_anchor);
                                                   selection.select_range(start,end-start+1,true);click.set_state(Gtk.EventSequenceState.CLAIMED);
                                               }else grid_anchor=position;
                                           });box.add_controller(click);
                                           var keys=new Gtk.EventControllerKey();keys.propagation_phase=Gtk.PropagationPhase.CAPTURE;
                                           keys.key_pressed.connect((key,code,state)=>{
                                               int current=(int)(slice.offset+li.position),target=current;
                                               if(key==Gdk.Key.Up)target-=(int)grid_rows.columns;
                                               else if(key==Gdk.Key.Down)target+=(int)grid_rows.columns;
                                               else if(key==Gdk.Key.Left)target--;
                                               else if(key==Gdk.Key.Right)target++;
                                               else if(key==Gdk.Key.Home)target=0;
                                               else if(key==Gdk.Key.End)target=(int)selection.get_n_items()-1;
                                               else return false;
                                               target=target.clamp(0,(int)selection.get_n_items()-1);
                                               if((state&Gdk.ModifierType.SHIFT_MASK)!=0){if(grid_anchor==uint.MAX)grid_anchor=(uint)current;uint start=uint.min(grid_anchor,(uint)target);selection.select_range(start,uint.max(grid_anchor,(uint)target)-start+1,true);}
                                               else{grid_anchor=(uint)target;if((state&Gdk.ModifierType.CONTROL_MASK)==0)selection.select_item((uint)target,true);}
                                               focus_grouped((uint)target);return true;
                                           });box.add_controller(keys);
                                       }
                                       var middle = new Gtk.GestureClick();
                                       middle.button = 2;
                                       middle.pressed.connect(() => { var item = li.item as FileItem;
                                                                      if(item != null && item.directory)
                                                                          open_in_tab(item.file);
                                           });
                                       box.add_controller(middle);
                                       var right = new Gtk.GestureClick();
                                       right.button = 3;
                                       right.pressed.connect(() => { var model=row_selection??active_selection; if(li.item != null && !model.is_selected(li.position))
                                                                         model.select_item(li.position, true);
                                           });
                                       box.add_controller(right);
                                       if(!chooser_mode)
                                       {
                                           var drag = new Gtk.DragSource();
                                           drag.actions = Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK;
                                           drag.prepare.connect(() => {
                        var item = li.item as FileItem;
                        if(item == null)
                            return null;
                        var model=row_selection??active_selection;
                        if(!model.is_selected(li.position))
                            model.select_item(li.position, true);
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
                                      var area = (Gtk.Overlay)box.get_first_child();
                                      var image = (Gtk.Image)area.child;
                                      cloud_badge_for((Gtk.Image)area.child.get_next_sibling(), item);
                                      image.set_from_gicon(item_icon(item));
                                      ((Gtk.Label)area.get_next_sibling()).label = visible_name(item);
                                      if(grid)
                                          ((Gtk.Label)area.get_next_sibling().get_next_sibling()).label = caption_key == "None" ? "" : column_text(item, caption_key);
                                      ((Gtk.CheckButton)box.get_last_child()).active = li.selected;
                                      box.tooltip_text = item.file.get_parse_name();
                                      refresh_thumbnail(li, image, item);
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
        void focus_grouped(uint position){
            grouped_grid.scroll_to(grid_rows.row_for(position),Gtk.ListScrollFlags.NONE,null);
            Idle.add(()=>{focus_grouped_cell(grouped_grid,position);return Source.REMOVE;});
        }
        bool focus_grouped_cell(Gtk.Widget widget,uint position){
            if(widget is Gtk.GridView){var slice=widget.get_data<GridSlice>("majoris-grid-slice");if(slice!=null&&position>=slice.offset&&position<slice.offset+slice.get_n_items()){((Gtk.GridView)widget).scroll_to(position-slice.offset,Gtk.ListScrollFlags.FOCUS,null);return true;}}
            for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())if(focus_grouped_cell(child,position))return true;
            return false;
        }
        public void cancel()
        {
            location_bar.visible_child_name = "breadcrumbs";
            column_sort_token.cancel();column_sort_pending=false;
            if (collection_refresh != 0) { Source.remove(collection_refresh); collection_refresh = 0; }
            grouped_grid.model=null;
            if(group_refresh != 0)
            {
                Source.remove(group_refresh);
                group_refresh = 0;
            }
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
            gallery_preview.cancel();
        }
        void refresh_thumbnail(Gtk.ListItem li, Gtk.Image image, FileItem item)
        {
            if(thumbnail_jobs.has_key(li))
                thumbnail_jobs[li].cancel();
            image.set_from_gicon(item_icon(item));
            var token = new Cancellable();
            thumbnail_jobs[li] = token;
            thumbnails.texture.begin(item, token, (service, res) => {
                try {
                    var texture = thumbnails.texture.end(res);
                    if(!token.is_cancelled() && li.item == item && texture != null)
                        image.set_from_paintable(texture);
                }
                catch(Error e) {}
            });
        }
        protected override void dispose()
        {
            if(grid_rows!=null)grid_rows.detach();
            if (cloud_changed != 0) { CloudFiles.get_default().disconnect(cloud_changed); cloud_changed = 0; }
            if (shares_changed != 0) { shares.disconnect(shares_changed); shares_changed = 0; }
            cancel();
            if(completion_popup.get_parent() != null)
                completion_popup.unparent();
            base.dispose();
        }
        public override void unroot()
        {
            if (cloud_changed != 0) { CloudFiles.get_default().disconnect(cloud_changed); cloud_changed = 0; }
            if (shares_changed != 0) { shares.disconnect(shares_changed); shares_changed = 0; }
            base.unroot();
        }
        Icon item_icon(FileItem item)
        {
            var icon = item.info.get_icon() ?? new ThemedIcon("text-x-generic");
            if (item.directory && shares.contains(item.file))
                return new EmblemedIcon(icon, new Emblem(new ThemedIcon("emblem-shared")));
            return icon;
        }
        static void cloud_badge_for(Gtk.Image badge, FileItem item) {
            var cloud = CloudFiles.get_default().peek(item.file);
            badge.visible = cloud != null && cloud.emblem != null;
            if (badge.visible) {
                badge.set_from_icon_name(cloud.emblem); badge.tooltip_text = cloud.state + (cloud.error == "" ? "" : ": " + cloud.error);
                badge.update_property(Gtk.AccessibleProperty.LABEL, cloud.state, -1);
            }
        }
        delegate File? DropFolder();
        async void recover_metadata(Adw.Banner banner)
        {
            if(!(yield Dialogs.confirm(get_root() as Gtk.Window, "Recover Metadata?", "Preserve the existing database as a recovery copy and create a fresh database? Files and folders are unaffected.", "Recover")))
                return;
            try {
                var backup = metadata.recover();
                banner.revealed = false;
                Dialogs.error(get_root() as Gtk.Window, _("A fresh metadata database is ready. The previous database is preserved at ") + backup);
            }
            catch(Error e) {
                error(e.message);
            }
        }
        void add_drop(Gtk.Widget widget, owned DropFolder folder)
        {
            var drop = new Gtk.DropTarget(typeof(Gdk.FileList), Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK);
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
                var modifiers = drop.get_current_event_state();
                bool copy_override = (modifiers & Gdk.ModifierType.CONTROL_MASK) != 0;
                bool move_override = (modifiers & Gdk.ModifierType.SHIFT_MASK) != 0;
                var offered = drop.current_drop == null ? Gdk.DragAction.COPY : drop.current_drop.get_actions();
                if(copy_override && move_override)
                {
                    if((offered & Gdk.DragAction.LINK) == 0)
                        return false;
                    if(!target.is_native())
                        return false;
                    foreach(var file in files)
                        if(!file.is_native())
                            return false;
                    link_requested(files, target);
                }
                else if(copy_override || move_override)
                {
                    if((offered & (move_override ? Gdk.DragAction.MOVE : Gdk.DragAction.COPY)) == 0)
                        return false;
                    transfer_requested(files, target, move_override);
                }
                else default_drop.begin(files, target, offered);
                return files.size > 0;
            });
            widget.add_controller(drop);
        }
        async void default_drop(Gee.ArrayList<File> files, File target, Gdk.DragAction offered)
        {
            bool move = (offered & Gdk.DragAction.MOVE) != 0 && (yield DropPolicy.same_filesystem(files, target));
            if(!move && (offered & Gdk.DragAction.COPY) == 0)
                return;
            if(get_root() != null)
                transfer_requested(files, target, move);
        }
    }
}
