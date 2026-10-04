using MajorisFiles;
int main(string[] args)
{
    try {
        var root = DirUtils.make_tmp("majoris-test-env-XXXXXX");
        Environment.set_variable("HOME", root, true);
        Environment.set_variable("XDG_DATA_HOME", root, true);
        Environment.set_variable("XDG_CONFIG_HOME", root, true);
        Environment.set_variable("XDG_CACHE_HOME", root, true);
    }
    catch(Error e) {
        error("%s", e.message);
    }
    Gtk.init();
    Adw.init();
    Test.init(ref args);
    Test.add_func("/ui/chooser-modes", () => { try { var temp = DirUtils.make_tmp("majoris-ui-XXXXXX");
                                                     var metadata = new MetadataStore(Path.build_filename(temp, "metadata.db"));
                                                     var places = new Places();
                                                     foreach (bool save in new bool[] {false, true})
                                                     {
                                                         var options = new ChooserOptions(save, new VariantBuilder(VariantType.VARDICT).end());
                                                         options.initial = File.new_for_path(temp);
                                                         var window = new ChooserWindow(options, metadata, places);
                                                         bool cancelled = false;
                                                         window.completed.connect((code, result) => { assert(code == 1);
                                                                                                      assert(result.n_children() == 0);
                                                                                                      cancelled = true;
                                                             });
                                                         window.cancel_request();
                                                         assert(cancelled);
                                                     }
                                               }
                                               catch (Error e) { error("%s", e.message);
                                               }
        });
    Test.add_func("/ui/open-single", () => chooser_flow(false, false, false));
    Test.add_func("/ui/open-multiple", () => chooser_flow(false, true, false));
    Test.add_func("/ui/select-folder", () => chooser_flow(false, false, true));
    Test.add_func("/ui/save-suggested", () => chooser_flow(true, false, false));
    Test.add_func("/ui/select-symlink-folder", () => chooser_flow(false, false, true, true));
    Test.add_func("/ui/initial-location-recovery", () => initial_recovery());
    Test.add_func("/ui/overwrite-confirmation", () => overwrite_test());
    Test.add_func("/ui/merge-move-and-persistent-undo", () => merge_test());
    Test.add_func("/ui/merge-skip-all", () => merge_test("skip-all"));
    Test.add_func("/ui/merge-replace-all", () => merge_test("replace-all"));
    Test.add_func("/ui/merge-rename", () => merge_test("rename"));
    Test.add_func("/ui/column-selection", () => columns_test());
    Test.add_func("/ui/session-detail-recovery", () => session_details_test());
    Test.add_func("/ui/disk-image-inventory", () => disk_image_inventory_test());
    Test.add_func("/ui/bookmark-reorder-and-drop-policy", () => bookmark_drop_test());
    Test.add_func("/ui/transferred-tab-routing", () => {
        try {
            var temp = DirUtils.make_tmp("majoris-tabs-XXXXXX");
            var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
            var places = new Places();
            var operations = new OperationManager(metadata);
            var app = new Adw.Application("com.majoris.files.tabs.test", ApplicationFlags.NON_UNIQUE);
            app.register(null);
            var first = new FilesWindow(app, metadata, places, operations, File.new_for_path(temp));
            first.new_tab(File.new_for_path(temp));
            var second = new FilesWindow(app, metadata, places, operations, null, true);
            var page = first.tabs.selected_page;
            first.tabs.transfer_page(page, second.tabs, 0);
            var browser = (Browser)page.child;
            browser.open_in_tab(File.new_for_path(temp));
            assert(first.tabs.n_pages == 1 && second.tabs.n_pages == 2);
            for(int i = 0; i < first.tabs.n_pages; i++)
                ((Browser)first.tabs.get_nth_page(i).child).cancel();
            for(int i = 0; i < second.tabs.n_pages; i++)
                ((Browser)second.tabs.get_nth_page(i).child).cancel();
            first.destroy();
            second.destroy();
        }
        catch(Error e) { error("%s", e.message);
        }
    });
    Test.add_func("/ui/script-policy-and-previews", () => {
        var loop = new MainLoop();
        bool passed = false;
        preview_case.begin((obj, res) => { try { preview_case.end(res);
                                                 passed = true;
                                           }
                                           catch(Error e) { error("%s", e.message);
                                           }
                                           loop.quit();
            });
        uint watchdog = Timeout.add_seconds(10, () => { error("Preview/provider test timed out");
            });
        loop.run();
        Source.remove(watchdog);
        assert(passed);
    });
    Test.add_func("/ui/sharing-policy", () => { assert(SharePolicy.valid_name("Projects"));
                                                assert(!SharePolicy.valid_name("../etc"));
                                                assert(!SharePolicy.valid_name("a;id"));
                                                try { var command = SharePolicy.arguments("Projects", "/tmp/projects", true, false, {"alice"});
                                                      assert(command[6] == "alice:F");
                                                      assert(command[7] == "guest_ok=n");
                                                }
                                                catch(Error e) { error("%s", e.message);
                                                }
        });
    Test.add_func("/ui/native-file-clipboard", () => {
        var clipboard = Gdk.Display.get_default().get_clipboard();
        var files = new Gee.ArrayList<File>();
        files.add(File.new_for_path("/tmp/example space.txt"));
        foreach(bool cut in new bool[] {false, true})
        {
            FileClipboard.publish(clipboard, files, cut);
            assert(clipboard.get_formats().contain_gtype(typeof(Gdk.FileList)));
            assert(clipboard.get_formats().contain_mime_type("text/uri-list"));
            var loop = new MainLoop();
            FileClipboard.read.begin(clipboard, (obj, res) => {
                try {
                    var content = FileClipboard.read.end(res);
                    assert(content.cut == cut);
                    assert(content.files.size == 1 && content.files[0].equal(files[0]));
                }
                catch(Error e) { error("%s", e.message);
                }
                loop.quit();
            });
            uint watchdog = Timeout.add_seconds(10, () => { error("Clipboard read timed out");
                });
            loop.run();
            Source.remove(watchdog);
        }
        clipboard.set_content(null);
    });
    return Test.run();
}
void overwrite_test()
{
    try {
        var temp = DirUtils.make_tmp("majoris-overwrite-XXXXXX");
        FileUtils.set_contents(Path.build_filename(temp, "existing.txt"), "preserved content");
        var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
        var options = new ChooserOptions(true, new VariantBuilder(VariantType.VARDICT).end());
        options.initial = File.new_for_path(temp);
        options.current_name = "existing.txt";
        var window = new ChooserWindow(options, metadata, new Places(metadata));
        window.present();
        var loop = new MainLoop();
        bool prompted = false;
        bool returned = false;
        window.completed.connect((code, result) => { assert(prompted && code == 0);
                                                     returned = true;
                                                     loop.quit();
            });
        window.browser.directory.loaded.connect(() => window.accept_selection.begin());
        uint poll = Timeout.add(50, () => { var dialog = window.visible_dialog as Adw.AlertDialog;
                                            if(dialog == null)
                                                return Source.CONTINUE;
                                            assert(!returned);
                                            prompted = true;
                                            dialog.response("apply");
                                            return Source.REMOVE;
            });
        uint watchdog = Timeout.add_seconds(10, () => { error("Overwrite confirmation timed out");
                                                        return Source.REMOVE;
            });
        loop.run();
        Source.remove(watchdog);
        assert(returned);
        string content;
        FileUtils.get_contents(Path.build_filename(temp, "existing.txt"), out content);
        assert(content == "preserved content");
    }
    catch(Error e) {
        error("%s", e.message);
    }
}
void merge_test(string decision = "both")
{
    var loop = new MainLoop();
    bool passed = false;
    merge_case.begin(decision, (obj, res) => { try { merge_case.end(res);
                                                     passed = true;
                                               }
                                               catch(Error e) { error("%s", e.message);
                                               }
                                               loop.quit();
        });
    uint watchdog = Timeout.add_seconds(15, () => { error("Folder merge timed out");
        });
    loop.run();
    Source.remove(watchdog);
    assert(passed);
}
void collect_lists(Gtk.Widget widget, Gee.ArrayList<Gtk.ListView> lists)
{
    if(widget is Gtk.ListView && widget.get_mapped())
        lists.add((Gtk.ListView)widget);
    for(var child = widget.get_first_child(); child != null; child = child.get_next_sibling())
        collect_lists(child, lists);
}
async void preview_case() throws Error
{
    var temp = DirUtils.make_tmp("majoris-preview-XXXXXX");
    var root = File.new_for_path(temp);
    FileUtils.set_contents(Path.build_filename(temp, "notes.md"), "# Title\n- Entry\n\n**Bold** and *Italic* [link](https://example.test)\n![External image](https://example.test/image.png)\n\n<script>never executed</script>\n```\ncode\n```");
    var file = root.get_child("notes.md");
    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    var item = new FileItem(file, info);
    var markdown = new MarkdownPreview();
    assert(markdown.supports(item));
    var widget = yield markdown.render(item, new Cancellable());
    assert(widget is MarkdownView);
    var markdown_view = (MarkdownView)widget;
    assert(markdown_view.rendered != null);
    var view = markdown_view.rendered;
    assert(view.buffer.text.contains("Title") && view.buffer.text.contains("never executed"));
    assert(view.buffer.text.contains("External image") && view.buffer.text.contains("https://example.test/image.png"));
    Gtk.TextIter text_start, match_start, match_end;
    view.buffer.get_start_iter(out text_start);
    assert(text_start.forward_search("Bold", Gtk.TextSearchFlags.TEXT_ONLY, out match_start, out match_end, null));
    assert(match_start.has_tag(view.buffer.get_tag_table().lookup("strong")));
    var source_view = (Gtk.TextView)((Gtk.ScrolledWindow)markdown_view.source).get_child();
    assert(source_view.buffer.text.contains("**Bold**"));
    var files = new Gee.ArrayList<File>();
    files.add(file);
    yield ArchiveService.compress(files, root.get_child("test.zip"), "zip", new Job("test"));
    var archive = root.get_child("test.zip");
    var archive_info = yield archive.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    var archive_item = new FileItem(archive, archive_info);
    var provider = new ArchivePreview();
    assert(provider.supports(archive_item));
    widget = yield provider.render(archive_item, new Cancellable());
    view = (Gtk.TextView)((Gtk.ScrolledWindow)widget).get_child();
    assert(view.buffer.text.contains("notes.md"));
    var pdf_file = root.get_child("sample.pdf");
    var surface = new Cairo.PdfSurface(pdf_file.get_path(), 200, 200);
    var cr = new Cairo.Context(surface);
    cr.move_to(20, 40);
    cr.show_text("Preview fixture");
    cr.show_page();
    surface.finish();
    var pdf_info = yield pdf_file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    var pdf_item = new FileItem(pdf_file, pdf_info);
    var pages = yield PreviewSandbox.run(pdf_item, "pdf-info", {}, new Cancellable());
    assert(pages.get_size() == 1 && pages.get_data()[0] == '1');
    var image_bytes = yield PreviewSandbox.run(pdf_item, "pdf-page", {"0", "1"}, new Cancellable());
    var texture = Gdk.Texture.from_bytes(image_bytes);
    assert(texture.get_width() == 200 && texture.get_height() == 200);
    var thumbnail = yield new ThumbnailService().texture(pdf_item, new Cancellable());
    assert(thumbnail != null && thumbnail.get_width() <= 128 && thumbnail.get_height() <= 128);
    var image_file = root.get_child("sample.png");
    var image_surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 200, 100);
    image_surface.write_to_png(image_file.get_path());
    var image_info = yield image_file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    var image_item = new FileItem(image_file, image_info);
    image_bytes = yield PreviewSandbox.run(image_item, "image", {"90"}, new Cancellable());
    texture = Gdk.Texture.from_bytes(image_bytes);
    assert(texture.get_width() == 100 && texture.get_height() == 200);
    var font_file = File.new_for_path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf");
    if(font_file.query_exists())
    {
        var font_info = yield font_file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
        var font_item = new FileItem(font_file, font_info);
        assert(new FontPreview().supports(font_item));
        image_bytes = yield PreviewSandbox.run(font_item, "font", {}, new Cancellable());
        texture = Gdk.Texture.from_bytes(image_bytes);
        assert(texture.get_width() == 1200 && texture.get_height() == 480);
    }
    var preview_cancel = new Cancellable();
    preview_cancel.cancel();
    bool preview_cancelled = false;
    try {
        yield PreviewSandbox.run(pdf_item, "pdf-page", {"0", "1"}, preview_cancel);
    }
    catch(IOError.CANCELLED e) {
        preview_cancelled = true;
    }
    assert(preview_cancelled);
    var selected = new Gee.ArrayList<FileItem>();
    selected.add(item);
    var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
    var scripts = new ScriptActions(metadata);
    assert(scripts.actions(selected).size == 0);
    bool denied = false;
    try {
        yield scripts.execute("../escape", selected, new Adw.Window());
    }
    catch(Error e) {
        denied = true;
    }
    assert(denied);
    yield OperationManager.remove_tree(root, new Cancellable());
}
void columns_test()
{
    try {
        var temp = DirUtils.make_tmp("majoris-columns-XXXXXX");
        DirUtils.create(Path.build_filename(temp, "folder"), 0700);
        FileUtils.set_contents(Path.build_filename(temp, "folder", "child.txt"), "child");
        var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
        var browser = new Browser(metadata, new Places());
        var parent = new Adw.Window();
        parent.default_width = 900;
        parent.default_height = 600;
        parent.content = browser;
        parent.present();
        var loop = new MainLoop();
        bool drilled = false;
        bool restoring = false;
        bool passed = false;
        browser.navigate(File.new_for_path(temp));
        browser.set_view("Columns");
        uint poll = Timeout.add(20, () => {
            var lists = new Gee.ArrayList<Gtk.ListView>();
            collect_lists(browser, lists);
            if(!drilled && lists.size == 1 && !browser.directory.loading)
            {
                var model = (Gtk.MultiSelection)lists[0].model;
                for(uint i = 0; i < model.get_n_items(); i++)
                    if(((FileItem)model.get_item(i)).name == "folder")
                    {
                        model.select_item(i, true);
                        drilled = true;
                        break;
                    }
            }
            else if(drilled && lists.size == 2)
            {
                var model = (Gtk.MultiSelection)lists[1].model;
                if(model.get_n_items() == 0)
                    return Source.CONTINUE;
                if(!restoring)
                    model.select_item(0, true);
                else if(browser.selected().size != 1)
                    return Source.CONTINUE;
                assert(browser.selected().size == 1 && browser.selected()[0].name == "child.txt");
                assert(browser.location.equal(File.new_for_path(Path.build_filename(temp, "folder"))));
                if(!restoring)
                {
                    string saved = browser.session_state();
                    assert(saved.has_prefix("columns-v1:"));
                    restoring = true;
                    browser.set_view("Grid");
                    browser.set_view("Columns");
                    try { browser.restore_session_state(saved);
                    }
                    catch(Error e) { error("%s", e.message);
                    }
                    return Source.CONTINUE;
                }
                passed = true;
                loop.quit();
                return Source.REMOVE;
            }
            return Source.CONTINUE;
        });
        uint watchdog = Timeout.add_seconds(10, () => { error("Column selection timed out");
            });
        loop.run();
        Source.remove(watchdog);
        assert(passed);
        browser.cancel();
        parent.destroy();
    }
    catch(Error e) {
        error("%s", e.message);
    }
}
async void merge_case(string decision) throws Error
{
    var temp = DirUtils.make_tmp("majoris-merge-XXXXXX");
    var root = File.new_for_path(temp);
    DirUtils.create_with_parents(Path.build_filename(temp, "source", "folder"), 0700);
    DirUtils.create_with_parents(Path.build_filename(temp, "destination", "folder"), 0700);
    FileUtils.set_contents(Path.build_filename(temp, "source", "folder", "new.txt"), "new");
    FileUtils.set_contents(Path.build_filename(temp, "source", "folder", "existing.txt"), "incoming");
    FileUtils.set_contents(Path.build_filename(temp, "destination", "folder", "existing.txt"), "preserved");
    if(decision == "skip-all" || decision == "replace-all")
    {
        FileUtils.set_contents(Path.build_filename(temp, "source", "folder", "second.txt"), "second incoming");
        FileUtils.set_contents(Path.build_filename(temp, "destination", "folder", "second.txt"), "second preserved");
    }
    var metadata = new MetadataStore(Path.build_filename(temp, "metadata.db"));
    var manager = new OperationManager(metadata);
    var parent = new Adw.Window();
    parent.default_width = 800;
    parent.default_height = 600;
    parent.present();
    Adw.AlertDialog? previous = null;
    uint prompts = 0;
    uint poll = Timeout.add(10, () => {
        var dialog = parent.visible_dialog as Adw.AlertDialog;
        if(dialog != null && dialog != previous)
        {
            previous = dialog;
            if(prompts++ == 0)
                dialog.response("merge");
            else if(dialog.heading == "Destination Name")
            {
                ((Gtk.Entry)dialog.extra_child).text = "renamed.txt";
                dialog.response("apply");
            }
            else dialog.response(decision);
        }
        return Source.CONTINUE;
    });
    var files = new Gee.ArrayList<File>();
    files.add(root.get_child("source/folder"));
    yield manager.run(OperationKind.MOVE, files, root.get_child("destination"), parent);
    Source.remove(poll);
    parent.destroy();
    assert(prompts == (decision == "rename" ? 3 : 2));
    var job = (Job)manager.jobs.get_item(0);
    assert(job.error == "");
    if(decision == "skip-all" || decision == "replace-all")
    {
        string first, second;
        FileUtils.get_contents(Path.build_filename(temp, "destination", "folder", "existing.txt"), out first);
        FileUtils.get_contents(Path.build_filename(temp, "destination", "folder", "second.txt"), out second);
        bool skipped = decision == "skip-all";
        assert(first == (skipped ? "preserved" : "incoming"));
        assert(second == (skipped ? "second preserved" : "second incoming"));
        assert(root.get_child("source/folder").query_exists() == skipped);
        yield OperationManager.remove_tree(root, new Cancellable());
        return;
    }
    assert(!root.get_child("source/folder").query_exists());
    string content;
    FileUtils.get_contents(Path.build_filename(temp, "destination", "folder", "existing.txt"), out content);
    assert(content == "preserved");
    assert(root.get_child(decision == "rename" ? "destination/folder/renamed.txt" : "destination/folder/existing.txt (1)").query_exists());
    manager = new OperationManager(new MetadataStore(Path.build_filename(temp, "metadata.db")));
    yield manager.undo();
    yield manager.undo();
    assert(root.get_child("source/folder/new.txt").query_exists());
    assert(root.get_child("source/folder/existing.txt").query_exists());
    assert(root.get_child("destination/folder/existing.txt").query_exists());
    yield OperationManager.remove_tree(root, new Cancellable());
}
void chooser_flow(bool save, bool multiple, bool directory, bool symlink = false)
{
    try {
        var temp = DirUtils.make_tmp("majoris-chooser-XXXXXX");
        FileUtils.set_contents(Path.build_filename(temp, "one.txt"), "one");
        FileUtils.set_contents(Path.build_filename(temp, "two.txt"), "two");
        DirUtils.create(Path.build_filename(temp, "folder"), 0700);
        if(symlink)
            File.new_for_path(Path.build_filename(temp, "linked-folder")).make_symbolic_link("folder");
        var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
        var options = new ChooserOptions(save, new VariantBuilder(VariantType.VARDICT).end());
        options.initial = File.new_for_path(temp);
        options.current_name = "Suggested.txt";
        options.multiple = multiple;
        options.directory = directory;
        var window = new ChooserWindow(options, metadata, new Places());
        var loop = new MainLoop();
        bool success = false;
        uint watchdog = Timeout.add_seconds(10, () => { error("Chooser test timed out");
                                                        return Source.REMOVE;
            });
        window.completed.connect((code, result) => { assert(code == 0);
                                                     var uris = result.lookup_value("uris", null);
                                                     assert(uris.n_children() == (multiple ? 2 : 1));
                                                     if(save)
                                                     {
                                                         assert(uris.get_child_value(0).get_string().has_suffix("Suggested.txt"));
                                                         assert(!FileUtils.test(Path.build_filename(temp, "Suggested.txt"), FileTest.EXISTS));
                                                     }
                                                     success = true;
                                                     loop.quit();
            });
        window.browser.directory.loaded.connect(() => { if(!save)
                                                        {
                                                            window.browser.selection.unselect_all();
                                                            for(uint i = 0; i < window.browser.selection.get_n_items(); i++)
                                                            {
                                                                var item = (FileItem)window.browser.selection.get_item(i);
                                                                if((directory && item.name == (symlink ? "linked-folder" : "folder")) || (!directory && (item.name == "one.txt" || (multiple && item.name == "two.txt"))))
                                                                    window.browser.selection.select_item(i, false);
                                                            }
                                                        }
                                                        window.accept_selection.begin();
            });
        loop.run();
        Source.remove(watchdog);
        assert(success);
    }
    catch(Error e) {
        error("%s", e.message);
    }
}
void initial_recovery()
{
    try {
        var temp = DirUtils.make_tmp("majoris-recovery-XXXXXX");
        var options = new ChooserOptions(false, new VariantBuilder(VariantType.VARDICT).end());
        options.initial = File.new_for_path(Path.build_filename(temp, "missing", "nested"));
        var window = new ChooserWindow(options, new MetadataStore(Path.build_filename(temp, "meta.db")), new Places());
        var loop = new MainLoop();
        bool recovered = false;
        window.browser.directory.loaded.connect(() => {
            assert(window.browser.location.equal(File.new_for_path(temp)));
            recovered = true;
            window.cancel_request();
            loop.quit();
        });
        uint watchdog = Timeout.add_seconds(10, () => { error("Initial location recovery timed out");
            });
        loop.run();
        Source.remove(watchdog);
        assert(recovered);
    }
    catch(Error e) {
        error("%s", e.message);
    }
}

