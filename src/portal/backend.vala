namespace MajorisFiles {
    [DBus(name = "org.freedesktop.impl.portal.Request")]
    public class PortalRequest : Object {
        public string owner;
        public signal void closed();
        public void close(BusName sender) throws DBusError, IOError
        {
            if (sender != owner)
                throw new DBusError.ACCESS_DENIED("Request belongs to another caller");
            closed();
        }
    }
    [DBus(name = "org.freedesktop.impl.portal.FileChooser")]
    public class PortalBackend : Object {
        public uint version {
            get {
                return 1;
            }
        }
        DBusConnection connection;
        Gtk.Application app;
        MetadataStore metadata;
        Places places;
        Gee.HashSet<string> handles = new Gee.HashSet<string>();
        public PortalBackend(DBusConnection connection, Gtk.Application app)
        {
            this.connection = connection;
            this.app = app;
            metadata = new MetadataStore();
            places = new Places(metadata);
        }
        public async void open_file(ObjectPath handle, string app_id, string parent_window, string title, HashTable<string, Variant> options, BusName sender, out uint response, out HashTable<string, Variant> results) throws DBusError, IOError
        {
            yield choose(false, handle, app_id, parent_window, title, options, sender, out response, out results);
        }
        public async void save_file(ObjectPath handle, string app_id, string parent_window, string title, HashTable<string, Variant> options, BusName sender, out uint response, out HashTable<string, Variant> results) throws DBusError, IOError
        {
            yield choose(true, handle, app_id, parent_window, title, options, sender, out response, out results);
        }
        async void choose(bool save, ObjectPath handle, string app_id, string parent_window, string title, HashTable<string, Variant> options, BusName sender, out uint response, out HashTable<string, Variant> results) throws DBusError, IOError
        {
            // Only xdg-desktop-portal may invoke this host-privileged browsing service.
            Variant owner;
            try {
                owner = yield connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetNameOwner", new Variant("(s)", "org.freedesktop.portal.Desktop"), new VariantType("(s)"), DBusCallFlags.NONE, -1, null);
            }
            catch (Error e) {
                throw new DBusError.ACCESS_DENIED("Desktop portal is unavailable");
            }
            if (owner.get_child_value(0).get_string() != sender)
                throw new DBusError.ACCESS_DENIED("Only xdg-desktop-portal may invoke the backend");
            if (!((string)handle).has_prefix("/org/freedesktop/portal/desktop/request/") || handles.contains(handle))
                throw new DBusError.INVALID_ARGS("Invalid or duplicate request handle");
            var builder = new VariantBuilder(VariantType.VARDICT);
            options.foreach((key, value) => builder.add("{sv}", key, value));
            ChooserOptions parsed;
            try {
                parsed = new ChooserOptions(save, builder.end());
            }
            catch (Error e) {
                throw new DBusError.INVALID_ARGS(e.message);
            }
            var window = new ChooserWindow(parsed, metadata, places, app_id);
            window.application = app;
            if (title != "")
                window.title = title;
            if (!set_external_parent(window, parent_window))
            {
                window.destroy();
                throw new DBusError.INVALID_ARGS("Unsupported parent window identifier");
            }
            var request = new PortalRequest();
            request.owner = sender;
            uint registration = connection.register_object(handle, request);
            handles.add(handle);
            app.hold();
            uint code = 1;
            Variant output = new VariantBuilder(VariantType.VARDICT).end();
            bool completed = false;
            window.completed.connect((r, v) => { code = r;
                                                 output = v;
                                                 completed = true;
                                                 Idle.add(() => { choose.callback();
                                                                  return Source.REMOVE;
                                                     });
                });
            request.closed.connect(() => window.cancel_request());
            uint subscription = connection.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus", sender, DBusSignalFlags.NONE, (c, s, p, i, n, parameters) => { if (parameters.get_child_value(2).get_string() == "")
                                                                                                                                                                                                                            window.cancel_request();
                });
            window.present();
            if (!completed)
                yield;
            connection.signal_unsubscribe(subscription);
            connection.unregister_object(registration);
            handles.remove(handle);
            app.release();
            response = code;
            results = new HashTable<string, Variant>(str_hash, str_equal);
            var iter = output.iterator();
            string key;
            Variant value;
            while (iter.next("{sv}", out key, out value))
                results.insert(key, value);
        }
    }
}
