using MajorisFiles;
string evidence;
Gtk.Widget? find_type(Gtk.Widget widget, Type type) {
    if (widget.get_type().is_a(type) && widget.get_mapped()) return widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = find_type(c, type); if (found != null) return found; } return null;
}
Gtk.Widget? labelled(Gtk.Widget widget, string label) {
    if (widget is Gtk.Button && ((Gtk.Button)widget).label == label) return widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = labelled(c, label); if (found != null) return found; } return null;
}
TagManageRow? tag_row(TagsDialog dialog, int64 id) {
    for (var row = dialog.list.get_first_child(); row != null; row = row.get_next_sibling()) if (row is TagManageRow && ((TagManageRow)row).tag != null && ((TagManageRow)row).tag.id == id) return (TagManageRow)row;
    return null;
}
Gtk.ListBoxRow? sidebar_tag(Gtk.Widget widget, int64 id) {
    var place = widget.get_data<Place>("majoris-place"); if (widget is Gtk.ListBoxRow && place != null && place.tag != null && place.tag.id == id) return (Gtk.ListBoxRow)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = sidebar_tag(c, id); if (found != null) return found; } return null;
}
Gtk.Button? tooltip_button(Gtk.Widget widget, string text) {
    if (widget is Gtk.Button && widget.tooltip_text == text) return (Gtk.Button)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = tooltip_button(c, text); if (found != null) return found; } return null;
}
async void shot(string name) throws Error {
    if (evidence == "") return;
    yield pause_layout(); var path = Path.build_filename(evidence, name);
    var capture = new Subprocess.newv({"import", "-window", "root", path + ".png"}, SubprocessFlags.NONE); yield capture.wait_check_async(null);
}
async void key(string value) throws Error { var focus = new Subprocess.newv({"xdotool", "search", "--name", "^Files$", "windowfocus", "--sync"}, SubprocessFlags.STDOUT_SILENCE); yield focus.wait_check_async(null); var process = new Subprocess.newv({"xdotool", "key", "--clearmodifiers", value}, SubprocessFlags.NONE); yield process.wait_check_async(null); yield pause_layout(); }
async void scenarios() throws Error {
    var root = File.new_for_path(DirUtils.make_tmp("majoris-tag-ui-XXXXXX")); var folder = root.get_child("Folder"); folder.make_directory();
    var a = root.get_child("a.txt"); var b = folder.get_child("b.txt"); FileUtils.set_contents(a.get_path(), "one"); FileUtils.set_contents(b.get_path(), "two");
    var metadata = new MetadataStore(root.get_child("state.db").get_path()); assert(metadata.available); metadata.set_state("notifications", "false");
    var places = new Places(metadata); var operations = new OperationManager(metadata);
    var app = new Adw.Application("com.majoris.files.tagcheck", ApplicationFlags.NON_UNIQUE); app.register(null);
    var window = new FilesWindow(app, metadata, places, operations, root); window.present(); yield pause_layout();
    var focus = new Subprocess.newv({"xdotool", "search", "--name", "^Files$", "windowfocus", "--sync"}, SubprocessFlags.STDOUT_SILENCE); yield focus.wait_check_async(null);
    var browser = window.current; while (browser.directory.loading) yield pause_layout();
    var work = metadata.tag_by_name("Work"); var projects = metadata.tag_by_name("Projects"); var personal = metadata.tag_by_name("Personal");
    var one = new Gee.ArrayList<File>(); one.add(a); metadata.set_tag_for_files(one, work.id, true); metadata.set_tag_for_files(one, projects.id, true);
    var two = new Gee.ArrayList<File>(); two.add(b); metadata.set_tag_for_files(two, projects.id, true); metadata.set_tag_for_files(two, personal.id, true);
    var selection = new Gee.ArrayList<FileItem>(); selection.add(new FileItem(a, a.query_info(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE))); selection.add(new FileItem(b, b.query_info(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE)));
    foreach (bool dark in new bool[] {false, true}) {
        Adw.StyleManager.get_default().color_scheme = dark ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
        var theme = Environment.get_variable("MAJORIS_TAG_THEME"); if (theme != null) { var css = new Gtk.CssProvider(); css.load_from_path(theme + "/gtk-4.0/" + (dark ? "gtk-dark.css" : "gtk.css")); Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER); }
        string suffix = dark ? "-dark" : "-light";
        var manage = new TagsDialog(metadata); manage.present(window); yield pause_layout(); yield shot("manage-defaults" + suffix);
        var row = tag_row(manage, work.id); assert(row != null); manage.list.select_row(row); yield shot("manage-selected" + suffix);
        row.color_button.popup(); yield pause_layout(); assert(row.color_button.popover is TagPalette); assert(row.color_button.popover.get_mapped()); yield shot("colour-palette" + suffix);
        var palette = (TagPalette)row.color_button.popover; tooltip_button(palette, "Orange").clicked(); yield pause_layout(); assert(metadata.tag_by_id(work.id).color == "#F97316");
        row = tag_row(manage, work.id); row.color_button.popup(); yield pause_layout(); palette = (TagPalette)row.color_button.popover;
        ((Gtk.Button)labelled(palette, "Custom Colour…")).clicked(); yield pause_layout();
        var toplevels = Gtk.Window.get_toplevels(); Gtk.Dialog? color_dialog = null;
        for (uint i = 0; i < toplevels.get_n_items(); i++) { var candidate = toplevels.get_item(i) as Gtk.Dialog; if (candidate != null && candidate is Gtk.ColorChooser && candidate.visible) { color_dialog = candidate; break; } }
        assert(color_dialog != null); var custom = Gdk.RGBA(); custom.parse("#13579B"); ((Gtk.ColorChooser)color_dialog).set_rgba(custom); color_dialog.response(Gtk.ResponseType.OK); yield pause_layout(); assert(metadata.tag_by_id(work.id).color == "#13579B");
        row = tag_row(manage, work.id); row.color_button.popup(); yield pause_layout(); palette = (TagPalette)row.color_button.popover; tooltip_button(palette, "No Colour").clicked(); yield pause_layout(); assert(metadata.tag_by_id(work.id).color == "");
        row = tag_row(manage, work.id); manage.list.select_row(row); row.grab_focus(); yield key("F2"); assert(row.editing); row.editor.entry.text = "Business"; yield shot("inline-rename" + suffix); row.editor.entry.activate(); yield pause_layout(); assert(metadata.tag_by_id(work.id).name == "Business" && metadata.has_tag(a, work.id));
        row = tag_row(manage, work.id); row.begin_edit(); row.editor.entry.text = ""; row.editor.entry.activate(); assert(row.editing && row.editor.error_label.visible); yield key("Escape"); assert(!row.editing && metadata.tag_by_id(work.id).name == "Business");
        row.begin_edit(); row.editor.entry.text = "Projects"; row.editor.entry.activate(); assert(row.editing && row.editor.error_label.visible); row.editor.cancelled();
        metadata.update_tag(work.id, "Work", "#EF4444", true); yield pause_layout();
        manage.new_button.clicked(); yield pause_layout(); var draft = manage.list.get_row_at_index(metadata.tag_definitions().size) as TagManageRow; assert(draft != null && draft.editing);
        draft.editor.entry.text = "新しいタグ"; yield shot("inline-create" + suffix); draft.editor.cancelled(); yield pause_layout(); assert(metadata.tag_by_name("新しいタグ") == null);
        manage.close(); yield pause_layout();
        var assign = new TagAssignmentDialog(metadata, selection); assign.present(window); yield pause_layout();
        assert(assign.checkbox(work.id).inconsistent && !assign.checkbox(projects.id).inconsistent && assign.checkbox(projects.id).active && assign.checkbox(personal.id).inconsistent);
        yield shot("mixed-assignment" + suffix);
        assign.search.text = "wOrK"; assign.search.search_changed(); yield pause_layout(); yield shot("assignment-search" + suffix); assign.search.text = ""; assign.search.search_changed();
        assign.checkbox(work.id).active = true; assert(metadata.has_tag(a, work.id) && metadata.has_tag(b, work.id) && metadata.has_tag(a, projects.id) && metadata.has_tag(b, personal.id));
        assign.checkbox(work.id).active = false; assert(!metadata.has_tag(a, work.id) && !metadata.has_tag(b, work.id) && metadata.has_tag(a, projects.id));
        assign.new_button.clicked(); assign.creator.entry.text = "Created " + (dark ? "dark" : "light"); assign.creator.entry.activate(); yield pause_layout(); var created = metadata.tag_by_name("Created " + (dark ? "dark" : "light")); assert(created != null && metadata.has_tag(a, created.id) && metadata.has_tag(b, created.id));
        yield shot("assignment" + suffix); assign.close(); yield pause_layout();
        browser.navigate(metadata.tag_by_name("Archive").location()); yield pause_layout(); assert(browser.virtual_collection && !browser.accepts_destination && browser.tag_empty.visible); yield shot("empty-collection" + suffix);
        browser.navigate(projects.location()); yield pause_layout(); assert(browser.active_selection.get_n_items() == 2 && browser.virtual_collection); yield shot("populated-collection" + suffix);
        browser.select_file(a); var props = new PropertiesDialog(window, selection, metadata); props.present(window); yield pause_layout(); yield shot("properties-tags" + suffix); props.close();
        browser.navigate(root); while (browser.directory.loading) yield pause_layout(); yield pause_layout(); yield shot("sidebar-tags" + suffix);
        // Dispatch through the actual sidebar DropTarget; no operation manager is used.
        var target = sidebar_tag(browser, work.id); assert(target != null); var controllers = target.observe_controllers(); bool dropped = false;
        uint jobs_before = operations.jobs.get_n_items();
        var single_payload = new Gdk.FileList.from_array({a}); Value single_value = Value(typeof(Gdk.FileList)); single_value.set_boxed(single_payload);
        for (uint i = 0; i < controllers.get_n_items(); i++) { var drop = controllers.get_item(i) as Gtk.DropTarget; if (drop != null) assert(drop.drop(single_value, 4, 4)); }
        assert(metadata.has_tag(a, work.id));
        var payload = new Gdk.FileList.from_array({a, b, folder}); Value value = Value(typeof(Gdk.FileList)); value.set_boxed(payload);
        for (uint i = 0; i < controllers.get_n_items(); i++) { var drop = controllers.get_item(i) as Gtk.DropTarget; if (drop != null) dropped = drop.drop(value, 4, 4); }
        assert(operations.jobs.get_n_items() == jobs_before);
        assert(dropped && metadata.has_tag(a, work.id) && metadata.has_tag(b, work.id) && metadata.has_tag(folder, work.id) && a.query_exists() && b.query_exists() && folder.query_exists());
        yield shot("drop-assignment" + suffix);
        metadata.set_tag_for_files(one, work.id, true); metadata.set_tag_for_files(two, work.id, false);
    }
    // Open stable collections survive rename/hide and refresh on assignment deltas.
    browser.navigate(work.location()); yield pause_layout(); metadata.update_tag(work.id, "Work renamed", "#123456", false); yield pause_layout();
    assert(browser.location.equal(work.location()) && sidebar_tag(browser, work.id) == null);
    metadata.set_tag_for_files(one, work.id, false); yield pause_layout(); assert(!metadata.has_tag(a, work.id));
    metadata.remove_tag(work.id); yield pause_layout(); assert(browser.location.get_uri() == "majoris:///favorites");
    // Tag drops never change the filesystem, and invalid virtual payloads fail atomically.
    bool rejected = false; var invalid = new Gee.ArrayList<File>(); invalid.add(File.new_for_uri("majoris:///favorites")); try { browser.assign_tag_drop(projects.id, invalid); } catch (Error e) { rejected = true; } assert(rejected);
    // Definition changes update an open manager and assignment interface without recreation.
    var manage = new TagsDialog(metadata); manage.present(window); yield pause_layout(); manage.new_button.clicked(); yield pause_layout();
    var draft = manage.list.get_row_at_index(metadata.tag_definitions().size) as TagManageRow; draft.editor.entry.text = "UI Created"; draft.editor.entry.activate(); yield pause_layout();
    var tag = metadata.tag_by_name("UI Created"); assert(tag != null); var row = tag_row(manage, tag.id); row.sidebar_switch.active = false; yield pause_layout(); assert(!metadata.tag_by_id(tag.id).sidebar_visible);
    var before = metadata.tag_definitions(); int old_index = before.index_of(before[before.size - 1]); manage.list.select_row(row); row.grab_focus(); yield key("alt+Up"); assert(metadata.tag_by_id(tag.id).position == old_index - 1);
    row = tag_row(manage, tag.id); var reorder_target = tag_row(manage, projects.id); assert(reorder_target != null);
    var reorder_controllers = reorder_target.observe_controllers(); Value reorder_value = Value(typeof(string)); reorder_value.set_string("majoris-tag:" + tag.id.to_string()); bool reordered = false;
    for (uint i = 0; i < reorder_controllers.get_n_items(); i++) { var drop = reorder_controllers.get_item(i) as Gtk.DropTarget; if (drop != null) reordered = drop.drop(reorder_value, 4, 4); }
    assert(reordered); yield pause_layout();
    row = tag_row(manage, tag.id); assert(row != null);
    Test.message("Row properties: selectable=%s visible=%s child=%s mapped=%s mode=%d index=%d parent=%s", row.selectable.to_string(), row.visible.to_string(), row.get_child_visible().to_string(), row.get_mapped().to_string(), (int)manage.list.selection_mode, row.get_index(), (row.get_parent() == manage.list).to_string());
    manage.list.select_row(row);
    Test.message("Delete selection: %s / sensitive=%s / rooted=%s", (manage.list.get_selected_row() != null).to_string(), manage.delete_button.sensitive.to_string(), (manage.get_root() != null).to_string());
    manage.delete_button.clicked(); yield pause_layout(); var confirm = find_type(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(confirm != null); confirm.response("cancel"); confirm.close(); yield pause_layout(); assert(metadata.tag_by_id(tag.id) != null);
    Test.message("Delete after cancel: selected=%s sensitive=%s", (manage.list.get_selected_row() != null).to_string(), manage.delete_button.sensitive.to_string());
    manage.delete_button.clicked(); yield pause_layout(); confirm = find_type(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(confirm != null); confirm.response("delete"); confirm.close(); yield pause_layout(); assert(metadata.tag_by_id(tag.id) == null && a.query_exists());
    manage.close();
    // Real rename/undo and copy policy retain tag identities.
    browser.navigate(root); while (browser.directory.loading) yield pause_layout(); browser.select_file(a); var original = metadata.tags_for(a);
    var renamed = yield operations.rename(a, "renamed.txt"); assert(metadata.has_tag(renamed, projects.id)); yield operations.undo(window); assert(a.query_exists() && metadata.has_tag(a, projects.id));
    // Open/Save guards use real selected files and never a virtual destination.
    var open_settings = new VariantBuilder(VariantType.VARDICT); open_settings.add("{sv}", "multiple", new Variant.boolean(true));
    var chooser = new ChooserWindow(new ChooserOptions(false, open_settings.end()), metadata, places); chooser.present(); yield pause_layout(); while (chooser.browser.directory.loading) yield pause_layout(); chooser.browser.navigate(projects.location()); yield pause_layout();
    assert(chooser.browser.virtual_collection && !chooser.browser.accepts_destination); chooser.browser.select_file(a); assert(chooser.browser.selected()[0].file.equal(a));
    string? returned_uri = null; chooser.completed.connect((response, results) => { if (response == 0) returned_uri = results.lookup_value("uris", null).get_child_value(0).get_string(); });
    yield chooser.accept_selection(); assert(returned_uri == a.get_uri()); chooser.destroy();
    var save_settings = new VariantBuilder(VariantType.VARDICT); save_settings.add("{sv}", "current_name", new Variant.string("saved.txt"));
    var save_options = new ChooserOptions(true, save_settings.end()); save_options.initial = root;
    var save = new ChooserWindow(save_options, metadata, places); save.present(); yield pause_layout(); while (save.browser.directory.loading) yield pause_layout(); save.browser.navigate(projects.location()); yield pause_layout();
    bool saved = false; save.completed.connect((response, results) => { if (response == 0) saved = true; }); yield save.accept_selection(); assert(!saved);
    var error_dialog = find_type(save, typeof(Adw.AlertDialog)) as Adw.AlertDialog; if (error_dialog != null) error_dialog.close(); save.destroy();
    // Callback ownership must not retain closed tag interfaces.
    bool marker_released = false; TagMarker? marker = new TagMarker("#EF4444"); marker.weak_ref(() => marker_released = true); marker = null; assert(marker_released);
    bool menu_released = false; Gtk.MenuButton? disposable_menu = new Gtk.MenuButton(); MenuPresentation.button(disposable_menu); disposable_menu.weak_ref(() => menu_released = true); disposable_menu = null; assert(menu_released);
    bool manager_released = false; TagsDialog? disposable_manager = new TagsDialog(metadata); disposable_manager.weak_ref(() => manager_released = true); disposable_manager.present(window); yield pause_layout(); disposable_manager.close(); yield pause_layout(); disposable_manager = null; yield pause_layout(); assert(manager_released);
    bool assignment_released = false; TagAssignmentDialog? disposable_assignment = new TagAssignmentDialog(metadata, selection); disposable_assignment.weak_ref(() => assignment_released = true); disposable_assignment.present(window); yield pause_layout(); disposable_assignment.close(); yield pause_layout(); disposable_assignment = null; yield pause_layout(); assert(assignment_released);
    window.destroy();
}
async void large_assignment_ui() throws Error {
    var root = File.new_for_path(DirUtils.make_tmp("majoris-large-tag-ui-XXXXXX")); var metadata = new MetadataStore(root.get_child("state.db").get_path()); metadata.set_state("notifications", "false");
    for (int i = 0; i < 995; i++) metadata.create_tag("Performance %04d".printf(i));
    var selection = new Gee.ArrayList<FileItem>();
    for (int i = 0; i < 10000; i++) { var info = new FileInfo(); info.set_name("item-%05d".printf(i)); info.set_content_type("text/plain"); selection.add(new FileItem(File.new_for_uri("file:///performance/item-%05d".printf(i)), info)); }
    var app = new Adw.Application("com.majoris.files.largetagcheck", ApplicationFlags.NON_UNIQUE); app.register(null);
    var places = new Places(metadata); var window = new FilesWindow(app, metadata, places, new OperationManager(metadata), root); window.present(); yield pause_layout();
    assert(sidebar_tag(window.current, metadata.tag_by_name("Performance 0994").id) != null);
    int sidebar_events = 0; places.changed.connect(() => sidebar_events++);
    int64 started = get_monotonic_time(); var assignment = new TagAssignmentDialog(metadata, selection); assignment.present(window); yield pause_layout();
    Test.message("1,000-tag / 10,000-file assignment window: %.3f seconds", (get_monotonic_time() - started) / 1000000.0);
    assignment.search.text = "pErFoRmAnCe 0994"; assignment.search.search_changed(); yield pause_layout(); int visible = 0;
    for (var row = assignment.list.get_first_child(); row != null; row = row.get_next_sibling()) if (row.get_child_visible()) visible++;
    assert(visible == 1);
    var tag = metadata.tag_by_name("Performance 0994"); started = get_monotonic_time(); assignment.checkbox(tag.id).active = true;
    assert(metadata.files_for_tag(tag.id).size == 10000 && sidebar_events == 0);
    Test.message("10,000-file checkbox assignment and state refresh: %.3f seconds", (get_monotonic_time() - started) / 1000000.0);
    bool dispatched = false; Idle.add(() => { dispatched = true; return Source.REMOVE; }); yield pause_layout(); assert(dispatched);
    assignment.close(); yield pause_layout(); window.destroy();
}
int main(string[] args) {
    Test.init(ref args); Gtk.init(); Adw.init(); evidence = Environment.get_variable("MAJORIS_TAG_EVIDENCE") ?? ""; if (evidence != "") DirUtils.create_with_parents(evidence, 0755);
    Test.add_func("/tags/native-ui", () => { var loop = new MainLoop(); scenarios.begin((obj, res) => { try { scenarios.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); }); loop.run(); });
    if (evidence == "") Test.add_func("/tags/large-assignment-ui", () => { var loop = new MainLoop(); large_assignment_ui.begin((obj, res) => { try { large_assignment_ui.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); }); loop.run(); });
    return Test.run();
}