void session_details_test()
{
    try {
        var temp = DirUtils.make_tmp("majoris-session-details-XXXXXX");
        var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
        var root = File.new_for_path(temp);
        for(int i = 0; i < 120; i++)
            FileUtils.set_contents(root.get_child("file-%03d.txt".printf(i)).get_path(), string.nfill(i + 1, 'x'));
        var columns = new VariantBuilder(new VariantType("a(sbi)"));
        columns.add("(sbi)", "Name", true, 240);
        columns.add("(sbi)", "Owner", true, 120);
        metadata.set_state("display:" + root.get_uri(), new Variant("(sbbib@a(sbi))", "Size", true, false, 32, true, columns.end()).print(true));
        var browser = new Browser(metadata, new Places());
        var window = new Gtk.Window();
        window.set_default_size(900, 600);
        window.child = browser;
        browser.navigate(root);
        browser.set_view("List");
        window.present();
        var query = new SearchQuery();
        query.text = "file-";
        var selected = new VariantBuilder(new VariantType("as"));
        selected.add("s", root.get_child("file-002.txt").get_uri());
        selected.add("s", root.get_child("file-100.txt").get_uri());
        var snapshot = new Variant("(sbb@asdd)", query.serialize(), false, false, selected.end(), 0.0, 400.0).print(true);
        browser.restore_session_state(snapshot);
        var loop = new MainLoop();
        Timeout.add(700, () => {
            try {
                assert(!browser.directory.loading);
                assert(browser.selected().size == 2);
                assert(((FileItem)browser.active_selection.get_item(0)).name == "file-000.txt");
                var restored = Variant.parse(new VariantType("(sbbasdd)"), browser.session_state());
                assert(SearchQuery.deserialize(restored.get_child_value(0).get_string()).text == "file-");
                assert(restored.get_child_value(3).n_children() == 2);
                assert(restored.get_child_value(5).get_double() > 300);
                browser.set_sort("Created", false);
                var display = Variant.parse(new VariantType("(sbbiba(sbi))"), metadata.state("display:" + root.get_uri()));
                assert(display.get_child_value(0).get_string() == "Created");
                assert(!display.get_child_value(1).get_boolean());
                assert(display.get_child_value(3).get_int32() == 32);
                assert(display.get_child_value(4).get_boolean());
                bool owner_found = false;
                var saved_columns = display.get_child_value(5);
                for(size_t i = 0; i < saved_columns.n_children(); i++)
                {
                    var column = saved_columns.get_child_value(i);
                    if(column.get_child_value(0).get_string() == "Owner")
                    {
                        assert(column.get_child_value(1).get_boolean());
                        assert(column.get_child_value(2).get_int32() == 120);
                        owner_found = true;
                    }
                }
                assert(owner_found);
                browser.register_column(new FixtureColumn());
                browser.set_sort("Byte Count", false);
                assert(((FileItem)browser.active_selection.get_item(0)).name == "file-119.txt");
                bool duplicate_rejected = false;
                try { browser.register_column(new FixtureColumn());
                }
                catch(MajorisFiles.FileError.INVALID e) { duplicate_rejected = true;
                }
                assert(duplicate_rejected);
                metadata.set_tags(root.get_child("file-000.txt"), "alpha");
                metadata.set_tags(root.get_child("file-119.txt"), "beta");
                browser.set_group("Tags");
                assert(metadata.state("group:" + root.get_uri()) == "Tags");
                assert(((FileItem)browser.active_selection.get_item(0)).name == "file-000.txt");
                assert(((FileItem)browser.active_selection.get_item(1)).name == "file-119.txt");
                var sections = browser.active_selection as Gtk.SectionModel;
                uint start, end;
                sections.get_section(0, out start, out end);
                assert(start == 0 && end == 1);
                browser.set_group("None");
                assert(((FileItem)browser.active_selection.get_item(0)).name == "file-119.txt");
                browser.cancel();
                window.destroy();
                loop.quit();
            }
            catch(Error e) { error("%s", e.message);
            }
            return Source.REMOVE;
        });
        loop.run();
    }
    catch(Error e) {
        error("%s", e.message);
    }
}

