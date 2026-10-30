using MajorisFiles;
void drain() {
    int64 deadline = get_monotonic_time() + 50000;
    while (MainContext.default().pending() && get_monotonic_time() < deadline) MainContext.default().iteration(false);
}
FilenameCell? editor(Gtk.Widget widget) {
    if (widget is FilenameCell && ((FilenameCell)widget).transaction != null) return (FilenameCell)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = editor(child); if (found != null) return found;
    }
    return null;
}
void wait_frames() {
    var loop = new MainLoop(); Timeout.add(250, () => { loop.quit(); return Source.REMOVE; }); loop.run(); drain();
}
async void key_input(string key) throws Error {
    Test.message("key=%s", key);
    var input = new Subprocess.newv({"xdotool", "key", "--clearmodifiers", key}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
    yield input.wait_check_async(null); yield pause_layout();
}
async void real_window() throws Error {
    var folder = File.new_for_path(DirUtils.make_tmp("majoris-inline-native-XXXXXX"));
    FileUtils.set_contents(folder.get_child("Annual Report.pdf").get_path(), "fixture");
    FileUtils.set_contents(folder.get_child("collision.pdf").get_path(), "fixture");
    var metadata = new MetadataStore(Path.build_filename(DirUtils.make_tmp("majoris-inline-state-XXXXXX"), "state.db"));
    metadata.set_state("notifications", "false");
    var operations = new OperationManager(metadata);
    var app = new Adw.Application("com.majoris.files.inlinerenamecheck", ApplicationFlags.NON_UNIQUE); app.register(null);
    var window = new FilesWindow(app, metadata, new Places(metadata), operations, folder);
    window.present(); yield pause_layout();
    var focus = new Subprocess.newv({"xdotool", "search", "--onlyvisible", "--name", "^Files$", "windowfocus", "--sync"}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
    yield focus.wait_check_async(null);
    var browser = window.current;
    while (browser.directory.loading) yield pause_layout();
    foreach (var mode in new string[] {"Grid", "List", "Columns", "Gallery"}) {
        browser.set_view(mode); yield pause_layout();
        browser.select_file(folder.get_child("Annual Report.pdf")); yield pause_layout();
        browser.file_surface.grab_focus();
        yield key_input("F2");
        var cell = editor(browser); assert(cell != null);
        int start, end; assert(cell.entry.get_selection_bounds(out start, out end)); assert(start == 0 && end == 13);
        yield key_input("ctrl+a"); assert(cell.entry.get_selection_bounds(out start, out end)); assert(end == 17);
        assert(browser.selected().size == 1);
        yield key_input("F2"); assert(cell.entry.get_selection_bounds(out start, out end)); assert(end == 17);
        yield key_input("F2"); assert(cell.entry.get_selection_bounds(out start, out end)); assert(end == 13);
        foreach (bool dark in new bool[] {false, true}) {
            Adw.StyleManager.get_default().color_scheme = dark ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
            var output = Environment.get_variable("MAJORIS_INLINE_EVIDENCE");
            if (output != null) { DirUtils.create_with_parents(output, 0755); yield capture(window, output, mode.down() + (dark ? "-dark" : "-light")); }
        }
        cell.entry.text = "cancelled.pdf"; yield key_input("Escape");
        assert(browser.inline_rename == null && folder.get_child("Annual Report.pdf").query_exists());
        Test.message("rename mode=%s selected=%d eligible=%s enabled=%s", mode, browser.selected().size, browser.can_inline_rename().to_string(), ((SimpleAction)window.lookup_action("rename")).enabled.to_string());
        window.lookup_action("rename").activate(null); yield pause_layout(); cell = editor(browser); assert(cell != null);
        // Unchanged Enter must not touch the filesystem or journal.
        yield key_input("Return"); assert(browser.inline_rename == null);
        window.lookup_action("rename").activate(null); yield pause_layout(); cell = editor(browser); assert(cell != null);
        cell.entry.text = ""; yield key_input("Return");
        assert(browser.inline_rename != null && !browser.inline_rename.pending && cell.entry.has_css_class("error"));
        cell.entry.text = "collision.pdf"; yield key_input("Return");
        assert(browser.inline_rename != null && !browser.inline_rename.pending && cell.entry.text == "collision.pdf");
        cell.entry.text = "Renamed Report.pdf"; yield key_input("Return");
        assert(browser.inline_rename == null && folder.get_child("Renamed Report.pdf").query_exists());
        assert(browser.selected().size == 1 && browser.selected()[0].file.equal(folder.get_child("Renamed Report.pdf")));
        yield key_input("ctrl+z"); assert(folder.get_child("Annual Report.pdf").query_exists());
        assert(browser.selected().size == 1 && browser.selected()[0].file.equal(folder.get_child("Annual Report.pdf")));
        yield key_input("ctrl+shift+z"); assert(folder.get_child("Renamed Report.pdf").query_exists());
        assert(browser.selected().size == 1 && browser.selected()[0].file.equal(folder.get_child("Renamed Report.pdf")));
        yield operations.undo(); yield pause_layout();
        browser.select_file(folder.get_child("Annual Report.pdf")); yield pause_layout();
        window.lookup_action("rename").activate(null); yield pause_layout(); cell = editor(browser); assert(cell != null);
        cell.entry.text = "Tab Report.pdf";
        yield key_input("ctrl+a"); yield key_input("ctrl+c"); yield key_input("End"); yield key_input("ctrl+v");
        assert(cell.entry.text == "Tab Report.pdfTab Report.pdf");
        yield key_input("ctrl+a"); yield key_input("ctrl+x"); assert(cell.entry.text == "");
        yield key_input("ctrl+v"); assert(cell.entry.text == "Tab Report.pdfTab Report.pdf");
        cell.entry.text = "Tab Report.pdf"; yield key_input("Tab");
        assert(browser.inline_rename == null && folder.get_child("Tab Report.pdf").query_exists());
        yield operations.undo(); yield pause_layout();
        browser.select_file(folder.get_child("Annual Report.pdf")); yield pause_layout();
        window.lookup_action("rename").activate(null); yield pause_layout(); cell = editor(browser); assert(cell != null);
        cell.entry.text = "Outside Report.pdf";
        var click = new Subprocess.newv({"xdotool", "mousemove", "--sync", "1040", "650", "click", "1"}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
        yield click.wait_check_async(null); yield pause_layout();
        assert(browser.inline_rename == null && folder.get_child("Outside Report.pdf").query_exists());
        yield operations.undo(); yield pause_layout(); browser.select_file(folder.get_child("Annual Report.pdf")); yield pause_layout();
        window.lookup_action("rename").activate(null); yield pause_layout(); cell = editor(browser); assert(cell != null);
        cell.entry.text = "changed.txt"; yield key_input("Return");
        var dialog = window.visible_dialog as Adw.AlertDialog; assert(dialog != null);
        assert(browser.inline_rename.pending); dialog.response("cancel"); dialog.close(); yield pause_layout();
        cell = editor(browser); assert(cell != null && cell.entry.text == "changed.txt" && !browser.inline_rename.pending);
        yield key_input("Return"); dialog = window.visible_dialog as Adw.AlertDialog; assert(dialog != null);
        dialog.response("apply"); dialog.close(); yield pause_layout();
        assert(browser.inline_rename == null && folder.get_child("changed.txt").query_exists());
        yield operations.undo(); yield pause_layout();
    }
    window.destroy();
}
void restore_directory_permissions(File folder) { try { folder.set_attribute_uint32("unix::mode", 0700, FileQueryInfoFlags.NONE); } catch (Error e) { warning("%s", e.message); } }
async void permission_window() throws Error {
    var folder = File.new_for_path(DirUtils.make_tmp("majoris-inline-permission-XXXXXX"));
    var metadata = new MetadataStore(Path.build_filename(DirUtils.make_tmp("majoris-inline-permission-state-XXXXXX"), "state.db"));
    var app = new Adw.Application("com.majoris.files.inlinerenamepermissions", ApplicationFlags.NON_UNIQUE); app.register(null);
    var window = new FilesWindow(app, metadata, new Places(metadata), new OperationManager(metadata), folder);
    var browser = window.current; window.present(); yield pause_layout();
    // Capabilities may become stale after editing starts: backend denial must retain text.
    var locked = folder.get_child("locked"); locked.make_directory();
    FileUtils.set_contents(locked.get_child("source.txt").get_path(), "fixture");
    browser.set_view("Grid"); browser.navigate(locked);
    while (browser.directory.loading) yield pause_layout();
    browser.select_file(locked.get_child("source.txt")); yield pause_layout();
    window.lookup_action("rename").activate(null); yield pause_layout();
    var denied_cell = editor(browser); assert(denied_cell != null);
    locked.set_attribute_uint32("unix::mode", 0500, FileQueryInfoFlags.NONE);
    try {
        denied_cell.entry.text = "denied.txt"; denied_cell.entry.activate(); yield pause_layout();
        assert(browser.inline_rename != null && !browser.inline_rename.pending);
        assert(denied_cell.entry.text == "denied.txt" && denied_cell.entry.has_css_class("error"));
        assert(locked.get_child("source.txt").query_exists());
    } finally { restore_directory_permissions(locked); }
    yield pause_layout(); denied_cell = editor(browser); assert(denied_cell != null);
    denied_cell.entry.activate(); yield pause_layout(); assert(locked.get_child("denied.txt").query_exists());
    window.destroy();
}
int main(string[] args) {
    Test.init(ref args); Gtk.init(); Adw.init();
    Test.add_func("/inline-rename/stems", () => {
        string[] names = {"report.txt", "archive.tar.gz", "README", ".bashrc", ".gitignore", "holiday.photo.jpg", "年次 報告.pdf", ".txt", ".tar.gz"};
        string[] stems = {"report", "archive.tar", "README", ".bashrc", ".gitignore", "holiday.photo", "年次 報告", ".txt", ".tar"};
        for (int i = 0; i < names.length; i++) {
            assert(InlineRename.stem_length(names[i], false) == stems[i].char_count());
            assert(InlineRename.stem_length(names[i], true) == names[i].char_count());
        }
    });
    Test.add_func("/inline-rename/views-and-recycling", () => {
        try {
            var temp = DirUtils.make_tmp("majoris-inline-XXXXXX");
            for (int i = 0; i < 1500; i++) FileUtils.set_contents(Path.build_filename(temp, "item-%04d.txt".printf(i)), "fixture");
            var metadata = new MetadataStore(Path.build_filename(DirUtils.make_tmp("majoris-inline-model-state-XXXXXX"), "metadata.db"));
            var browser = new Browser(metadata, new Places());
            var window = new Gtk.Window(); window.set_default_size(1000, 700); window.child = browser; window.present();
            browser.navigate(File.new_for_path(temp));
            while (browser.directory.loading) { MainContext.default().iteration(true); }
            foreach (var mode in new string[] {"Grid", "Grouped Grid", "List", "Columns", "Gallery"}) {
                browser.set_group(mode == "Grouped Grid" ? "Type" : "None");
                browser.set_view(mode == "Grouped Grid" ? "Grid" : mode); wait_frames();
                foreach (int position in new int[] {0, 750, 1499}) {
                browser.select_file(File.new_for_path(Path.build_filename(temp, "item-%04d.txt".printf(position)))); wait_frames();
                for (int attempt = 0; browser.selected().size != 1 && attempt < 20; attempt++) wait_frames();
                assert(browser.selected().size == 1);
                browser.begin_inline_rename(); wait_frames();
                Test.message("mode=%s selected=%d state=%s eligible=%s", mode, browser.selected().size, (browser.inline_rename != null).to_string(), browser.can_inline_rename().to_string());
                var cell = editor(browser); assert(cell != null);
                var state = browser.inline_rename; assert(state != null);
                assert(cell.item.file.equal(state.item.file));
                cell.entry.text = "proposed.txt"; assert(state.proposed == "proposed.txt");
                cell.detach(); drain(); assert(browser.inline_rename == state); assert(!state.pending);
                browser.cancel_inline_rename(); assert(browser.inline_rename == null);
                assert(FileUtils.test(Path.build_filename(temp, "item-%04d.txt".printf(position)), FileTest.EXISTS));
                }
            }
            window.destroy();
        } catch (Error e) { error("%s", e.message); }
    });
    Test.add_func("/inline-rename/cell-state", () => {
        var info = new FileInfo(); info.set_file_type(FileType.REGULAR); info.set_display_name("年次.pdf");
        var item = new FileItem(File.new_for_path("/tmp/年次.pdf"), info);
        var store = new GLib.ListStore(typeof(FileItem)); store.append(item);
        var state = new InlineRename(item, new Gtk.MultiSelection(store));
        var cell = new FilenameCell(); cell.item = item; cell.context = state.context;
        var window = new Gtk.Window(); window.child = cell; window.present(); wait_frames();
        cell.render(state, true); int start, end;
        assert(cell.entry.get_selection_bounds(out start, out end)); assert(start == 0 && end == 2);
        cell.toggle_selection(); assert(cell.entry.get_selection_bounds(out start, out end)); assert(end == 6);
        state.proposed = "collision.pdf"; state.message = "File exists"; cell.render(state, true);
        assert(cell.entry.text == "collision.pdf" && cell.entry.has_css_class("error"));
        state.cancelled = true; cell.detach(); drain(); assert(cell.transaction == null);
        window.destroy();
    });
    Test.add_func("/inline-rename/native-interactions", () => {
        var loop = new MainLoop();
        real_window.begin((obj, res) => { try { real_window.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    Test.add_func("/inline-rename/permission-denied", () => {
        var loop = new MainLoop();
        permission_window.begin((obj, res) => { try { permission_window.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    return Test.run();
}
