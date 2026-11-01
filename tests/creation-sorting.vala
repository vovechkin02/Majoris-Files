using MajorisFiles;
[DBus (name = "com.majoris.Files.Extension1")]
interface SortFixtureAPI : Object {
    public abstract uint get_version() throws Error;
    public abstract async HashTable<string, string> get_file_info(string uri) throws Error;
}
class SortFixtureService : Object, SortFixtureAPI {
    public uint get_version() throws Error { return 1; }
    public async HashTable<string, string> get_file_info(string uri) throws Error {
        var info = yield File.new_for_uri(uri).query_info_async("standard::size", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
        var fields = new HashTable<string, string>(str_hash, str_equal);
        fields.insert("bytes", info.get_size().to_string()); return fields;
    }
}
FilenameCell? creation_editor(Gtk.Widget widget) {
    if (widget is FilenameCell && ((FilenameCell)widget).transaction != null && widget.get_mapped()) return (FilenameCell)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = creation_editor(child); if (found != null) return found;
    }
    return null;
}
bool editor_focused(Gtk.Window window, FilenameCell? cell) {
    var focus = window.get_focus();
    return cell != null && focus != null && (focus == cell.entry || focus.is_ancestor(cell.entry));
}
Gtk.Widget? find_tooltip(Gtk.Widget widget, string tooltip) {
    if (widget.tooltip_text == tooltip) return widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = find_tooltip(child, tooltip); if (found != null) return found;
    }
    return null;
}
Gtk.ColumnView? detail_view(Gtk.Widget widget) {
    if (widget is Gtk.ColumnView) return (Gtk.ColumnView)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = detail_view(child); if (found != null) return found;
    }
    return null;
}
Gtk.Widget? header_label(Gtk.Widget widget, string title) {
    if (widget is Gtk.Label && ((Gtk.Label)widget).label == title && widget.get_mapped()) return widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = header_label(child, title); if (found != null) return found;
    }
    return null;
}
async void click_header(FilesWindow window, string title) throws Error {
    Gtk.Widget? label = null;
    int64 deadline = get_monotonic_time() + 30 * 1000000L;
    while (get_monotonic_time() < deadline) {
        label = header_label(detail_view(window.current), title);
        if (label != null && label.get_width() > 0 && label.get_height() > 0) break;
        yield pause_layout();
    }
    assert(label != null && label.get_width() > 0 && label.get_height() > 0);
    yield click_widget(window, label);
}
async void click_widget(FilesWindow window, Gtk.Widget label) throws Error {
    Graphene.Rect bounds; assert(label.compute_bounds(window, out bounds));
    string description = "column"; if (label is Gtk.Label) description = ((Gtk.Label)label).label;
    Test.message("pointer %s at %.0f,%.0f window %dx%d", description, bounds.origin.x + bounds.size.width / 2, bounds.origin.y + bounds.size.height / 2, window.get_width(), window.get_height());
    window.title = "Majoris Creation Sorting";
    var search = new Subprocess.newv({"xdotool", "search", "--name", "^Majoris Creation Sorting$"}, SubprocessFlags.STDOUT_PIPE);
    string? ids; yield search.communicate_utf8_async(null, null, out ids, null);
    var click = new Subprocess.newv({"xdotool", "windowfocus", "--sync", ids.strip(), "mousemove", "--window", ids.strip(),
        ((int)(bounds.origin.x + bounds.size.width / 2)).to_string(), ((int)(bounds.origin.y + bounds.size.height / 2)).to_string(), "click", "1"}, SubprocessFlags.NONE);
    yield click.wait_check_async(null); yield pause_layout();
}
Gtk.ListView? empty_column(Gtk.Widget widget) {
    if (widget is Gtk.ListView && widget.get_mapped() && ((Gtk.ListView)widget).model.get_n_items() == 0) return (Gtk.ListView)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = empty_column(child); if (found != null) return found;
    }
    return null;
}
uint file_position(Gtk.SelectionModel model, File file) {
    for (uint i = 0; i < model.get_n_items(); i++) if (((FileItem)model.get_item(i)).file.equal(file)) return i;
    return uint.MAX;
}
Adw.SwitchRow? folders_switch(Gtk.Widget widget) {
    if (widget is Adw.SwitchRow && ((Adw.SwitchRow)widget).title == "Folders First") return (Adw.SwitchRow)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = folders_switch(child); if (found != null) return found;
    }
    return null;
}
async void evidence(Gtk.Window window, string name) throws Error {
    var output = Environment.get_variable("MAJORIS_CREATION_EVIDENCE");
    if (output != null && !name.has_prefix("grouped-grid")) { DirUtils.create_with_parents(output, 0755); Gsk.RenderNode? node = null;
        for (int attempt = 0; attempt < 6 && node == null; attempt++) {
            yield pause_layout();
            var paintable = new Gtk.WidgetPaintable(window); var snapshot = new Gtk.Snapshot();
            paintable.snapshot(snapshot, window.get_width(), window.get_height()); node = snapshot.to_node();
        }
        assert(node != null);
        var renderer = Gsk.Renderer.for_surface(window.get_surface());
        var texture = renderer.render_texture(node, null);
        assert(texture.save_to_png(Path.build_filename(output, name + ".png"))); renderer.unrealize(); }
}
async void run_creation_sorting() throws Error {
    var folder = File.new_for_path(DirUtils.make_tmp("majoris-creation-XXXXXX"));
    for (int i = 0; i < 1500; i++) FileUtils.set_contents(folder.get_child("item-%04d.txt".printf(i)).get_path(), "fixture");
    var file_two = folder.get_child("File 2"), file_ten = folder.get_child("File 10");
    var unicode_file = folder.get_child("年次 報告.txt"), missing_file = folder.get_child("missing metadata");
    FileUtils.set_contents(file_two.get_path(), string.nfill(900, 'a'));
    FileUtils.set_contents(file_ten.get_path(), string.nfill(2000, 'b'));
    FileUtils.set_contents(unicode_file.get_path(), "Unicode"); FileUtils.set_contents(missing_file.get_path(), "missing");
    var sources = folder.get_child("sources"); sources.make_directory();
    var alpha = sources.get_child("alpha"), beta = sources.get_child("beta"); alpha.make_directory(); beta.make_directory();
    var same_alpha = alpha.get_child("same.txt"), same_beta = beta.get_child("same.txt");
    FileUtils.set_contents(same_alpha.get_path(), "same"); FileUtils.set_contents(same_beta.get_path(), "same");
    var metadata = new MetadataStore(Path.build_filename(DirUtils.make_tmp("majoris-creation-state-XXXXXX"), "state.db"));
    metadata.set_state("notifications", "false");
    var operations = new OperationManager(metadata);
    var app = new Adw.Application("com.majoris.files.creationcheck", ApplicationFlags.NON_UNIQUE); app.register(null);
    var window = new FilesWindow(app, metadata, new Places(metadata), operations, folder);
    window.set_default_size(1100, 820); window.present(); yield pause_layout();
    var browser = window.current;
    while (browser.directory.loading) yield pause_layout();
    foreach (var mode in new string[] {"Grid", "List", "Columns", "Gallery", "Grouped Grid"}) {
        browser.set_group(mode == "Grouped Grid" ? "Type" : "None");
        browser.set_view(mode == "Grouped Grid" ? "Grid" : mode); yield pause_layout();
        foreach (bool is_folder in new bool[] {true, false}) {
            var base_name = is_folder ? "New Folder" : "New File";
            var command = (SimpleAction)window.lookup_action(is_folder ? "new-folder" : "new-file");
            int64 ready_deadline = get_monotonic_time() + 30 * 1000000L;
            while (!command.enabled && get_monotonic_time() < ready_deadline) yield pause_layout();
            Test.message("ready mode=%s folder=%s enabled=%s loading=%s writable=%s destination=%s current=%s location=%s", mode, is_folder.to_string(), command.enabled.to_string(), browser.directory.loading.to_string(), browser.directory.writable.to_string(), browser.accepts_destination.to_string(), (window.current == browser).to_string(), browser.location.get_uri());
            assert(command.enabled);
            command.activate(null);
            yield pause_layout();
            int64 deadline = get_monotonic_time() + 30 * 1000000L;
            while (!editor_focused(window, creation_editor(browser)) && get_monotonic_time() < deadline) yield pause_layout();
            var cell = creation_editor(browser);
            Test.message("creation mode=%s folder=%s epoch=%u state=%s selected=%d cell=%s focus=%s writable=%s", mode, is_folder.to_string(), browser.creation_epoch, (browser.inline_rename != null).to_string(), browser.selected().size, (cell != null).to_string(), (editor_focused(window, cell)).to_string(), browser.accepts_destination.to_string());
            assert(editor_focused(window, cell));
            assert(window.visible_dialog == null && browser.selected().size == 1);
            var file = browser.selected()[0].file;
            assert(cell.item.file.equal(file) && file.get_basename().has_prefix(base_name));
            int start, end; assert(cell.entry.get_selection_bounds(out start, out end));
            assert(start == 0 && end == file.get_basename().char_count());
            yield evidence(window, mode.down().replace(" ", "-") + (is_folder ? "-folder" : "-file"));
            browser.cancel_inline_rename(); assert(file.query_exists());
        }
    }
    var nested = folder.get_child("nested-destination"); nested.make_directory();
    browser.set_group("None"); browser.navigate(folder);
    while (browser.directory.loading) yield pause_layout();
    browser.set_view("Columns"); browser.select_file(nested); yield pause_layout();
    int64 nested_deadline = get_monotonic_time() + 30 * 1000000L;
    while (empty_column(browser) == null && get_monotonic_time() < nested_deadline) yield pause_layout();
    var child_list = empty_column(browser); assert(child_list != null);
    yield click_widget(window, child_list); assert(browser.location.equal(nested));
    window.lookup_action("new-file").activate(null); yield pause_layout();
    while (!editor_focused(window, creation_editor(browser)) && get_monotonic_time() < nested_deadline) yield pause_layout();
    assert(editor_focused(window, creation_editor(browser)));
    var nested_file = nested.get_child("New File");
    assert(nested_file.query_exists() && browser.inline_rename.item.file.equal(nested_file));
    yield evidence(window, "columns-nested-file"); browser.cancel_inline_rename();
    var small = nested.get_child("small.bin"); var large = nested.get_child("large.bin");
    FileUtils.set_contents(small.get_path(), "12"); FileUtils.set_contents(large.get_path(), "1234567890123456789012345678901234567890");
    while (child_list.model.get_n_items() != 3 && get_monotonic_time() < nested_deadline) yield pause_layout();
    browser.set_sort("Size", false); yield pause_layout();
    assert(((FileItem)child_list.model.get_item(0)).file.equal(large));
    assert(((FileItem)child_list.model.get_item(2)).file.equal(nested_file));
    assert(browser.selected().size == 1 && browser.selected()[0].file.equal(nested_file));
    browser.set_group("None"); browser.set_view("List"); yield pause_layout();
    // Controlled backend metadata: exercise unknown sizes/timestamps without a
    // monitor reload replacing the fixture while native headers are clicked.
    while (browser.directory.loading) yield pause_layout();
    browser.directory.cancel();
    for (uint i = 0; i < browser.selection.get_n_items(); i++) {
        var item = (FileItem)browser.selection.get_item(i);
        if (item.file.equal(file_two) || item.file.equal(file_ten)) foreach (var key in new string[] {"time::modified", "time::created", "time::access"}) {
            item.info.set_attribute_uint64(key, item.file.equal(file_two) ? 1000 : 2000);
            item.info.set_attribute_uint32(key + "-usec", 123);
        }
        if (item.file.equal(missing_file)) foreach (var key in new string[] {"standard::size", "time::modified", "time::created", "time::access", "time::modified-usec", "time::created-usec", "time::access-usec"}) item.info.remove_attribute(key);
    }
    // Search-style rows with equal names but distinct source URIs.
    browser.directory.items.append(new FileItem(same_alpha, yield same_alpha.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE)));
    browser.directory.items.append(new FileItem(same_beta, yield same_beta.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE)));
    browser.register_column(new CreationColumn());
    foreach (var key in new string[] {"Name", "Size", "Type", "Modified", "Created", "Accessed", "Byte Count"}) {
        var detail = detail_view(browser);
        for (uint i = 0; i < detail.columns.get_n_items(); i++) {
            var column = (Gtk.ColumnViewColumn)detail.columns.get_item(i);
            bool standard = key in new string[] {"Name", "Size", "Type", "Modified"};
            column.visible = column.title == "Name" || column.title == key ||
                (standard && column.title in new string[] {"Size", "Type", "Modified"});
        }
        browser.set_sort(key == "Name" ? "Size" : "Name", true); yield pause_layout();
        var chosen = folder.get_child("item-0750.txt"); browser.select_file(chosen);
        yield click_header(window, key); assert(browser.sort_key == key);
        bool direction = browser.ascending;
        if (key == "Name" || key == "Size" || key == "Modified" || key == "Created" || key == "Accessed" || key == "Byte Count") {
            assert(file_position(browser.selection, file_two) < file_position(browser.selection, file_ten));
            if (key != "Name") assert(file_position(browser.selection, missing_file) < file_position(browser.selection, file_two));
        }
        assert(((FileItem)browser.selection.get_item(0)).directory);
        if (key == "Name") assert(file_position(browser.selection, same_alpha) < file_position(browser.selection, same_beta));
        assert(browser.selected().size == 1 && browser.selected()[0].file.equal(chosen));
        yield click_header(window, key); assert(browser.sort_key == key && browser.ascending != direction);
        if (key == "Name" || key == "Size" || key == "Modified" || key == "Created" || key == "Accessed" || key == "Byte Count")
            assert(file_position(browser.selection, file_two) > file_position(browser.selection, file_ten));
        assert(((FileItem)browser.selection.get_item(0)).directory);
        if (key == "Name") assert(file_position(browser.selection, same_alpha) > file_position(browser.selection, same_beta));
        var native = (Gtk.ColumnViewSorter)detail_view(browser).sorter;
        assert(native.get_primary_sort_column().title == key && native.get_n_sort_columns() == 1);
        assert(browser.activate_action_variant("context.descending", null));
        assert(browser.sort_key == key && browser.ascending == direction);
        assert(browser.activate_action_variant("context.sort", new Variant.string(key)));
        assert(browser.sort_key == key && browser.ascending);
        assert(native.get_n_sort_columns() == 1 && native.get_primary_sort_column().title == key && native.get_primary_sort_order() == Gtk.SortType.ASCENDING);
        bool listed = false;
        var choices = browser.sort_menu();
        for (int i = 0; i < choices.get_n_items(); i++) {
            var target = choices.get_item_attribute_value(i, "target", VariantType.STRING);
            if (target != null && target.get_string() == key) listed = true;
        }
        assert(listed);
        yield evidence(window, "sort-" + key.down());
    }
    browser.selection.select_item(file_position(browser.selection, unicode_file), false);
    var selected_before = browser.selected(); assert(selected_before.size == 2);
    yield click_header(window, "Name"); assert(browser.selected().size == 2);
    browser.show_view_settings(); yield pause_layout();
    var folders = folders_switch(window.visible_dialog); assert(folders != null && folders.active);
    folders.active = false; yield pause_layout();
    assert(browser.selected().size == 2); window.visible_dialog.close(); yield pause_layout();
    browser.set_sort("Name", true);
    assert(((FileItem)browser.selection.get_item(0)).file.equal(file_two));
    browser.show_view_settings(); yield pause_layout(); folders = folders_switch(window.visible_dialog);
    folders.active = true; window.visible_dialog.close(); yield pause_layout();
    assert(((FileItem)browser.selection.get_item(0)).directory && browser.selected().size == 2);
    browser.set_group("Type"); yield pause_layout(); yield click_header(window, "Name");
    assert(detail_view(browser).header_factory != null && browser.selected().size == 2);
    browser.set_group("None"); yield pause_layout(); assert(detail_view(browser).header_factory == null);
    var non_sortable = new Gtk.ColumnViewColumn("Non-sortable", new Gtk.SignalListItemFactory());
    detail_view(browser).append_column(non_sortable); yield pause_layout();
    string previous_key = browser.sort_key; bool previous_direction = browser.ascending;
    yield click_header(window, "Non-sortable");
    assert(browser.sort_key == previous_key && browser.ascending == previous_direction);
    detail_view(browser).remove_column(non_sortable);
    var bus = yield Bus.get(BusType.SESSION);
    var service = new SortFixtureService();
    uint registration = bus.register_object<SortFixtureAPI>("/com/majoris/SortFixture", service);
    bool service_ready = false;
    uint service_owner = Bus.own_name_on_connection(bus, "com.majoris.Files.SortFixture", BusNameOwnerFlags.NONE, () => service_ready = true);
    while (!service_ready) yield pause_layout();
    var async_manifest = Path.build_filename(DirUtils.make_tmp("majoris-async-sort-XXXXXX"), "sort.extension");
    FileUtils.set_contents(async_manifest, "[Extension]\nId=com.majoris.Files.SortFixture\nName=Sort Fixture\nVersion=1\nBusName=com.majoris.Files.SortFixture\nObjectPath=/com/majoris/SortFixture\nCapabilities=columns;\n");
    var extension = new ExternalExtension(async_manifest, true, metadata);
    browser.register_column(new ExternalColumn(extension, "bytes", "Async Bytes"));
    for (uint i = 0; i < detail_view(browser).columns.get_n_items(); i++) {
        var column = (Gtk.ColumnViewColumn)detail_view(browser).columns.get_item(i);
        column.visible = column.title == "Name" || column.title == "Async Bytes";
    }
    browser.set_sort("Name", true); yield pause_layout();
    uint heartbeats = 0; uint heartbeat = Timeout.add(1, () => { heartbeats++; return Source.CONTINUE; });
    yield click_header(window, "Async Bytes");
    int64 async_deadline = get_monotonic_time() + 30 * 1000000L;
    while (browser.sort_key != "Async Bytes" && get_monotonic_time() < async_deadline) yield pause_layout();
    Source.remove(heartbeat);
    assert(browser.sort_key == "Async Bytes" && heartbeats > 0 && browser.selected().size == 2);
    assert(file_position(browser.selection, file_two) < file_position(browser.selection, file_ten));
    yield click_header(window, "Async Bytes");
    while (browser.ascending && get_monotonic_time() < async_deadline) yield pause_layout();
    assert(!browser.ascending && file_position(browser.selection, file_two) > file_position(browser.selection, file_ten));
    browser.remove_extension_columns(new Gee.HashSet<string>());
    assert(browser.sort_key == "Name" && !browser.has_column("Async Bytes"));
    assert(((Gtk.ColumnViewSorter)detail_view(browser).sorter).get_primary_sort_column().title == "Name");
    Bus.unown_name(service_owner); bus.unregister_object(registration);
    var manifest = Path.build_filename(DirUtils.make_tmp("majoris-sort-extension-XXXXXX"), "unavailable.extension");
    FileUtils.set_contents(manifest, "[Extension]\nId=com.majoris.UnavailableSort\nName=Unavailable Sort\nVersion=1\nBusName=com.majoris.UnavailableSort\nObjectPath=/com/majoris/UnavailableSort\nCapabilities=columns;\n");
    var unavailable = new ExternalExtension(manifest, false, metadata);
    browser.register_column(new ExternalColumn(unavailable, "count", "Unavailable"));
    var detail = detail_view(browser);
    for (uint i = 0; i < detail.columns.get_n_items(); i++) {
        var column = (Gtk.ColumnViewColumn)detail.columns.get_item(i);
        column.visible = column.title == "Name" || column.title == "Unavailable";
    }
    bool sort_error = false;
    ulong error_handler = browser.error.connect(() => sort_error = true);
    browser.set_sort("Size", true); yield pause_layout();
    yield click_header(window, "Unavailable");
    int64 failure_deadline = get_monotonic_time() + 30 * 1000000L;
    while (!sort_error && get_monotonic_time() < failure_deadline) yield pause_layout();
    Test.message("unavailable enabled=%s error=%s key=%s", unavailable.enabled.to_string(), sort_error.to_string(), browser.sort_key);
    assert(sort_error && browser.sort_key == "Size");
    assert(((Gtk.ColumnViewSorter)detail.sorter).get_primary_sort_column().title == "Size");
    browser.disconnect(error_handler);
    if (window.visible_dialog != null) { window.visible_dialog.close(); yield pause_layout(); }
    browser.remove_extension_columns(new Gee.HashSet<string>());
    assert(!browser.has_column("Unavailable") && !browser.has_column("Async Bytes"));
    browser.set_sort("Size", true); window.lookup_action("descending").activate(null);
    assert(browser.sort_key == "Size" && !browser.ascending);
    assert(((Gtk.ColumnViewSorter)detail_view(browser).sorter).get_primary_sort_order() == Gtk.SortType.DESCENDING);
    browser.navigate(folder.get_child("New Folder")); yield pause_layout();
    while (browser.directory.loading) yield pause_layout(); browser.set_view("List"); yield pause_layout();
    yield click_header(window, "Name"); yield click_header(window, "Size");
    assert(browser.selection.get_n_items() == 0 && browser.sort_key == "Size");
    yield evidence(window, "sort-empty");
    browser.navigate(folder); yield pause_layout();
    assert(browser.sort_key == "Size" && !browser.ascending);
    window.new_tab(folder); yield pause_layout(); window.current.set_sort("Modified", true);
    window.tabs.selected_page = window.tabs.get_nth_page(0); yield pause_layout();
    assert(window.current == browser && browser.sort_key == "Size" && !browser.ascending);
    assert(((Gtk.ColumnViewSorter)detail_view(browser).sorter).get_primary_sort_order() == Gtk.SortType.DESCENDING);
    var isolated = folder.get_child("navigation-target"); isolated.make_directory();
    browser.set_view("List");
    var race_context = browser.active_selection; uint race_epoch = browser.start_creation();
    var race_file = yield operations.create_default(folder, false);
    yield browser.directory.reconcile_created(race_file);
    yield browser.edit_created(race_file, folder, race_epoch, race_context); yield pause_layout();
    assert(browser.inline_rename != null && browser.inline_rename.item.file.equal(race_file));
    while (browser.directory.loading) yield pause_layout();
    uint matching = 0;
    for (uint i = 0; i < browser.directory.items.get_n_items(); i++)
        if (((FileItem)browser.directory.items.get_item(i)).file.equal(race_file)) matching++;
    assert(matching == 1); browser.cancel_inline_rename();
    browser.directory.cancel(); race_context = browser.active_selection; race_epoch = browser.start_creation();
    race_file = yield operations.create_default(folder, false);
    yield browser.edit_created(race_file, folder, race_epoch, race_context); yield pause_layout();
    assert(browser.inline_rename != null && browser.inline_rename.item.file.equal(race_file));
    browser.cancel_inline_rename();
    // Callback after navigation or tab change must not activate an editor.
    var context = browser.active_selection; uint epoch = browser.start_creation();
    var pending = yield operations.create_default(folder, false);
    browser.navigate(isolated); yield pause_layout();
    yield browser.edit_created(pending, folder, epoch, context); assert(browser.inline_rename == null);
    browser.navigate(folder); yield pause_layout();
    context = browser.active_selection; epoch = browser.start_creation();
    pending = yield operations.create_default(folder, true);
    window.tabs.selected_page = window.tabs.get_nth_page(1);
    window.tabs.selected_page = window.tabs.get_nth_page(0);
    yield browser.edit_created(pending, folder, epoch, context); assert(browser.inline_rename == null);
    window.destroy();
    for (int mode = 0; mode < 4; mode++) {
        var options = new ChooserOptions(mode == 2, new VariantBuilder(VariantType.VARDICT).end()); options.initial = folder;
        options.save = mode == 2; options.multiple = mode == 1; options.directory = mode == 3;
        var chooser = new ChooserWindow(options, metadata, new Places(metadata)); chooser.present(); yield pause_layout();
        while (chooser.browser.directory.loading) yield pause_layout();
        bool responded = false;
        chooser.completed.connect(() => responded = true);
        var create = find_tooltip(chooser, "New Folder") as Gtk.Button;
        assert(create != null && create.sensitive); create.clicked(); yield pause_layout();
        int64 deadline = get_monotonic_time() + 30 * 1000000L;
        while (!editor_focused(chooser, creation_editor(chooser.browser)) && get_monotonic_time() < deadline) yield pause_layout();
        var cell = creation_editor(chooser.browser); assert(editor_focused(chooser, cell));
        cell.entry.text = "chooser-created-%d".printf(mode); cell.entry.activate(); yield pause_layout();
        while (chooser.browser.inline_rename != null && get_monotonic_time() < deadline) yield pause_layout();
        assert(!responded && chooser.browser.inline_rename == null);
        assert(folder.get_child("chooser-created-%d".printf(mode)).query_exists());
        chooser.browser.set_view("List"); chooser.browser.set_sort("Size", false);
        assert(((Gtk.ColumnViewSorter)detail_view(chooser.browser).sorter).get_primary_sort_order() == Gtk.SortType.DESCENDING);
        yield evidence(chooser, "chooser-%d".printf(mode)); chooser.cancel_request();
    }
}
async void check_creation_history() throws Error {
    var metadata = new MetadataStore(Path.build_filename(DirUtils.make_tmp("majoris-creation-journal-XXXXXX"), "state.db"));
    var operations = new OperationManager(metadata);
    // Collision-safe filesystem operations and persisted history.
    var history_root = File.new_for_path(Environment.get_user_cache_dir());
    DirUtils.create_with_parents(history_root.get_path(), 0700);
    var isolated = history_root.get_child("majoris-created-history-" + Uuid.string_random()); isolated.make_directory();
    var created = yield operations.create_default(isolated, false); assert(created.get_basename() == "New File");
    var second = yield operations.create_default(isolated, false); assert(second.get_basename() == "New File (2)");
    assert((yield second.query_info_async("standard::size", FileQueryInfoFlags.NONE)).get_size() == 0);
    var renamed = yield operations.rename(second, "Notes.txt"); assert(renamed.query_exists());
    operations = new OperationManager(metadata); // Restore CREATE_FILE and rename from the saved v3 journal.
    yield operations.undo(); assert(second.query_exists());
    yield operations.undo(); assert(!second.query_exists());
    yield operations.redo(); assert(second.query_exists());
    yield operations.redo(); assert(renamed.query_exists());
    yield operations.undo();
    FileUtils.set_contents(second.get_path(), "valuable data");
    bool refused = false;
    try { yield operations.undo(); } catch (Error e) { refused = true; }
    assert(refused && second.query_exists());
    FileUtils.set_contents(isolated.get_child("New Folder").get_path(), "existing file");
    var numbered_folder = yield operations.create_default(isolated, true);
    assert(numbered_folder.get_basename() == "New Folder (2)");
    FileUtils.set_contents(numbered_folder.get_child("valuable.txt").get_path(), "valuable data");
    refused = false;
    try { yield operations.undo(); } catch (Error e) { refused = true; }
    assert(refused && numbered_folder.get_child("valuable.txt").query_exists());
    var scratch = yield operations.new_folder(isolated, "Scratch");
    var projects = yield operations.rename(scratch, "Projects");
    var work = yield operations.rename(projects, "Work");
    yield operations.undo(); yield operations.undo(); yield operations.undo();
    assert(!scratch.query_exists() && !work.query_exists());
    yield operations.redo(); yield operations.redo(); yield operations.redo();
    assert(work.query_exists());
    var conflict = yield operations.new_file(isolated, "redo-conflict");
    yield operations.undo(); FileUtils.set_contents(conflict.get_path(), "external data");
    refused = false;
    try { yield operations.redo(); } catch (Error e) { refused = true; }
    assert(refused && conflict.query_exists());
    bool invalid = false;
    try { yield operations.new_file(isolated, "../invalid"); } catch (MajorisFiles.FileError.INVALID e) { invalid = true; }
    assert(invalid);
    var replaced = yield operations.new_file(isolated, "replacement-guard");
    yield replaced.move_async(isolated.get_child("original-preserved"), FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    FileUtils.set_contents(replaced.get_path(), "replacement data");
    refused = false;
    try { yield operations.undo(); } catch (Error e) { refused = true; }
    assert(refused && replaced.query_exists());
}
int main(string[] args) {
    Test.init(ref args); Adw.init();
    if (Environment.get_variable("MAJORIS_VISUAL_DARK") == "1") Adw.StyleManager.get_default().color_scheme = Adw.ColorScheme.FORCE_DARK;
    Test.add_func("/creation-sorting/history", () => {
        var loop = new MainLoop();
        check_creation_history.begin((obj, result) => { try { check_creation_history.end(result); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    Test.add_func("/creation-sorting/integration", () => {
        var loop = new MainLoop();
        run_creation_sorting.begin((obj, result) => { try { run_creation_sorting.end(result); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    return Test.run();
}

class CreationColumn : Object, ColumnProvider {
    public string title { owned get { return "Byte Count"; } }
    public string text(FileItem item, MetadataStore metadata) { return item.bytes.to_string(); }
    public int compare(FileItem a, FileItem b, MetadataStore metadata) { return a.bytes < b.bytes ? -1 : a.bytes == b.bytes ? 0 : 1; }
}
