using MajorisFiles;
string output;
class MenuCloud : Object, CloudFileProvider {
    File location;
    public File root { get { return location; } }
    public MenuCloud(File location) { this.location = location; }
    public async CloudFileState query(File file, Cancellable token) throws Error {
        var state = new CloudFileState(); state.state = "online-only"; state.capabilities = {"pin"}; return state;
    }
    public async File perform(File file, string action, uint64 maximum_bytes, Cancellable token, CloudProgress? progress = null) throws Error { throw new IOError.NOT_SUPPORTED("Menu fixture only"); }
}
string[] labels(MenuModel model, bool recursive = true) {
    string[] result = {};
    for (int i = 0; i < model.get_n_items(); i++) {
        assert(model.get_item_attribute_value(i, "icon", null) == null);
        var label = model.get_item_attribute_value(i, "label", VariantType.STRING);
        if (label != null) result += label.get_string();
        var section = model.get_item_link(i, Menu.LINK_SECTION);
        if (section != null) { assert(section.get_n_items() > 0); foreach (var text in labels(section, recursive)) result += text; }
        var sub = model.get_item_link(i, Menu.LINK_SUBMENU);
        if (sub != null) { assert(sub.get_n_items() > 0); if (recursive) foreach (var text in labels(sub)) result += text; }
    }
    return result;
}
Gtk.PopoverMenu? file_popup(Gtk.Widget widget) {
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) if (c is Gtk.PopoverMenu) return (Gtk.PopoverMenu)c;
    return null;
}
Gtk.Widget? menu_label(Gtk.Widget widget, string text) {
    if (widget is Gtk.Label && ((Gtk.Label)widget).label == text && widget.get_mapped()) return widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = menu_label(c, text); if (found != null) return found; } return null;
}
Gtk.MenuButton? menu_button(Gtk.Widget widget, string icon) {
    if (widget is Gtk.MenuButton && ((Gtk.MenuButton)widget).icon_name == icon) return (Gtk.MenuButton)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = menu_button(c, icon); if (found != null) return found; } return null;
}
void verify_arrows(Gtk.Widget widget) {
    if (widget.get_css_name() == "arrow" && widget.get_mapped()) assert(widget.get_width() == 0);
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) verify_arrows(c);
}
Gtk.ListBoxRow? place_row(Gtk.Widget widget) {
    if (widget is Gtk.ListBoxRow && widget.get_data<Place>("majoris-place") != null && widget.get_data<Place>("majoris-place").system) return (Gtk.ListBoxRow)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = place_row(c); if (found != null) return found; } return null;
}
void dismiss_popovers(Gtk.Widget widget) {
    var c = widget.get_first_child();
    while (c != null) { var next = c.get_next_sibling(); dismiss_popovers(c); c = next; }
    if (widget is Gtk.Popover) ((Gtk.Popover)widget).popdown();
}
Gtk.Widget? file_view(Gtk.Widget widget) {
    if (widget is Gtk.GridView && widget.get_mapped()) return widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = file_view(c); if (found != null) return found; } return null;
}
FilenameCell? file_cell(Gtk.Widget widget, string name) {
    if (widget is FilenameCell && widget.get_mapped() && ((FilenameCell)widget).item != null && ((FilenameCell)widget).item.name == name) return (FilenameCell)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = file_cell(c, name); if (found != null) return found; } return null;
}
Adw.PreferencesRow? preference(Gtk.Widget widget, string title) {
    if (widget is Adw.PreferencesRow && ((Adw.PreferencesRow)widget).title == title) return (Adw.PreferencesRow)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = preference(c, title); if (found != null) return found; } return null;
}
async void screenshot(string name) throws Error {
    if (output == "") return;
    yield pause_layout();
    var path = Path.build_filename(output, name);
    var grab = new Subprocess.newv({"xwd", "-silent", "-root", "-out", path + ".xwd"}, SubprocessFlags.NONE); yield grab.wait_check_async(null);
    var convert = new Subprocess.newv({"magick", path + ".xwd", path + ".png"}, SubprocessFlags.NONE); yield convert.wait_check_async(null); FileUtils.unlink(path + ".xwd");
}
async void scenarios() throws Error {
    var folder = File.new_for_path(DirUtils.make_tmp("majoris-menu-fixture-XXXXXX"));
    FileUtils.set_contents(folder.get_child("document.txt").get_path(), "text");
    FileUtils.set_contents(folder.get_child("archive.zip").get_path(), "archive menu fixture");
    yield folder.get_child("Folder").make_directory_async(Priority.DEFAULT, null);
    var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 16, 16); surface.write_to_png(folder.get_child("image.png").get_path());
    var metadata = new MetadataStore(Path.build_filename(DirUtils.make_tmp("majoris-menu-state-XXXXXX"), "state.db")); metadata.set_state("notifications", "false");
    var app = new Adw.Application("com.majoris.files.menucheck", ApplicationFlags.NON_UNIQUE); app.register(null);
    var window = new FilesWindow(app, metadata, new Places(metadata), new OperationManager(metadata), folder); window.present();
    var browser = window.current; while (browser.directory.loading) yield pause_layout(); yield pause_layout();
    foreach (bool dark in new bool[] {false, true}) {
        Adw.StyleManager.get_default().color_scheme = dark ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
        string suffix = dark ? "-dark" : "-light";
        var theme = Environment.get_variable("MAJORIS_MENU_THEME");
        if (theme != null) {
            var css = new Gtk.CssProvider(); css.load_from_path(theme + "/gtk-4.0/" + (dark ? "gtk-dark.css" : "gtk.css"));
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER);
        }
        foreach (var filename in new string[] {"document.txt", "Folder", "archive.zip", "image.png", "multiple", "empty"}) {
            browser.active_selection.unselect_all();
            if (filename != "empty") browser.select_file(folder.get_child(filename == "multiple" ? "document.txt" : filename));
            if (filename == "multiple") for (uint i = 0; i < browser.active_selection.get_n_items(); i++) if (((FileItem)browser.active_selection.get_item(i)).name == "Folder") browser.active_selection.select_item(i, false);
            var model = new Menu(); window.populate_context(model, browser); var all = labels(model); var main = labels(model, false);
            assert(!("Permissions…" in all) && !("Default Application…" in all) && !("Custom Icon…" in all));
            assert(!("Extract with Password…" in all) && !("Create Encrypted ZIP…" in all));
            if (filename == "empty") { assert("New Folder…" in main); assert(!("Properties" in main)); }
            else {
                assert(main[main.length - 1] == "Properties"); assert("More Actions…" in main); assert("Compress…" in all); assert(!("Compress…" in main));
                assert("Add to Favorites" in main); assert("Tags…" in main);
                if (filename == "multiple") { assert(!("Open" in main)); assert("Batch Rename…" in main); }
                else assert("Open" in main);
                if (filename == "Folder") { assert("Open in New Tab" in main); assert(!("Open With…" in main)); }
                if (filename == "archive.zip") assert("Extract…" in main);
                if (filename == "image.png") { assert("Quick Actions…" in all); assert(!("Rotate Clockwise" in main)); }
            }
            var popup = file_popup(browser.file_surface); assert(popup != null && !popup.has_arrow);
            popup.menu_model = model;
            Gdk.Rectangle anchor = {browser.file_surface.get_width() / 2, browser.file_surface.get_height() / 3, 1, 1}; popup.pointing_to = anchor; popup.popup(); yield screenshot(filename + suffix);
            if (filename == "document.txt") {
                // GtkPopoverMenu exposes native submenu navigation as an action.
                var more = menu_label(popup, "More Actions…"); assert(more != null); more.get_parent().activate(); yield pause_layout();
                assert(menu_label(popup, "Duplicate") != null); if (theme != null) verify_arrows(popup);
                yield screenshot("more-actions" + suffix);
            }
            popup.popdown();
        }
        foreach (var icon in new string[] {"open-menu-symbolic", "view-more-symbolic"}) {
            var button = menu_button(window, icon); assert(button != null);
            if (!button.get_mapped()) { window.set_default_size(500, 740); yield pause_layout(); }
            if (button.get_mapped()) { button.popup(); yield pause_layout(); assert(!button.popover.has_arrow); yield screenshot((icon == "open-menu-symbolic" ? "application" : "overflow") + suffix); button.popdown(); }
        }
        window.set_default_size(1100, 740); yield pause_layout();
        var row = place_row(browser); assert(row != null); var controllers = row.get_parent().observe_controllers();
        for (uint i = 0; i < controllers.get_n_items(); i++) {
            var gesture = controllers.get_item(i) as Gtk.GestureClick;
            if (gesture != null && gesture.button == 3) { Graphene.Rect bounds; row.compute_bounds(row.get_parent(), out bounds); gesture.pressed(1, 16, bounds.origin.y + 8); yield pause_layout(); var device_popup = file_popup(row.get_parent()); assert(device_popup != null && device_popup.get_mapped());
                Test.message("Sidebar popup: %dx%d items=%d", device_popup.get_width(), device_popup.get_height(), device_popup.menu_model.get_n_items());
                assert(menu_label(device_popup, "Open in New Tab") != null); yield screenshot("sidebar" + suffix); break; }
        }
        dismiss_popovers(window);
        window.set_default_size(1100, 740); yield pause_layout();
    }
    // Invoke the native file menu through both keyboard entry points.
    var focus = new Subprocess.newv({"xdotool", "search", "--name", "^Files$", "windowfocus", "--sync"}, SubprocessFlags.STDOUT_SILENCE); yield focus.wait_check_async(null);
    dismiss_popovers(window); browser.set_view("Grid"); yield pause_layout(); browser.select_file(folder.get_child("document.txt"));
    var view = file_view(browser.file_surface); assert(view != null); view.grab_focus(); yield pause_layout();
    foreach (var key in new string[] {"Menu", "shift+F10"}) {
        Test.message("Keyboard context key=%s focus=%s", key, window.get_focus() == null ? "none" : window.get_focus().get_type().name());
        var input = new Subprocess.newv({"xdotool", "key", "--clearmodifiers", key}, SubprocessFlags.NONE); yield input.wait_check_async(null); yield pause_layout();
        assert(file_popup(browser.file_surface).visible);
        var escape = new Subprocess.newv({"xdotool", "key", "Escape"}, SubprocessFlags.NONE); yield escape.wait_check_async(null); yield pause_layout(); assert(!file_popup(browser.file_surface).visible);
    }
    // Mixed favorites converge to all added, then all removed.
    browser.active_selection.select_all(); var selected = browser.selected(); assert(selected.size > 1);
    metadata.set_favorite(selected[0].file, true); window.lookup_action("favorite").activate(null);
    foreach (var item in selected) assert(metadata.favorite(item.file));
    var favorite_menu = new Menu(); window.populate_context(favorite_menu, browser); assert("Remove from Favorites" in labels(favorite_menu));
    window.lookup_action("favorite").activate(null); foreach (var item in selected) assert(!metadata.favorite(item.file));
    var compress = new SevenZipDialog(window, selected, folder, new OperationManager(metadata)); yield pause_layout();
    var archive_name = preference(compress, "Archive Filename") as Adw.EntryRow;
    var archive_format = preference(compress, "Archive Format") as Adw.ComboRow;
    var volume = preference(compress, "Volume Size (MiB; 0 for one file)") as Adw.SpinRow;
    var level = preference(compress, "Compression Level") as Adw.SpinRow;
    var encryption = preference(compress, "Encrypt Contents (ZIP filenames remain visible)") as Adw.SwitchRow;
    assert(archive_name != null && archive_format != null && volume != null && level != null && encryption != null);
    assert(encryption.sensitive && !volume.sensitive && !level.sensitive);
    archive_name.text = "My archive.zip"; archive_format.selected = 1;
    assert(archive_name.text == "My archive.7z" && volume.sensitive && level.sensitive && encryption.sensitive);
    encryption.active = true; archive_format.selected = 2;
    assert(archive_name.text == "My archive.tar" && !encryption.sensitive && !encryption.active && !volume.sensitive);
    compress.close(); yield pause_layout();
    // Provider model adaptation preserves nested targets, sections and state actions.
    var provider = new Menu(); provider.append_submenu("Empty provider submenu", new Menu()); provider.append_section(null, new Menu()); var sub = new Menu(); var icon = new MenuItem("Provider", "cloudprovider.state::yes"); icon.set_icon(new ThemedIcon("starred-symbolic")); sub.append_item(icon); provider.append_submenu("Provider actions", sub);
    var clean = MenuPresentation.text_only(provider); labels(clean); assert(clean.get_n_items() == 1);
    var target = clean.get_item_link(0, Menu.LINK_SUBMENU).get_item_attribute_value(0, "target", VariantType.STRING); assert(target.get_string() == "yes");
    // Pointer target and empty-space reset in every view.
    foreach (var mode in new string[] {"Grid", "List", "Columns", "Gallery"}) {
        browser.set_view(mode); yield pause_layout(); browser.select_file(folder.get_child("document.txt")); yield pause_layout();
        var cell = file_cell(browser.file_surface, "document.txt"); assert(cell != null);
        Graphene.Rect bounds; assert(cell.compute_bounds(browser.file_surface, out bounds));
        browser.active_selection.unselect_all(); browser.target_context(bounds.origin.x + 2, bounds.origin.y + 2);
        assert(browser.selected().size == 1 && browser.selected()[0].name == "document.txt");
        browser.active_selection.select_all(); int count = browser.selected().size;
        browser.target_context(bounds.origin.x + 2, bounds.origin.y + 2); assert(browser.selected().size == count);
        browser.target_context(browser.file_surface.get_width() - 2, browser.file_surface.get_height() - 2); assert(browser.selected().size == 0);
    }
    browser.set_view("List"); browser.select_file(folder.get_child("document.txt"));
    var cloud = CloudFiles.get_default(); cloud.register_provider(new MenuCloud(folder)); cloud.peek(folder.get_child("document.txt"));
    for (int i = 0; cloud.cached(folder.get_child("document.txt")) == null && i < 10; i++) yield pause_layout();
    var cloud_menu = new Menu(); window.populate_context(cloud_menu, browser); var cloud_labels = labels(cloud_menu);
    assert("Make Available Offline" in cloud_labels && !("Free Local Space" in cloud_labels) && !("Retry Cloud Sync" in cloud_labels));
    var readonly = folder.get_child("Read Only"); yield readonly.make_directory_async(Priority.DEFAULT, null);
    readonly.set_attribute_uint32("unix::mode", 0555, FileQueryInfoFlags.NONE); browser.navigate(readonly);
    while (browser.directory.loading) yield pause_layout(); yield pause_layout();
    var readonly_menu = new Menu(); window.populate_context(readonly_menu, browser);
    assert(!browser.accepts_destination && !("New Folder…" in labels(readonly_menu)) && !("Paste" in labels(readonly_menu)));
    readonly.set_attribute_uint32("unix::mode", 0755, FileQueryInfoFlags.NONE);
    browser.directory.virtual_location(File.new_for_uri("trash:///"));
    browser.directory.items.append(selected[0]); browser.selection.select_all();
    var trash = new Menu(); window.populate_context(trash, browser); var trash_labels = labels(trash);
    assert("Restore" in trash_labels && "Delete Permanently" in trash_labels && !("Cut" in trash_labels) && !("Compress…" in trash_labels));
    browser.selection.unselect_all(); trash.remove_all(); window.populate_context(trash, browser);
    assert("Empty Trash" in labels(trash) && !("New Folder…" in labels(trash)));
    browser.directory.virtual_location(File.new_for_uri("recent:///")); var recent = new Menu(); window.populate_context(recent, browser); assert(!("New Folder…" in labels(recent)));
    window.destroy();
}
int main(string[] args) {
    Test.init(ref args); Gtk.init(); Adw.init(); output = Environment.get_variable("MAJORIS_MENU_EVIDENCE") ?? "";
    if (output != "") DirUtils.create_with_parents(output, 0755);
    Test.add_func("/menus/context-and-presentation", () => { var loop = new MainLoop(); scenarios.begin((obj, res) => { try { scenarios.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); }); loop.run(); });
    return Test.run();
}
