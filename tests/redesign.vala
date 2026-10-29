using MajorisFiles;

// Every fixture lives under an isolated HOME; no installed manager or user data.
int main(string[] args) {
    try {
        string root = DirUtils.make_tmp("majoris-redesign-XXXXXX");
        Environment.set_variable("HOME", root, true);
        Environment.set_variable("XDG_DATA_HOME", root, true);
        Environment.set_variable("XDG_CONFIG_HOME", root, true);
        Environment.set_variable("XDG_CACHE_HOME", root, true);
    } catch (Error e) { error("%s", e.message); }
    Gtk.init(); Adw.init(); Test.init(ref args);
    Gtk.Settings.get_default().gtk_enable_animations = false;
    if(Environment.get_variable("MAJORIS_VISUAL_DARK") == "1")
        Adw.StyleManager.get_default().color_scheme = Adw.ColorScheme.FORCE_DARK;
    Test.add_func("/redesign/native-layout-and-schemes", layout_case);
    Test.add_func("/redesign/collections-search-and-actions", () => {
        var loop = new MainLoop();
        collections_case.begin((obj, res) => { try { collections_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    Test.add_func("/redesign/path-editing-and-history", () => {
        var loop = new MainLoop();
        navigation_case.begin((obj, res) => { try { navigation_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    Test.add_func("/redesign/large-grid-viewport", () => {
        var loop = new MainLoop();
        large_grid_case.begin((obj, res) => { try { large_grid_case.end(res); } catch(Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    return Test.run();
}
async void settle() {
    Timeout.add(400, () => { settle.callback(); return Source.REMOVE; });
    yield;
}
int fixture_number = 0;
FilesWindow fixture(out MetadataStore metadata) throws Error {
    string root = DirUtils.make_tmp("majoris-redesign-case-XXXXXX");
    metadata = new MetadataStore(Path.build_filename(root, "state.db"));
    metadata.set_state("notifications", "false");
    var app = new Adw.Application("com.majoris.files.redesign.case%d".printf(++fixture_number), ApplicationFlags.NON_UNIQUE);
    app.register(null);
    return new FilesWindow(app, metadata, new Places(metadata), new OperationManager(metadata));
}
Gtk.Widget? find_class(Gtk.Widget widget, string name) {
    if (widget.has_css_class(name)) return widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var result = find_class(child, name); if (result != null) return result;
    }
    return null;
}
bool press(Gtk.Widget widget, uint key, Gdk.ModifierType modifiers = 0) {
    var controllers = widget.observe_controllers();
    for (uint i = 0; i < controllers.get_n_items(); i++) {
        var controller = controllers.get_item(i) as Gtk.EventControllerKey;
        if (controller != null && controller.key_pressed(key, 0, modifiers)) return true;
    }
    return false;
}
void layout_case() {
    try {
        MetadataStore metadata;
        var window = fixture(out metadata);
        assert(window.current.location.get_uri() == "recent:///");
        assert(window.current.search_entry.visible);
        assert(find_class(window, "majoris-toolbar") != null);
        assert(find_class(window, "majoris-toolbar-segmented") != null);
        assert(find_class(window, "majoris-document-tabs") != null);
        var places = new Places(metadata);
        assert(places.entries[0].label == "Recent");
        assert(places.entries[1].label == "Favorites");
        foreach (var place in places.entries) assert(place.label != "Home Overview");
        var navigation = (Gtk.Box)find_class(window, "majoris-toolbar");
        assert(navigation is Majoris.Ui.Toolbar && navigation.spacing == 0);
        assert(navigation.margin_start == 0 && navigation.margin_end == 0);
        assert(navigation.margin_top == 0 && navigation.margin_bottom == 0);
        assert(find_class(window, "majoris-location-bar") != null);
        assert(window.current.path.has_css_class("majoris-location-entry"));
        var current = find_class(window, "majoris-location-current");
        assert(current != null && current.has_css_class("majoris-location-crumb"));
        var resources = resources_enumerate_children("/com/majoris/files/theme", ResourceLookupFlags.NONE);
        assert(resources.length == 1 && resources[0] == "files.css");
        var css = resources_lookup_data("/com/majoris/files/theme/files.css", ResourceLookupFlags.NONE);
        assert(!((string)css.get_data()).contains(".files-navigation"));
        window.current.cancel(); window.destroy();
    } catch (Error e) { error("%s", e.message); }
}
async void collections_case() throws Error {
    MetadataStore metadata;
    var window = fixture(out metadata);
    var browser = window.current;
    string root = DirUtils.make_tmp("majoris-collection-XXXXXX");
    var alpha = File.new_for_path(Path.build_filename(root, "alpha.txt"));
    var beta = File.new_for_path(Path.build_filename(root, "beta.txt"));
    FileUtils.set_contents(alpha.get_path(), "alpha"); FileUtils.set_contents(beta.get_path(), "beta");
    metadata.set_favorite(alpha, true); metadata.set_favorite(beta, true);
    metadata.set_tags(alpha,"Sidebar regression");
    metadata.save_search("Sidebar saved search",alpha.get_parent(),new SearchQuery().serialize());
    File? tag_target=null;File? saved_target=null;
    foreach(var place in browser.collection_locations()){
        if(place.file.get_uri().has_prefix("majoris:///tag/"))tag_target=place.file;
        if(place.file.get_uri().has_prefix("majoris:///search/"))saved_target=place.file;
    }
    assert(tag_target!=null&&saved_target!=null);
    browser.navigate(tag_target);yield settle();assert(browser.active_selection.get_n_items()==1);
    browser.navigate(saved_target);yield settle();assert(browser.location.equal(alpha.get_parent()));
    assert(window.lookup_action("bookmark")==null);
    browser.navigate(File.new_for_uri("majoris:///favorites"));
    yield settle();
    assert(browser.active_selection.get_n_items() == 2);
    assert(!browser.accepts_destination);
    foreach (var name in new string[] {"paste", "new-folder", "new-file", "duplicate-items", "extract", "templates"}) assert(!window.command_available(name));
    browser.select_file(alpha);
    assert(window.command_available("copy"));
    window.activate_action("favorite", null);
    yield settle();
    assert(!metadata.favorite(alpha));
    assert(browser.active_selection.get_n_items() == 1);
    browser.search_entry.text = "beta"; browser.search_entry.search_changed(); yield settle();
    assert(browser.active_selection.get_n_items() == 1);
    browser.search_entry.text = "missing"; browser.search_entry.search_changed(); yield settle();
    assert(browser.active_selection.get_n_items() == 0);
    browser.search_entry.text = ""; browser.search_entry.search_changed(); yield settle();
    browser.select_file(beta); window.activate_action("source-folder", null); yield settle();
    assert(browser.location.equal(beta.get_parent()));
    assert(browser.selected().size == 1 && browser.selected()[0].file.equal(beta));
    assert(window.command_available("new-folder"));
    // Exercise native clipboard copy/paste with real filesystem results.
    window.activate_action("copy", null);
    var destination = beta.get_parent().get_child("destination"); destination.make_directory();
    browser.navigate(destination); yield settle();
    window.activate_action("paste", null); yield settle();
    assert(destination.get_child("beta.txt").query_exists());
    Gtk.RecentManager.get_default().add_item(alpha.get_uri());
    browser.navigate(File.new_for_uri("recent:///")); yield settle();
    assert(browser.directory.items.get_n_items() >= 1);
    bool found = false;
    for (uint i = 0; i < browser.directory.items.get_n_items(); i++) {
        var item = (FileItem)browser.directory.items.get_item(i);
        if (item.file.equal(alpha)) { found = true; assert(FileGroups.label(item, "Recent Date", metadata) == "Today"); }
    }
    assert(found && !window.command_available("paste"));
    browser.set_view("Columns"); yield settle(); assert(browser.active_selection.get_n_items() >= 1);
    browser.cancel(); window.destroy();
    var persisted = new MetadataStore(Path.build_filename(root, "persist.db"));
    persisted.set_favorite(beta, true);
    assert(new MetadataStore(Path.build_filename(root, "persist.db")).favorite(beta));
}
async void navigation_case() throws Error {
    MetadataStore metadata; var window = fixture(out metadata); var browser = window.current;
    string root = DirUtils.make_tmp("majoris-navigation-XXXXXX");
    DirUtils.create(Path.build_filename(root, "child"), 0700);
    browser.navigate(File.new_for_path(root)); yield settle();
    assert(press(browser, Gdk.Key.l, Gdk.ModifierType.CONTROL_MASK));
    assert(browser.path.get_parent().visible);
    var bar = find_class(browser, "majoris-location-bar");
    assert(bar.has_css_class("majoris-location-editing"));
    browser.path.text = "child"; browser.path.activate(); yield settle();
    assert(browser.location.equal(File.new_for_path(Path.build_filename(root, "child"))));
    assert(!bar.has_css_class("majoris-location-editing"));
    assert(find_class(browser, "majoris-location-separator") != null);
    assert(press(browser, Gdk.Key.d, Gdk.ModifierType.ALT_MASK));
    browser.path.text = "/unsubmitted";
    assert(press(browser.path, Gdk.Key.Escape));
    assert(browser.path.text == browser.location.get_parse_name());
    assert(!bar.has_css_class("majoris-location-editing"));
    browser.edit_location();
    assert(press(browser, Gdk.Key.Escape));
    assert(!bar.has_css_class("majoris-location-editing"));
    var current = (Gtk.Button)find_class(browser, "majoris-location-current");
    current.clicked(); yield settle();
    assert(browser.location.get_basename() == "child");
    browser.edit_location();
    browser.navigate(File.new_for_path(root)); yield settle();
    assert(!bar.has_css_class("majoris-location-editing"));
    browser.navigate(File.new_for_path(Path.build_filename(root, "child"))); yield settle();
    assert(press(browser, Gdk.Key.Left, Gdk.ModifierType.ALT_MASK)); yield settle();
    assert(browser.location.equal(File.new_for_path(root)));
    assert(press(browser, Gdk.Key.Right, Gdk.ModifierType.ALT_MASK)); yield settle();
    assert(browser.location.get_basename() == "child");
    browser.navigate(File.new_for_uri("majoris:///home")); yield settle();
    assert(browser.location.get_uri() == "recent:///");
    browser.cancel(); window.destroy();
}


// Check rendered labels intersecting the actual viewport, not just model counts.
bool visible_file(Gtk.Widget widget, Gtk.Widget viewport, string name) {
    if(widget is Gtk.Label && ((Gtk.Label)widget).label == name && widget.get_mapped()) {
        Graphene.Rect bounds;
        if(widget.compute_bounds(viewport, out bounds) && bounds.origin.y < viewport.get_height() &&
           bounds.origin.y + bounds.size.height > 0) return true;
    }
    for(var child = widget.get_first_child(); child != null; child = child.get_next_sibling())
        if(visible_file(child, viewport, name)) return true;
    return false;
}
async void large_grid_case() throws Error {
    var folder = File.new_for_path(DirUtils.make_tmp("majoris-large-grid-XXXXXX"));
    for(int i = 0; i < 1500; i++)
        FileUtils.set_contents(folder.get_child("file-%04d.txt".printf(i)).get_path(), "fixture");
    MetadataStore metadata;
    var window = fixture(out metadata);
    window.set_default_size(1100, 800); window.present();
    var browser = window.current;
    browser.navigate(folder);
    for(int attempt = 0; attempt < 100; attempt++) {
        yield settle();
        if(!browser.directory.loading && browser.active_selection.get_n_items() == 1500) break;
    }
    assert(browser.active_selection.get_n_items() == 1500);
    foreach(string mode in new string[]{"None", "Type", "Modified Date"}) {
        browser.set_group(mode);
        foreach(string density in new string[]{"Compact", "Standard", "Large"}) {
            browser.set_density(density);
            foreach(int width in new int[]{600, 1100}) {
                window.set_default_size(width, 800);
                yield settle();
                var stack = browser.file_surface as Gtk.Stack;
                var grids = stack.get_child_by_name("Grid") as Gtk.Stack;
                assert(grids != null);
                var scroll = grids.visible_child as Gtk.ScrolledWindow;
                assert(scroll != null && scroll.child is Gtk.Scrollable);
                var adjustment = scroll.vadjustment;
                assert(adjustment.page_size > 0 && adjustment.upper > adjustment.page_size);
                foreach(uint position in new uint[]{0, 750, 1499, 0}) {
                    var item = (FileItem)browser.active_selection.get_item(position);
                    // Newly realized grouped rows refine GTK's height estimates.
                    // Repeat the request after allocation until the target is visible.
                    for(int attempt = 0; attempt < 5; attempt++) {
                        if(scroll.child is Gtk.GridView)
                            ((Gtk.GridView)scroll.child).scroll_to(position, Gtk.ListScrollFlags.NONE, null);
                        else {
                            var cells = find_class(scroll.child, "majoris-data-grid") as Gtk.GridView;
                            assert(cells != null);
                            ((Gtk.ListView)scroll.child).scroll_to(1 + position / cells.max_columns, Gtk.ListScrollFlags.NONE, null);
                        }
                        yield settle();
                        if(visible_file(scroll.child, scroll, item.file.get_basename())) break;
                    }
                    stdout.printf("Grid %s %s width %d position %u adjustment %.0f/%.0f page %.0f\n", mode, density, width, position, adjustment.value, adjustment.upper, adjustment.page_size);
                    if(!visible_file(scroll.child, scroll, item.file.get_basename())) {
                        dump_visible(scroll.child, scroll);
                    }
                    assert(visible_file(scroll.child, scroll, item.file.get_basename()));
                    if(density == "Standard" && width == 1100) {
                        if(position == 0) { adjustment.value = 0; yield settle(); }
                        grid_capture(window, "%s-%u".printf(mode.replace(" ", "-"), position));
                    }
                }
            }
        }
    }
    browser.set_group("None");
    foreach(string mode in new string[]{"List", "Columns", "Gallery"}) {
        browser.set_view(mode); yield settle();
        var page = ((Gtk.Stack)browser.file_surface).visible_child;
        var view = find_class(page, mode == "List" ? "majoris-data-column" : "majoris-data-list");
        assert(view != null && view.get_mapped());
        if(view is Gtk.ColumnView) ((Gtk.ColumnView)view).scroll_to(1499, null, Gtk.ListScrollFlags.NONE, null);
        else ((Gtk.ListView)view).scroll_to(1499, Gtk.ListScrollFlags.NONE, null);
        yield settle();
        var viewport = view.get_ancestor(typeof(Gtk.ScrolledWindow));
        assert(viewport != null && visible_file(view, viewport, "file-1499.txt"));
    }
    browser.cancel(); window.destroy();
    var directories = File.new_for_path(DirUtils.make_tmp("majoris-large-folders-XXXXXX"));
    for(int i = 0; i < 1500; i++) directories.get_child("file-%04d.txt".printf(i)).make_directory();
    foreach(string mode in new string[]{"open", "multiple", "save", "folder", "savefiles"}) {
        var values = new VariantBuilder(VariantType.VARDICT);
        if(mode == "multiple") values.add("{sv}", "multiple", new Variant.boolean(true));
        if(mode == "folder") values.add("{sv}", "directory", new Variant.boolean(true));
        if(mode == "savefiles") {
            var names = new VariantBuilder(new VariantType("aay"));
            names.add_value(new Variant.bytestring("output.txt"));
            values.add("{sv}", "files", names.end());
        }
        var options = new ChooserOptions(mode == "save" || mode == "savefiles", values.end(), mode == "savefiles");
        options.initial = mode == "folder" || mode == "savefiles" ? directories : folder;
        var chooser = new ChooserWindow(options, metadata, new Places(metadata));
        chooser.present();
        for(int attempt = 0; attempt < 50; attempt++) {
            yield settle();
            if(!chooser.browser.directory.loading && chooser.browser.active_selection.get_n_items() == 1500) break;
        }
        chooser.browser.set_view("Grid"); chooser.browser.set_group("None"); yield settle();
        var grids = ((Gtk.Stack)chooser.browser.file_surface).get_child_by_name("Grid") as Gtk.Stack;
        var scroll = grids.visible_child as Gtk.ScrolledWindow;
        ((Gtk.GridView)scroll.child).scroll_to(1499, Gtk.ListScrollFlags.NONE, null);
        yield settle();
        assert(visible_file(scroll.child, scroll, "file-1499.txt"));
        chooser.browser.active_selection.select_item(1499, true);
        assert(chooser.browser.selected().size == 1);
        chooser.browser.cancel(); chooser.destroy();
    }
    for(int i = 0; i < 1500; i++) folder.get_child("file-%04d.txt".printf(i)).delete();
    folder.delete();
    for(int i = 0; i < 1500; i++) directories.get_child("file-%04d.txt".printf(i)).delete();
    directories.delete();
}

void dump_visible(Gtk.Widget widget, Gtk.Widget viewport) {
    Graphene.Rect bounds = Graphene.Rect();
    if(widget.get_mapped() && widget.compute_bounds(viewport, out bounds) && bounds.origin.y < viewport.get_height() && bounds.origin.y + bounds.size.height > 0) {
        if(widget is Gtk.Label) stdout.printf("VISIBLE %s y %.0f h %.0f\n", ((Gtk.Label)widget).label, bounds.origin.y, bounds.size.height);
        if(widget is Gtk.GridView) stdout.printf("CELLS columns %u width %d height %d\n", ((Gtk.GridView)widget).max_columns, widget.get_width(), widget.get_height());
    }
    for(var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) dump_visible(child, viewport);
}

void grid_capture(Gtk.Window window, string name) throws Error {
    string? output = Environment.get_variable("MAJORIS_GRID_EVIDENCE");
    if(output == null) return;
    DirUtils.create_with_parents(output, 0755);
    var paintable = new Gtk.WidgetPaintable(window);
    var snapshot = new Gtk.Snapshot();
    paintable.snapshot(snapshot, window.get_width(), window.get_height());
    var node = snapshot.to_node(); assert(node != null);
    var renderer = Gsk.Renderer.for_surface(window.get_surface());
    var texture = renderer.render_texture(node, null);
    assert(texture.save_to_png(Path.build_filename(output, name + ".png")));
    renderer.unrealize();
}
