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
    Test.add_func("/portal/roundtrip-and-isolation", () => test_portal());
    Test.add_func("/portal/success-close-and-authorization", () => test_success_and_authorization());
    Test.add_func("/portal/save-files", () => test_save_files());
    return Test.run();
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