void disk_image_inventory_test()
{
    var objects = new VariantBuilder(new VariantType("a{oa{sa{sv}}}"));
    var interfaces = new VariantBuilder(new VariantType("a{sa{sv}}"));
    var backing = new VariantBuilder(VariantType.VARDICT);
    backing.add("{sv}", "BackingFile", new Variant.bytestring("/tmp/image.iso"));
    interfaces.add("{s@a{sv}}", "org.freedesktop.UDisks2.Loop", backing.end());
    var filesystem = new VariantBuilder(VariantType.VARDICT);
    filesystem.add("{sv}", "MountPoints", new VariantBuilder(new VariantType("aay")).end());
    var properties = filesystem.end();
    interfaces.add("{s@a{sv}}", "org.freedesktop.UDisks2.Filesystem", properties);
    string loop = "/org/freedesktop/UDisks2/block_devices/loop0";
    objects.add("{o@a{sa{sv}}}", loop, interfaces.end());
    for(int i = 1; i <= 2; i++)
    {
        var partition_interfaces = new VariantBuilder(new VariantType("a{sa{sv}}"));
        var partition = new VariantBuilder(VariantType.VARDICT);
        partition.add("{sv}", "Table", new Variant.object_path(i == 1 ? loop : "/org/freedesktop/UDisks2/block_devices/other"));
        partition_interfaces.add("{s@a{sv}}", "org.freedesktop.UDisks2.Partition", partition.end());
        partition_interfaces.add("{s@a{sv}}", "org.freedesktop.UDisks2.Filesystem", properties);
        objects.add("{o@a{sa{sv}}}", loop + "p" + i.to_string(), partition_interfaces.end());
    }
    var inventory = objects.end();
    assert(DiskImages.find_loop(inventory, File.new_for_path("/tmp/image.iso")) == loop);
    assert(DiskImages.find_loop(inventory, File.new_for_path("/tmp/other.iso")) == null);
    var devices = DiskImages.filesystems(inventory, loop);
    assert(devices.size == 2 && devices[0] == loop && devices[1] == loop + "p1");
    var info = new FileInfo();
    info.set_name("image.iso");
    info.set_display_name("image.iso");
    info.set_file_type(FileType.REGULAR);
    info.set_is_symlink(false);
    var selection = new Gee.ArrayList<FileItem>();
    selection.add(new FileItem(File.new_for_path("/tmp/image.iso"), info));
    var provider = new DiskImageActions();
    assert(provider.actions(selection).size == 2);
    selection.add(selection[0]);
    assert(provider.actions(selection).size == 0);
}

