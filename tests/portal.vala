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
    // Own the mock portal name before GTK can auto-activate the installed portal
    // while reading desktop settings. These are backend component tests.
    DBusConnection mock_portal_bus;
    try {
        mock_portal_bus = Bus.get_sync(BusType.SESSION);
        var bus = mock_portal_bus;
        var result = bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", new Variant("(su)", "org.freedesktop.portal.Desktop", 0u), new VariantType("(u)"), DBusCallFlags.NONE, 5000, null);
        assert(result.get_child_value(0).get_uint32() == 1);
    }
    catch (Error e) { error("%s", e.message); }
    Gtk.init();
    Adw.init();
    Test.init(ref args);
    Test.add_func("/portal/roundtrip-and-isolation", () => test_portal());
    Test.add_func("/portal/success-close-and-authorization", () => test_success_and_authorization());
    Test.add_func("/portal/save-files", () => test_save_files());
    Test.add_func("/extensions/out-of-process-lifecycle", () => {
        var loop = new MainLoop();
        extension_case.begin((obj, res) => { try { extension_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        uint watchdog = Timeout.add_seconds(15, () => { error("Extension integration timed out"); });
        loop.run(); Source.remove(watchdog);
    });
    Test.add_func("/desktop/shell-search-protocol", () => {
        var loop = new MainLoop();
        shell_case.begin((obj, res) => { try { shell_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        uint watchdog = Timeout.add_seconds(15, () => { error("Shell search integration timed out"); });
        loop.run(); Source.remove(watchdog);
    });
    int result = Test.run();
    mock_portal_bus.flush_sync(null);
    return result;
}
async void shell_case() throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-shell-XXXXXX"));
    var file = root.get_child("shell-hit.txt"); FileUtils.set_contents(file.get_path(), "shell fixture");
    var metadata = new MetadataStore(root.get_child("state.db").get_path());
    metadata.set_state("indexed-search", "false");
    var app = new Adw.Application("com.majoris.files.shelltest", ApplicationFlags.NON_UNIQUE); app.register(null);
    var roots = new Gee.ArrayList<File>(); roots.add(root);
    var provider = new ShellSearchProvider(app, metadata, new Places(), new OperationManager(metadata), roots);
    var bus = Bus.get_sync(BusType.SESSION);
    uint registration = bus.register_object("/com/majoris/files/SearchProvider", provider);
    try {
        var reply = yield bus.call(bus.unique_name, "/com/majoris/files/SearchProvider", "org.gnome.Shell.SearchProvider2", "GetInitialResultSet", new Variant("(^as)", new string[] {"shell-hit"}), new VariantType("(as)"), DBusCallFlags.NONE, 10000, null);
        var ids = reply.get_child_value(0).dup_strv(); assert(ids.length == 1 && ids[0] == file.get_uri());
        var metas = yield bus.call(bus.unique_name, "/com/majoris/files/SearchProvider", "org.gnome.Shell.SearchProvider2", "GetResultMetas", new Variant("(^as)", ids), new VariantType("(aa{sv})"), DBusCallFlags.NONE, 1000, null);
        assert(metas.get_child_value(0).n_children() == 1);
        yield bus.call(bus.unique_name, "/com/majoris/files/SearchProvider", "org.gnome.Shell.SearchProvider2", "ActivateResult", new Variant("(s^asu)", ids[0], new string[] {"shell-hit"}, 0u), new VariantType("()"), DBusCallFlags.NONE, 1000, null);
        var window = app.get_windows().data as FilesWindow; assert(window != null);
        for (int i = 0; i < 100 && window.current.selected().size == 0; i++) {
            Timeout.add(20, () => { shell_case.callback(); return Source.REMOVE; }); yield;
        }
        assert(window.current.location.equal(root) && window.current.selected().size == 1 && window.current.selected()[0].file.equal(file));
        window.close();
        bool refused = false; try { provider.activate_result("file:///unrequested", {}, 0); } catch (Error e) { refused = true; }
        assert(refused);
    }
    finally { bus.unregister_object(registration); }
    yield OperationManager.remove_tree(root, new Cancellable());
}
async void extension_case() throws Error
{
    string build = Path.get_dirname(FileUtils.read_link("/proc/self/exe"));
    string examples = Path.build_filename(build, "..", "examples");
    var root = File.new_for_path(DirUtils.make_tmp("majoris-extension-XXXXXX"));
    string manifest;
    FileUtils.get_contents(Path.build_filename(examples, "checksum.extension"), out manifest);
    FileUtils.set_contents(root.get_child("checksum.extension").get_path(), manifest);
    var metadata = new MetadataStore(root.get_child("state.db").get_path());
    var manager = new ExtensionManager(metadata, {root.get_path()});
    assert(manager.extensions.size == 1 && !manager.extensions[0].enabled);
    var extension = manager.extensions[0]; extension.set_enabled(true);
    var process = new Subprocess.newv({"/usr/bin/python3", Path.build_filename(examples, "checksum-extension.py")}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
    bool stopped = false;
    try {
        var bus = Bus.get_sync(BusType.SESSION);
        bool ready = false;
        for (int i = 0; i < 100; i++) {
            var reply = yield bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", new Variant("(s)", extension.bus_name), new VariantType("(b)"), DBusCallFlags.NONE, 1000, null);
            if (reply.get_child_value(0).get_boolean()) { ready = true; break; }
            Timeout.add(20, () => { extension_case.callback(); return Source.REMOVE; }); yield;
        }
        assert(ready);
        var file = root.get_child("example.txt"); FileUtils.set_contents(file.get_path(), "external provider fixture");
        var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
        var item = new FileItem(file, info);
        var selected = new Gee.ArrayList<FileItem>(); selected.add(item);
        yield manager.prepare(selected);
        assert(extension.actions(selected).size == 1);
        var values = yield extension.file_info(item); assert(values["Extension"] == ".txt");
        var properties = yield extension.call("GetProperties", new Variant("(s)", file.get_uri()), "(a(ss))");
        assert(properties.get_child_value(0).n_children() == 2);
        var column = new ExternalColumn(extension, "Bytes", "Example Bytes");
        column.text(item, metadata);
        for (int i = 0; i < 100 && column.text(item, metadata) == "…"; i++) { Timeout.add(20, () => { extension_case.callback(); return Source.REMOVE; }); yield; }
        assert(column.text(item, metadata) == "25");
        var parent = new Gtk.Window();
        yield extension.execute("checksum", selected, parent);
        string checksum; FileUtils.get_contents(root.get_child("example.txt.sha256").get_path(), out checksum);
        assert(checksum.has_prefix(Checksum.compute_for_string(ChecksumType.SHA256, "external provider fixture")));
        parent.destroy();
        process.force_exit(); yield process.wait_async(null); stopped = true;
        yield extension.prepare(selected);
        assert(extension.actions(selected).size == 0 && extension.failure != "");
        extension.set_enabled(false); assert(column.text(item, metadata) == "");
    }
    finally { if (!stopped) process.force_exit(); }
    yield OperationManager.remove_tree(root, new Cancellable());
}
void test_save_files()
{
    try {
        var temp = DirUtils.make_tmp("majoris-save-files-XXXXXX");
        FileUtils.set_contents(Path.build_filename(temp, "report.txt"), "preserved");
        var connection = Bus.get_sync(BusType.SESSION);
        connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", new Variant("(su)", "org.freedesktop.portal.Desktop", 0u), null, DBusCallFlags.NONE, -1, null);
        var app = new Adw.Application("com.majoris.files.test.savefiles", ApplicationFlags.NON_UNIQUE);
        app.register(null);
        var backend = new PortalBackend(connection, app);
        uint registration = connection.register_object("/org/freedesktop/portal/desktop", backend);
        var options = new VariantBuilder(VariantType.VARDICT);
        options.add("{sv}", "current_folder", new Variant.bytestring(temp));
        var names = new VariantBuilder(new VariantType("aay"));
        foreach (var name in new string[] {"report.txt", "report.txt", "other.txt"})
            names.add_value(new Variant.bytestring(name));
        options.add("{sv}", "files", names.end());
        var loop = new MainLoop();
        bool done = false;
        connection.call.begin(connection.unique_name, "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.FileChooser", "SaveFiles", new Variant("(osss@a{sv})", "/org/freedesktop/portal/desktop/request/test/savefiles", "test.app", "", "Save Files", options.end()), new VariantType("(ua{sv})"), DBusCallFlags.NONE, 10000, null, (obj, res) => {
            try {
                var result = connection.call.end(res);
                assert(result.get_child_value(0).get_uint32() == 0);
                var uris = result.get_child_value(1).lookup_value("uris", new VariantType("as"));
                assert(uris.n_children() == 3);
                string[] expected = {"report (1).txt", "report (2).txt", "other.txt"};
                for (size_t i = 0; i < 3; i++)
                {
                    var target = File.new_for_uri(uris.get_child_value(i).get_string());
                    assert(target.get_basename() == expected[i]);
                    assert(!target.query_exists());
                }
                string contents;
                FileUtils.get_contents(Path.build_filename(temp, "report.txt"), out contents);
                assert(contents == "preserved");
                done = true;
                loop.quit();
            }
            catch (Error e) { error("%s", e.message); }
        });
        uint poll = Timeout.add(20, () => {
            if (app.get_windows().length() != 1)
                return Source.CONTINUE;
            var window = (ChooserWindow)app.get_windows().data;
            if (window.browser.directory.loading || !window.browser.location.equal(File.new_for_path(temp)))
                return Source.CONTINUE;
            assert(window.options.save_many && window.options.directory);
            window.accept_selection.begin();
            return Source.REMOVE;
        });
        uint watchdog = Timeout.add_seconds(15, () => { error("SaveFiles timed out"); });
        loop.run();
        Source.remove(watchdog);
        assert(done && poll > 0);
        assert(app.get_windows().length() == 0);
        connection.unregister_object(registration);
    }
    catch (Error e) { error("%s", e.message); }
}
void test_success_and_authorization()
{
    try {
        var temp = DirUtils.make_tmp("majoris-portal-success-XXXXXX");
        var file = File.new_for_path(Path.build_filename(temp, "selected.txt"));
        FileUtils.set_contents(file.get_path(), "unchanged");
        var connection = Bus.get_sync(BusType.SESSION);
        connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", new Variant("(su)", "org.freedesktop.portal.Desktop", 0u), null, DBusCallFlags.NONE, -1, null);
        var app = new Adw.Application("com.majoris.files.test.success", ApplicationFlags.NON_UNIQUE);
        app.register(null);
        var backend = new PortalBackend(connection, app);
        uint registration = connection.register_object("/org/freedesktop/portal/desktop", backend);
        var stranger = new DBusConnection.for_address_sync(Environment.get_variable("DBUS_SESSION_BUS_ADDRESS"), DBusConnectionFlags.AUTHENTICATION_CLIENT | DBusConnectionFlags.MESSAGE_BUS_CONNECTION);
        var loop = new MainLoop();
        uint finished = 0;
        bool rejected = false;
        bool close_returned = false;
        bool close_denied = false;
        var options = new VariantBuilder(VariantType.VARDICT);
        options.add("{sv}", "current_folder", new Variant.bytestring(temp));
        connection.call.begin(connection.unique_name, "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.FileChooser", "OpenFile", new Variant("(osss@a{sv})", "/org/freedesktop/portal/desktop/request/test/success", "test.app", "", "Select", options.end()), new VariantType("(ua{sv})"), DBusCallFlags.NONE, 10000, null, (obj, res) => {
            try {
                var result = connection.call.end(res);
                assert(result.get_child_value(0).get_uint32() == 0);
                var uris = result.get_child_value(1).lookup_value("uris", new VariantType("as"));
                assert(uris.n_children() == 1 && uris.get_child_value(0).get_string() == file.get_uri());
                finished++;
            }
            catch(Error e) { error("%s", e.message);
            }
        });
        string close_handle = "/org/freedesktop/portal/desktop/request/test/close";
        connection.call.begin(connection.unique_name, "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.FileChooser", "OpenFile", new Variant("(osss@a{sv})", close_handle, "test.app", "", "Close", new VariantBuilder(VariantType.VARDICT).end()), new VariantType("(ua{sv})"), DBusCallFlags.NONE, 10000, null, (obj, res) => {
            try {
                var result = connection.call.end(res);
                assert(result.get_child_value(0).get_uint32() == 1);
                finished++;
            }
            catch(Error e) { error("%s", e.message);
            }
        });
        stranger.call.begin(connection.unique_name, "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.FileChooser", "OpenFile", new Variant("(osss@a{sv})", "/org/freedesktop/portal/desktop/request/test/stranger", "test.app", "", "Forbidden", new VariantBuilder(VariantType.VARDICT).end()), null, DBusCallFlags.NONE, 10000, null, (obj, res) => {
            try { stranger.call.end(res);
                  assert_not_reached();
            }
            catch(Error e) { assert(DBusError.get_remote_error(e) == "org.freedesktop.DBus.Error.AccessDenied");
                             rejected = true;
            }
        });
        bool acted = false;
        Timeout.add(20, () => {
            if(finished == 2 && rejected && close_returned && close_denied)
            {
                loop.quit();
                return Source.REMOVE;
            }
            if(!acted && app.get_windows().length() == 2)
            {
                ChooserWindow? success = null;
                foreach(var candidate in app.get_windows())
                {
                    var window = (ChooserWindow)candidate;
                    if(window.title == "Select")
                        success = window;
                }
                if(success == null || success.browser.directory.loading || !success.browser.location.equal(File.new_for_path(temp)))
                    return Source.CONTINUE;
                bool found = false;
                for(uint i = 0; i < success.browser.selection.get_n_items(); i++)
                {
                    var item = (FileItem)success.browser.selection.get_item(i);
                    if(item.file.equal(file))
                    {
                        success.browser.selection.select_item(i, true);
                        found = true;
                    }
                }
                if(!found)
                    return Source.CONTINUE;
                acted = true;
                success.accept_selection.begin();
                stranger.call.begin(connection.unique_name, close_handle, "org.freedesktop.impl.portal.Request", "Close", null, null, DBusCallFlags.NONE, 10000, null, (obj, res) => {
                    try { stranger.call.end(res);
                          assert_not_reached();
                    }
                    catch(Error e) {
                        assert(DBusError.get_remote_error(e) == "org.freedesktop.DBus.Error.AccessDenied");
                        close_denied = true;
                        connection.call.begin(connection.unique_name, close_handle, "org.freedesktop.impl.portal.Request", "Close", null, null, DBusCallFlags.NONE, 10000, null, (o, r) => {
                            try { connection.call.end(r);
                                  close_returned = true;
                            }
                            catch(Error close_error) { error("%s", close_error.message);
                            }
                        });
                    }
                });
            }
            return Source.CONTINUE;
        });
        uint watchdog = Timeout.add_seconds(15, () => { error("Portal success/authorization timed out");
            });
        loop.run();
        Source.remove(watchdog);
        assert(app.get_windows().length() == 0);
        connection.unregister_object(registration);
        stranger.close_sync();
    }
    catch(Error e) {
        error("%s", e.message);
    }
}
void test_portal()
{
    try {
        var connection = Bus.get_sync(BusType.SESSION);
        connection.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", new Variant("(su)", "org.freedesktop.portal.Desktop", 0u), null, DBusCallFlags.NONE, -1, null);
        var app = new Adw.Application("com.majoris.files.test", ApplicationFlags.NON_UNIQUE);
        app.register(null);
        var backend = new PortalBackend(connection, app);
        uint registration = connection.register_object("/org/freedesktop/portal/desktop", backend);
        var loop = new MainLoop();
        uint completed = 0;
        bool malformed = false;
        for(uint i = 0; i < 2; i++)
        {
            string handle = "/org/freedesktop/portal/desktop/request/test/" + "r%u".printf(i);
            var options = new VariantBuilder(VariantType.VARDICT);
            options.add("{sv}", "multiple", new Variant.boolean(i == 1));
            var parameters = new Variant("(osss@a{sv})", handle, "test.app", "", "Choose a File", options.end());
            connection.call.begin(connection.unique_name, "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.FileChooser", "OpenFile", parameters, new VariantType("(ua{sv})"), DBusCallFlags.NONE, 10000, null, (obj, res) => { try { var result = connection.call.end(res);
                                                                                                                                                                                                                                                    assert(result.get_child_value(0).get_uint32() == 1);
                                                                                                                                                                                                                                                    assert(result.get_child_value(1).n_children() == 0);
                                                                                                                                                                                                                                                    completed++;
                                                                                                                                                                                                                                                    if(completed == 2 && malformed)
                                                                                                                                                                                                                                                        loop.quit();
                                                                                                                                                                                                                                              }
                                                                                                                                                                                                                                              catch(Error e) { error("%s", e.message);
                                                                                                                                                                                                                                              }
                });
        }
        var invalid = new VariantBuilder(VariantType.VARDICT);
        invalid.add("{sv}", "multiple", new Variant.string("invalid"));
        connection.call.begin(connection.unique_name, "/org/freedesktop/portal/desktop", "org.freedesktop.impl.portal.FileChooser", "OpenFile", new Variant("(osss@a{sv})", "/org/freedesktop/portal/desktop/request/test/bad", "test.app", "", "Bad", invalid.end()), null, DBusCallFlags.NONE, 10000, null, (obj, res) => { try { connection.call.end(res);
                                                                                                                                                                                                                                                                                                                                    assert_not_reached();
                                                                                                                                                                                                                                                                                                                              }
                                                                                                                                                                                                                                                                                                                              catch(Error e) { malformed = true;
                                                                                                                                                                                                                                                                                                                                               if(completed == 2)
                                                                                                                                                                                                                                                                                                                                                   loop.quit();
                                                                                                                                                                                                                                                                                                                              }
            });
        bool cancelled = false;
        uint poll = Timeout.add(50, () => { if(cancelled)
                                                return Source.REMOVE;
                                            if(app.get_windows().length() == 2)
                                            {
                                                var windows = new Gee.ArrayList<ChooserWindow>();
                                                foreach(var window in app.get_windows())
                                                    windows.add((ChooserWindow)window);
                                                assert(windows[0].options != windows[1].options);
                                                assert(windows[0].options.multiple != windows[1].options.multiple);
                                                foreach(var window in windows)
                                                    window.cancel_request();
                                                cancelled = true;
                                                return Source.REMOVE;
                                            }
                                            return Source.CONTINUE;
            });
        uint watchdog = Timeout.add_seconds(15, () => { error("Portal roundtrip timed out");
                                                        return Source.REMOVE;
            });
        loop.run();
        Source.remove(watchdog);
        if(!cancelled)
            Source.remove(poll);
        assert(completed == 2 && malformed);
        connection.unregister_object(registration);
    }
    catch(Error e) {
        error("%s", e.message);
    }
}
