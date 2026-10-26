using MajorisFiles;
[CCode(cname="majoris_playback_new",cheader_filename="src/preview/playback.h")]
extern Gtk.MediaStream fixture_playback(Subprocess process,bool output);
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
    Test.add_func("/sharing/inventory-parser", () => {
        try {
            var shares = ShareRecord.parse("[Projects]\npath=/home/alice/Projects\ncomment=Work\nusershare_acl=Everyone:R\nguest_ok=n\n\n[Team]\npath=/srv/team\nusershare_acl=alice:F,bob:F\nguest_ok=y\n");
            assert(shares.size == 2);
            assert(shares[0].name == "Projects" && !shares[0].writable && !shares[0].guest);
            assert(shares[1].path == "/srv/team" && shares[1].writable && shares[1].guest);
            assert(shares[1].address.has_suffix("/Team"));
            assert(ShareRecord.parse("").size == 0);
            var policy = SharePolicy.parse_acl("alice:F,bob:R,carol:D");
            assert(policy["alice"] == "F" && policy["bob"] == "R" && policy["carol"] == "D");
            assert(SharePolicy.mixed_acl(policy).has_prefix("carol:D,"));
            bool rejected = false;
            try { ShareRecord.parse("[Bad]\npath=relative\nusershare_acl=Everyone:F\nguest_ok=n\n"); }
            catch (Error e) { rejected = true; }
            assert(rejected);
        }
        catch (Error e) { error("%s", e.message); }
    });
    Test.add_func("/ui/open-single", () => chooser_flow(false, false, false));
    Test.add_func("/ui/system-drive-navigation",()=>{
        try {
            string root=DirUtils.make_tmp("majoris-root-navigation-XXXXXX");
            var browser=new Browser(new MetadataStore(Path.build_filename(root,"metadata.db")),new Places());
            assert_sidebar_structure(browser);
            var sidebar=sidebar_widget(browser);Gtk.ListBoxRow? target=null;
            for(int i=0;i<browser.places.entries.size;i++)if(browser.places.entries[i].system)target=sidebar.get_row_at_index(i);
            assert(target!=null);sidebar.row_activated(target);
            assert(browser.location.equal(File.new_for_path("/")));
            assert(!browser.location.equal(File.new_for_path(Environment.get_home_dir())));
            browser.cancel();
        }catch(Error e){error("%s",e.message);}
    });
    Test.add_func("/preview/persistent-rotation", () => {
        var loop = new MainLoop();
        rotation_case.begin((obj, res) => { try { rotation_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        uint timer = Timeout.add_seconds(30, () => { error("Persistent rotation fixture timed out"); });
        loop.run(); Source.remove(timer);
    });
    Test.add_func("/preview/isolated-codec-playback",()=>{
        var loop=new MainLoop();playback_case.begin((obj,res)=>{try{playback_case.end(res);}catch(Error e){error("%s",e.message);}loop.quit();});
        uint watchdog=Timeout.add_seconds(100,()=>{error("Isolated playback fixture timed out");});loop.run();Source.remove(watchdog);
    });
    Test.add_func("/ui/grid-grouped-model",()=>{
        var store=new GLib.ListStore(typeof(FileItem));
        for(int i=0;i<1000;i++){var info=new FileInfo();info.set_name("file-%04d".printf(i));info.set_display_name(info.get_name());info.set_file_type(FileType.REGULAR);store.append(new FileItem(File.new_for_path("/fixture/"+info.get_name()),info));}
        var sorted=new Gtk.SortListModel(store,null);
        sorted.section_sorter=new Gtk.CustomSorter((a,b)=>(((FileItem)a).name.collate("file-0500")<0?0:1)-(((FileItem)b).name.collate("file-0500")<0?0:1));
        var selection=new Gtk.MultiSelection(sorted);var rows=new GridRows(sorted);
        assert(rows.get_n_items()==252);assert(((GridRow)rows.get_item(0)).heading);assert(((GridRow)rows.get_item(126)).heading);
        var first=new GridSlice(selection,0,4);var second=new GridSlice(selection,500,4);
        first.select_item(1,true);second.select_item(2,false);assert(selection.is_selected(1)&&selection.is_selected(502));
        second.select_all();assert(selection.get_selection().get_size()==1000);
        first.unselect_all();assert(selection.get_selection().is_empty());
        rows.resize(3);assert(rows.get_n_items()==336&&rows.row_for(500)==169);
        store.remove(0);assert(rows.get_n_items()==336);
        first.detach();second.detach();rows.detach();
    });
    Test.add_func("/ui/grid-headings-and-keyboard",()=>{var loop=new MainLoop();grouped_grid_case.begin((obj,res)=>{try{grouped_grid_case.end(res);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    Test.add_func("/preview/media-and-office-rendering", () => {
        var loop = new MainLoop();
        rich_preview_case.begin((obj, res) => {
            try { rich_preview_case.end(res); } catch (Error e) { error("%s", e.message); }
            loop.quit();
        });
        uint watchdog = Timeout.add_seconds(90, () => { error("Rich preview fixtures timed out"); });
        loop.run();
        Source.remove(watchdog);
    });
    Test.add_func("/ui/adaptive-sidebar", () => {
        try {
            var root = DirUtils.make_tmp("majoris-adaptive-XXXXXX");
            var metadata = new MetadataStore(Path.build_filename(root, "state.db"));
            var options = new ChooserOptions(false, new VariantBuilder(VariantType.VARDICT).end());
            options.initial = File.new_for_path(root);
            var window = new ChooserWindow(options, metadata, new Places());
            window.set_default_size(500, 660);
            window.present();
            var loop = new MainLoop();
            int stage = 0;
            uint poll = Timeout.add(50, () => {
                if (stage == 0 && window.browser.narrow)
                {
                    var overlay = find_overlay(window.browser);
                    assert(overlay != null && overlay.collapsed && overlay.sidebar != null);
                    overlay.show_sidebar = true;
                    assert(overlay.show_sidebar);
                    window.browser.navigate(File.new_for_path(root));
                    assert(!overlay.show_sidebar);
                    Timeout.add(100, () => { window.set_default_size(960, 660); return Source.REMOVE; });
                    stage = 1;
                }
                else if (stage == 1 && !window.browser.narrow)
                {
                    var overlay = find_overlay(window.browser);
                    // The empty overlay stays collapsed in wide mode so it
                    // cannot reserve a second sidebar beside the Paned child.
                    assert(overlay != null && overlay.collapsed && overlay.sidebar == null);
                    window.cancel_request();
                    loop.quit();
                    return Source.REMOVE;
                }
                return Source.CONTINUE;
            });
            uint watchdog = Timeout.add_seconds(10, () => { error("Adaptive sidebar transition timed out: stage=%d window=%d browser=%d", stage, window.get_width(), window.browser.get_width()); });
            loop.run();
            Source.remove(watchdog);
            assert(poll > 0 && stage == 1);
        }
        catch (Error e) { error("%s", e.message); }
    });
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
    Test.add_func("/ui/nearby-confirm", () => nearby_test(true));
    Test.add_func("/ui/nearby-cancel", () => nearby_test(false));
    Test.add_func("/ui/drop-policy", () => drop_policy_test());
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
Adw.OverlaySplitView? find_overlay(Gtk.Widget widget)
{
    if (widget is Adw.OverlaySplitView)
        return (Adw.OverlaySplitView)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling())
    {
        var found = find_overlay(child);
        if (found != null)
            return found;
    }
    return null;
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
GtkSource.View? find_source_view(Gtk.Widget widget)
{
    if (widget is GtkSource.View) return (GtkSource.View)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = find_source_view(child);
        if (found != null) return found;
    }
    return null;
}
async void rich_preview_case() throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-rich-preview-XXXXXX"));
    var token = new Cancellable();
    var gif = root.get_child("animated.gif");
    yield gif.replace_contents_async(Base64.decode("R0lGODlhAQABAIAAAAAAAP///yH5BAAKAAAALAAAAAABAAEAAAICRAEAIfkEAAoAAAAsAAAAAAEAAQAAAgJMAQA7"), null, false, FileCreateFlags.PRIVATE, token, null);
    var gif_info = yield gif.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
    var gif_item = new FileItem(gif, gif_info);
    var frames = yield PreviewSandbox.run(gif_item, "image-animation", {}, token);
    var parser = new Json.Parser(); parser.load_from_data((string)frames.get_data(), (ssize_t)frames.get_size());
    var gif_frames = parser.get_root().get_array();
    assert(gif_frames.get_length() >= 2);
    bool distinct = false;
    foreach (var frame in gif_frames.get_elements())
        if (frame.get_object().get_string_member("png") != gif_frames.get_object_element(0).get_string_member("png")) distinct = true;
    assert(distinct);
    var animation = yield new ImagePreview().render(gif_item, token);
    assert(animation is AnimatedImageView);
    string? gst = Environment.find_program_in_path("gst-launch-1.0");
    if (gst != null) {
        var video = root.get_child("sample.ogv");
        var generator = new Subprocess.newv({gst, "-q", "videotestsrc", "num-buffers=30", "!", "video/x-raw,width=160,height=90,framerate=10/1", "!", "videoconvert", "!", "theoraenc", "!", "oggmux", "!", "filesink", "location=" + video.get_path()}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
        yield generator.wait_check_async(token);
        var info = yield video.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
        var item = new FileItem(video, info);
        Test.message("Discovering media fixture %s", video.get_path());
        var fields = yield RichMetadata.load(item, token);
        assert(fields["Resolution"] == "160 × 90" && fields.has_key("Video Codec"));
        Test.message("Rendering video thumbnail");
        var png = yield new VideoThumbnail().render(item, token);
        var texture = Gdk.Texture.from_bytes(png);
        assert(texture.get_width() <= 128 && texture.get_height() <= 128);
    } else Test.message("Media fixture generator unavailable; media fixture not executed");
    if (FileUtils.test("/usr/bin/soffice", FileTest.IS_EXECUTABLE)) {
        var content = root.get_child("content.xml");
        FileUtils.set_contents(content.get_path(), "<?xml version=\"1.0\"?><office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" office:version=\"1.2\"><office:body><office:text><text:p>Formatted Majoris document fixture</text:p></office:text></office:body></office:document-content>");
        FileUtils.set_contents(root.get_child("mimetype").get_path(), "application/vnd.oasis.opendocument.text");
        var files = new Gee.ArrayList<File>(); files.add(content); files.add(root.get_child("mimetype"));
        var meta = root.get_child("META-INF"); yield meta.make_directory_async(Priority.DEFAULT, token);
        FileUtils.set_contents(meta.get_child("manifest.xml").get_path(), "<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\"><manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.text\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>");
        files.add(meta);
        var document = root.get_child("sample.odt");
        yield ArchiveService.compress(files, document, "zip", new Job("Office fixture"));
        var info = yield document.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
        var item = new FileItem(document, info);
        Test.message("Rendering Office fixture %s", document.get_path());
        var pdf = yield PreviewSandbox.run(item, "office-pdf", {}, token);
        assert(pdf.get_size() > 100 && ((string)pdf.get_data()).has_prefix("%PDF-"));
        var view = yield new OfficePreview().render(item, token);
        assert(view is PdfView);
        var word = root.get_child("word"); yield word.make_directory_async(Priority.DEFAULT, token);
        var rels = root.get_child("_rels"); yield rels.make_directory_async(Priority.DEFAULT, token);
        FileUtils.set_contents(word.get_child("document.xml").get_path(), """<?xml version="1.0"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:rPr><w:b/><w:color w:val="245AB8"/><w:sz w:val="36"/></w:rPr><w:t>Formatted Majoris DOCX</w:t></w:r></w:p><w:tbl><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="8"/><w:bottom w:val="single" w:sz="8"/></w:tblBorders></w:tblPr><w:tblGrid><w:gridCol w:w="4000"/></w:tblGrid><w:tr><w:tc><w:p><w:r><w:t>Table content</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:r><w:br w:type="page"/><w:t>Second page</w:t></w:r></w:p><w:sectPr><w:pgSz w:w="12240" w:h="15840"/></w:sectPr></w:body></w:document>""");
        FileUtils.set_contents(root.get_child("[Content_Types].xml").get_path(), """<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>""");
        FileUtils.set_contents(rels.get_child(".rels").get_path(), """<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>""");
        var entries = new Gee.ArrayList<File>(); entries.add(word); entries.add(rels); entries.add(root.get_child("[Content_Types].xml"));
        var docx = root.get_child("formatted.docx"); yield ArchiveService.compress(entries, docx, "zip", new Job("DOCX fixture"));
        var docx_info = yield docx.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
        var docx_pdf = yield PreviewSandbox.run(new FileItem(docx, docx_info), "office-pdf", {}, token);
        var rendered = new Poppler.Document.from_bytes(docx_pdf, null);
        assert(rendered.get_n_pages() == 2);
        assert(rendered.get_page(0).get_text().contains("Formatted Majoris DOCX"));
        assert(rendered.get_page(1).get_text().contains("Second page"));
    } else Test.message("LibreOffice not installed; Office rendering fixture not executed");
    token.cancel();
    yield OperationManager.remove_tree(root, new Cancellable());
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
    var source_view = find_source_view(markdown_view.source);
    assert(source_view != null && source_view.show_line_numbers && !source_view.editable);
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
    var cached_thumbnail = yield new ThumbnailService().texture(pdf_item, new Cancellable());
    assert(cached_thumbnail != null && cached_thumbnail.get_width() == thumbnail.get_width());
    var comparison_copy = root.get_child("comparison.pdf");
    yield pdf_file.copy_async(comparison_copy, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    var comparison = new Adw.AlertDialog("Conflict fixture", null);
    ConflictThumbnails.attach(comparison, pdf_file, comparison_copy, new MetadataStore(root.get_child("conflict-state.db").get_path()));
    var previews = (Gtk.Box)comparison.extra_child;
    var first_preview = (Gtk.Picture)previews.get_first_child().get_first_child();
    var second_preview = (Gtk.Picture)previews.get_last_child().get_first_child();
    for (int i = 0; i < 100 && (first_preview.paintable == null || second_preview.paintable == null); i++) {
        Timeout.add(20, () => { preview_case.callback(); return Source.REMOVE; }); yield;
    }
    assert(first_preview.paintable != null && second_preview.paintable != null);
    assert(first_preview.alternative_text != second_preview.alternative_text);
    string cache_name = Checksum.compute_for_string(ChecksumType.MD5, pdf_item.file.get_uri()) + ".png";
    FileUtils.set_contents(Path.build_filename(Environment.get_user_cache_dir(), "thumbnails", "normal", cache_name), "corrupted thumbnail");
    cached_thumbnail = yield new ThumbnailService().texture(pdf_item, new Cancellable());
    assert(cached_thumbnail != null);
    var thumbnail_settings = new MetadataStore(root.get_child("thumbnail-settings.db").get_path());
    thumbnail_settings.set_state("thumbnail-policy", "Never");
    assert((yield new ThumbnailService(thumbnail_settings).texture(pdf_item, new Cancellable())) == null);
    yield root.get_child("word").make_directory_async(Priority.DEFAULT, null);
    FileUtils.set_contents(root.get_child("word/document.xml").get_path(), "<w:document xmlns:w='urn:fixture'><w:p><w:r><w:t>Office café &amp; text</w:t></w:r></w:p></w:document>");
    var office_sources = new Gee.ArrayList<File>();
    office_sources.add(root.get_child("word"));
    var office_file = root.get_child("sample.docx");
    yield ArchiveService.compress(office_sources, office_file, "zip", new Job("Office fixture"));
    var office_info = yield office_file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    office_info.set_content_type("application/vnd.openxmlformats-officedocument.wordprocessingml.document");
    var office_item = new FileItem(office_file, office_info);
    var office_provider = new OfficePreview();
    assert(office_provider.supports(office_item));
    var office_widget = (Gtk.Box)(yield office_provider.render(office_item, new Cancellable()));
    var office_text = (Gtk.TextView)((Gtk.ScrolledWindow)office_widget.get_last_child()).child;
    assert(office_text.buffer.text.contains("Office café & text"));
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
        var font_thumbnail = yield new ThumbnailService().texture(font_item, new Cancellable());
        assert(font_thumbnail != null && font_thumbnail.get_width() <= 128);
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
        assert_sidebar_structure(window.browser);
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

void drop_policy_test()
{
    var loop = new MainLoop();
    drop_policy_flow.begin((obj, res) => { drop_policy_flow.end(res);
                                             loop.quit();
        });
    loop.run();
}
async void drop_policy_flow()
{
    try {
        var root = DirUtils.make_tmp("majoris-drop-XXXXXX");
        var a = File.new_for_path(root).get_child("a");
        var b = File.new_for_path(root).get_child("b");
        var c = File.new_for_path(root).get_child("c");
        a.make_directory();
        b.make_directory();
        c.make_directory();
        var sources = new Gee.ArrayList<File>();
        sources.add(a);
        sources.add(b);
        assert(yield DropPolicy.same_filesystem(sources, c));
        sources.add(File.new_for_uri("sftp://example.invalid/file"));
        assert(!(yield DropPolicy.same_filesystem(sources, c)));
    }
    catch(Error e) {
        error("%s", e.message);
    }
}

class FixtureNearby : Object, NearbyShareProvider {
    public bool sent;
    public string provider_id {
        owned get {
            return "fixture";
        }
    }
    public bool supports(Gee.List<FileItem> selection)
    {
        return selection.size == 1;
    }
    public async Gee.List<NearbyPeer> discover(Cancellable token) throws Error
    {
        token.set_error_if_cancelled();
        var peers = new Gee.ArrayList<NearbyPeer>();
        peers.add(new NearbyPeer("test-device", "Test Device"));
        return peers;
    }
    public async void send(string peer_id, Gee.List<File> files, Cancellable token) throws Error
    {
        token.set_error_if_cancelled();
        assert(peer_id == "test-device" && files.size == 1);
        sent = true;
    }
}
void nearby_test(bool confirm)
{
    var loop = new MainLoop();
    nearby_flow.begin(confirm, (obj, res) => { try { nearby_flow.end(res);
                                               }
                                               catch(Error e) { error("%s", e.message);
                                               }
                                               loop.quit();
        });
    uint watchdog = Timeout.add_seconds(10, () => { error("Nearby provider flow timed out");
        });
    loop.run();
    Source.remove(watchdog);
}
async void nearby_flow(bool confirm) throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-nearby-XXXXXX"));
    var file = root.get_child("attachment.txt");
    FileUtils.set_contents(file.get_path(), "test attachment");
    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    var items = new Gee.ArrayList<FileItem>();
    items.add(new FileItem(file, info));
    var provider = new FixtureNearby();
    var actions = new NearbyActions(provider);
    assert(actions.actions(items).size == 1);
    assert(new DesktopActions().actions(items).size == 1);
    var parent = new Adw.Window();
    parent.set_default_size(700, 500);
    parent.present();
    uint poll = Timeout.add(10, () => {
        var dialog = parent.visible_dialog as Adw.AlertDialog;
        if(dialog != null)
            dialog.response(confirm ? "send" : "cancel");
        return Source.CONTINUE;
    });
    yield actions.execute("send", items, parent);
    Source.remove(poll);
    parent.destroy();
    assert(provider.sent == confirm);
    yield OperationManager.remove_tree(root, new Cancellable());
}

async void rotation_case() throws Error {
    var root = File.new_for_path(DirUtils.make_tmp("majoris-rotation-XXXXXX"));
    var token = new Cancellable();
    foreach (var format in new string[] {"png", "jpeg"}) {
        var file = root.get_child("image." + format);
        var pixbuf = new Gdk.Pixbuf(Gdk.Colorspace.RGB, format == "png", 8, 32, 16); pixbuf.fill(0x33669980);
        pixbuf.savev(file.get_path(), format, {}, {});
        var original = yield SplitService.checksum(file, ChecksumType.SHA256, token);
        var metadata = new MetadataStore(root.get_child(format + ".db").get_path()); metadata.set_tags(file, "rotation fixture");
        var manager = new OperationManager(metadata);
        var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
        yield ImageRotation.rotate(new FileItem(file, info), true, manager);
        var rotated = new Gdk.Pixbuf.from_file(file.get_path()); assert(rotated.width == 16 && rotated.height == 32);
        string rendered = yield SplitService.checksum(file, ChecksumType.SHA256, token);
        assert(rendered != original && metadata.tags(file) == "rotation fixture");
        manager = new OperationManager(new MetadataStore(root.get_child(format + ".db").get_path()));
        yield manager.undo(); assert((yield SplitService.checksum(file, ChecksumType.SHA256, token)) == original);
        manager = new OperationManager(new MetadataStore(root.get_child(format + ".db").get_path()));
        yield manager.redo(); assert((yield SplitService.checksum(file, ChecksumType.SHA256, token)) == rendered);
        info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
        yield ImageRotation.rotate(new FileItem(file, info), false, manager);
        var restored = new Gdk.Pixbuf.from_file(file.get_path()); assert(restored.width == 32 && restored.height == 16);
        yield manager.undo(); assert((yield SplitService.checksum(file, ChecksumType.SHA256, token)) == rendered);
        var append = yield file.append_to_async(FileCreateFlags.NONE, Priority.DEFAULT, token);
        size_t written; yield append.write_all_async("external".data, Priority.DEFAULT, token, out written); yield append.close_async(Priority.DEFAULT, token);
        bool refused = false; try { yield manager.undo(); } catch (MajorisFiles.FileError.CONFLICT e) { refused = true; }
        assert(refused);
    }
    var odd = root.get_child("odd.jpeg");
    var pixbuf = new Gdk.Pixbuf(Gdk.Colorspace.RGB, false, 8, 31, 17); pixbuf.fill(0x884422ffU); pixbuf.savev(odd.get_path(), "jpeg", {}, {});
    string before = yield SplitService.checksum(odd, ChecksumType.SHA256, token);
    var manager = new OperationManager(new MetadataStore(root.get_child("odd.db").get_path()));
    var info = yield odd.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
    bool rejected = false; try { yield ImageRotation.rotate(new FileItem(odd, info), true, manager); } catch (IOError.NOT_SUPPORTED e) { rejected = true; }
    assert(rejected && (yield SplitService.checksum(odd, ChecksumType.SHA256, token)) == before);
    yield ImageRotation.rotate(new FileItem(odd, info), true, manager, null, true);
    var rotated = new Gdk.Pixbuf.from_file(odd.get_path()); assert(rotated.width == 17 && rotated.height == 31);
    yield manager.undo(); assert((yield SplitService.checksum(odd, ChecksumType.SHA256, token)) == before);
    yield OperationManager.remove_tree(root, token);
}
async void playback_case() throws Error {
    var root=File.new_for_path(DirUtils.make_tmp("majoris-playback-XXXXXX"));
    string[] names={"mp4","hevc.mkv","webm","mkv","mp3","aac","flac","opus"};
    string[] encoders={"x264enc","x265enc","vp8enc","vp8enc","lamemp3enc","avenc_aac","flacenc","opusenc"};
    string[] tails={"x264enc tune=zerolatency ! h264parse ! mp4mux","x265enc option-string=pools=1:frame-threads=1 ! h265parse ! matroskamux","vp8enc deadline=1 ! webmmux","vp8enc deadline=1 ! matroskamux","lamemp3enc ! id3v2mux","avenc_aac ! aacparse ! audio/mpeg,mpegversion=4,stream-format=adts","flacenc","opusenc ! oggmux"};
    for(int index=0;index<names.length;index++){
        var probe=new Subprocess.newv({"gst-inspect-1.0",encoders[index]},SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_SILENCE);yield probe.wait_async(null);
        if(!probe.get_successful()){Test.message("Unverified codec %s: fixture encoder unavailable",names[index]);continue;}
        var file=root.get_child("sample."+names[index]);
        string prefix=index<4?"videotestsrc num-buffers=30 ! video/x-raw,width=160,height=90,framerate=10/1 ! videoconvert ! ":"audiotestsrc num-buffers=130 ! audioconvert ! audioresample ! ";
        string pipeline=prefix+tails[index]+" ! filesink location="+file.get_path();
        string[] args={"gst-launch-1.0","-q"};foreach(var arg in pipeline.split(" "))args+=arg;
        var generator=new Subprocess.newv(args,SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_SILENCE);yield generator.wait_check_async(null);
        var info=yield file.query_info_async(FileItem.ATTRIBUTES,FileQueryInfoFlags.NONE,Priority.DEFAULT,null);
        var token=new Cancellable();var stream=IsolatedPlayback.open(new FileItem(file,info),token,false);
        for(int i=0;i<750&&!stream.is_prepared()&&stream.get_error()==null;i++){Timeout.add(20,()=>{playback_case.callback();return Source.REMOVE;});yield;}
        if(stream.get_error()!=null)throw new IOError.FAILED("%s: %s".printf(names[index],stream.get_error().message));
        assert(stream.is_prepared()&&stream.get_duration()>1000000);
        assert(index<4?stream.has_video:stream.has_audio);stream.set_volume(0.35);stream.play();
        for(int i=0;i<200&&stream.get_timestamp()<200000&&stream.get_error()==null;i++){Timeout.add(20,()=>{playback_case.callback();return Source.REMOVE;});yield;}
        if(stream.get_error()!=null)throw new IOError.FAILED("%s playback: %s".printf(names[index],stream.get_error().message));
        assert(stream.get_timestamp()>=200000);
        if(index<4)assert(((Gdk.Paintable)stream).get_intrinsic_width()==160);else assert(IsolatedPlayback.audio_bytes(stream)>0);
        stream.pause();assert(!stream.get_playing());
        if(stream.is_seekable()){
            stream.seek(1000000);
            for(int i=0;i<200&&stream.is_seeking();i++){Timeout.add(20,()=>{playback_case.callback();return Source.REMOVE;});yield;}
            assert(!stream.is_seeking()&&stream.get_error()==null);
        }
        token.cancel();Test.message("PASS actual isolated decode/play/pause/seek: %s",names[index]);
    }
    var corrupt=root.get_child("corrupt.mp4");FileUtils.set_contents(corrupt.get_path(),"Not a video");
    var info=yield corrupt.query_info_async(FileItem.ATTRIBUTES,FileQueryInfoFlags.NONE,Priority.DEFAULT,null);var token=new Cancellable();
    var stream=IsolatedPlayback.open(new FileItem(corrupt,info),token,false);
    for(int i=0;i<750&&stream.get_error()==null;i++){Timeout.add(20,()=>{playback_case.callback();return Source.REMOVE;});yield;}
    assert(stream.get_error()!=null&&!stream.get_playing());token.cancel();
    var broken=new Subprocess.newv({"/usr/bin/python3","-c","import struct,sys;sys.stdout.buffer.write(struct.pack('<II',86,4294967295));sys.stdout.flush()"},SubprocessFlags.STDIN_PIPE|SubprocessFlags.STDOUT_PIPE|SubprocessFlags.STDERR_SILENCE);
    stream=fixture_playback(broken,false);
    for(int i=0;i<100&&stream.get_error()==null;i++){Timeout.add(20,()=>{playback_case.callback();return Source.REMOVE;});yield;}
    assert(stream.get_error()!=null);IsolatedPlayback.close(stream);
    yield OperationManager.remove_tree(root,new Cancellable());
}
Gtk.Widget? find_grouped_grid(Gtk.Widget widget){
    if(widget is Gtk.ListView){var model=((Gtk.ListView)widget).model as Gtk.NoSelection;if(model!=null&&model.model is GridRows)return widget;}
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=find_grouped_grid(child);if(found!=null)return found;}return null;
}
uint count_headings(Gtk.Widget widget){uint count=widget is Gtk.Label&&widget.has_css_class("heading")?1u:0u;for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())count+=count_headings(child);return count;}
Gtk.EventControllerKey? find_grid_keys(Gtk.Widget widget){
    if(widget is Gtk.Box&&widget.get_first_child() is Gtk.Overlay){var controllers=widget.observe_controllers();for(uint i=0;i<controllers.get_n_items();i++){var key=controllers.get_item(i) as Gtk.EventControllerKey;if(key!=null&&key.propagation_phase==Gtk.PropagationPhase.CAPTURE)return key;}}
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var key=find_grid_keys(child);if(key!=null)return key;}return null;
}
async void grouped_grid_case() throws Error {
    var temporary=File.new_for_path(DirUtils.make_tmp("majoris-grid-ui-XXXXXX"));var root=temporary.get_child("files");yield root.make_directory_async(Priority.DEFAULT,null);
    for(int i=0;i<2;i++){FileUtils.set_contents(root.get_child("text-%d.txt".printf(i)).get_path(),"Fixture text");var image=new Gdk.Pixbuf(Gdk.Colorspace.RGB,false,8,16,16);image.fill(0x336699ffU);image.savev(root.get_child("image-%d.png".printf(i)).get_path(),"png",{},{});}
    for(int i=0;i<4;i++)yield root.get_child("folder-%d".printf(i)).make_directory_async(Priority.DEFAULT,null);
    var metadata=new MetadataStore(temporary.get_child("state.db").get_path());metadata.set_state("thumbnail-policy","Never");
    var browser=new Browser(metadata,new Places(metadata));var window=new Gtk.Window();window.set_default_size(900,650);window.child=browser;browser.navigate(root);browser.set_group("Type");window.present();
    Gtk.Widget? grouped=null;Gtk.EventControllerKey? keys=null;
    for(int attempt=0;attempt<200;attempt++){
        grouped=find_grouped_grid(browser);if(grouped!=null)keys=find_grid_keys(grouped);
        if(!browser.directory.loading&&count_headings(grouped??browser)>=2&&keys!=null)break;
        Timeout.add(20,()=>{grouped_grid_case.callback();return Source.REMOVE;});yield;
    }
    assert(grouped!=null&&keys!=null&&count_headings(grouped)==3&&browser.active_selection.get_n_items()==8);
    var cells=keys.get_widget().get_ancestor(typeof(Gtk.GridView));Graphene.Rect bounds;assert(cells.compute_bounds(browser,out bounds));assert(bounds.origin.x+bounds.size.width<=browser.get_width()+1);
    bool handled=false;Signal.emit_by_name(keys,"key-pressed",Gdk.Key.End,0u,Gdk.ModifierType.SHIFT_MASK,out handled);assert(handled&&browser.selected().size==8);
    Signal.emit_by_name(keys,"key-pressed",Gdk.Key.Home,0u,(Gdk.ModifierType)0,out handled);assert(handled&&browser.selected().size==1&&browser.active_selection.is_selected(0));
    File selected=browser.selected()[0].file;browser.set_group("Size");assert(browser.selected().size==1&&browser.selected()[0].file.equal(selected));
    browser.cancel();window.destroy();yield OperationManager.remove_tree(temporary,new Cancellable());
}
Gtk.ListBox? sidebar_widget(Gtk.Widget widget) {
    if(widget is Gtk.ListBox && widget.has_css_class("files-sidebar"))return (Gtk.ListBox)widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=sidebar_widget(child);if(found!=null)return found;}
    return null;
}
void assert_sidebar_structure(Browser browser) {
    var sidebar=sidebar_widget(browser);assert(sidebar!=null);
    var entries=browser.places.entries;
    assert(entries[0].label=="Home"&&entries[0].file.get_uri()=="recent:///");
    assert(entries[1].label=="Favorites"&&entries[1].section=="");
    bool devices=false;int roots=0;
    for(int i=0;i<entries.size;i++) {
        var place=entries[i];var row=sidebar.get_row_at_index(i);assert(row!=null&&row.get_data<Place>("majoris-place")==place);
        if(place.system){roots++;assert(place.file.equal(File.new_for_path("/")));assert(row.get_header() is Gtk.Label);assert(((Gtk.Label)row.get_header()).label=="Devices");devices=true;}
        if(place.section=="Folders")for(int j=0;j<i;j++)assert(!entries[j].file.equal(place.file));
        assert(place.section==""||place.section=="Folders"||place.section=="Devices");
    }
    assert(devices&&roots==1&&sidebar.get_row_at_index(entries.size)==null);
    assert(entries[entries.size-2].file.get_uri()=="network:///"&&entries[entries.size-1].file.get_uri()=="trash:///");
}
