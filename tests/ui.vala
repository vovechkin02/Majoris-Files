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
        foreach(bool cut in new bool[] {false, true}) {
            FileClipboard.publish(clipboard, files, cut);
            assert(clipboard.get_formats().contain_gtype(typeof(Gdk.FileList)));
            assert(clipboard.get_formats().contain_mime_type("text/uri-list"));
            var loop = new MainLoop();
            FileClipboard.read.begin(clipboard, (obj, res) => {
                try {
                    var content = FileClipboard.read.end(res);
                    assert(content.cut == cut);
                    assert(content.files.size == 1 && content.files[0].equal(files[0]));
                } catch(Error e) { error("%s", e.message); }
                loop.quit();
            });
            uint watchdog = Timeout.add_seconds(10, () => { error("Clipboard read timed out"); });
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
        uint watchdog = Timeout.add_seconds(10, () => { error("Initial location recovery timed out"); });
        loop.run();
        Source.remove(watchdog);
        assert(recovered);
    } catch(Error e) { error("%s", e.message); }
}