class FixtureColumn : Object, ColumnProvider {
    public string title {
        owned get {
            return "Byte Count";
        }
    }
    public string text(FileItem item, MetadataStore metadata)
    {
        return item.bytes.to_string();
    }
    public int compare(FileItem first, FileItem second, MetadataStore metadata)
    {
        return first.bytes < second.bytes ? -1 : first.bytes == second.bytes ? 0 : 1;
    }
}

void bookmark_drop_test()
{
    var loop = new MainLoop();
    bookmark_drop_flow.begin((obj, res) => { bookmark_drop_flow.end(res);
                                             loop.quit();
        });
    loop.run();
}
async void bookmark_drop_flow()
{
    try {
        var root = DirUtils.make_tmp("majoris-drop-XXXXXX");
        var a = File.new_for_path(root).get_child("a");
        var b = File.new_for_path(root).get_child("b");
        var c = File.new_for_path(root).get_child("c");
        a.make_directory();
        b.make_directory();
        c.make_directory();
        var places = new Places();
        yield places.add_bookmark(a);
        yield places.add_bookmark(b);
        yield places.add_bookmark(c);
        yield places.edit_bookmark(a, "A label with spaces");
        yield places.reorder_bookmark(c, a, false);
        yield places.reorder_bookmark(a, b, true);
        var ordered = new Gee.ArrayList<Place>();
        foreach(var place in places.entries)
            if(place.bookmark)
                ordered.add(place);
        assert(ordered.size == 3);
        assert(ordered[0].file.equal(c) && ordered[1].file.equal(b) && ordered[2].file.equal(a));
        assert(ordered[2].label == "A label with spaces");
        bool rejected = false;
        try {
            yield places.reorder_bookmark(a, File.new_for_path(root).get_child("missing"), false);
        }
        catch(MajorisFiles.FileError.INVALID e) {
            rejected = true;
        }
        assert(rejected);
        var sources = new Gee.ArrayList<File>();
        sources.add(a);
        sources.add(b);
        assert(yield DropPolicy.same_filesystem(sources, c));
        sources.add(File.new_for_uri("sftp://example.invalid/file"));
        assert(!(yield DropPolicy.same_filesystem(sources, c)));
        yield places.edit_bookmark(a, null, true);
        yield places.edit_bookmark(b, null, true);
        yield places.edit_bookmark(c, null, true);
    }
    catch(Error e) {
        error("%s", e.message);
    }
}
