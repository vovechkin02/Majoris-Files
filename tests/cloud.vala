using MajorisFiles;
[DBus(name = "com.majoris.Files.CloudOperation1")]
class CloudJobFixture : Object {
    public bool cancelled;
    public bool waiting;
    public void get_status(out string phase, out HashTable<string, Variant> fields) throws DBusError, IOError {
        fields = new HashTable<string, Variant>(str_hash, str_equal);
        fields["progress"] = new Variant.double(waiting ? 0.25 : 1);
        fields["message"] = new Variant.string(cancelled ? "Cancelled" : "Fixture transfer");
        phase = cancelled ? "cancelled" : waiting ? "running" : "completed";
    }
    public void cancel() throws DBusError, IOError { cancelled = true; }
}
[DBus(name = "com.majoris.Files.CloudFiles1")]
class CloudFixture : Object {
    public string folder;
    public string state = "online-only";
    public bool fail;
    public bool waiting;
    public CloudJobFixture job = new CloudJobFixture();
    public signal void changed(string uri);
    public uint get_version() throws DBusError, IOError { return 1; }
    public HashTable<string, Variant> get_file_state(string uri) throws DBusError, IOError {
        if (fail) throw new IOError.HOST_UNREACHABLE("Provider offline");
        var fields = new HashTable<string, Variant>(str_hash, str_equal);
        fields["state"] = new Variant.string(state);
        fields["size"] = new Variant.uint64(17);
        fields["capabilities"] = new Variant.strv({"materialize", "pin", "evict", "cancel"});
        fields["quota-used"] = new Variant.uint64(17);
        fields["quota-total"] = new Variant.uint64(1000);
        return fields;
    }
    public ObjectPath start_operation(string uri, string action, uint64 maximum) throws DBusError, IOError {
        if (action != "evict" && maximum < 17) throw new IOError.NO_SPACE("Fixture limit");
        var file = File.new_for_uri(uri);
        if (!file.has_prefix(File.new_for_path(folder))) throw new IOError.PERMISSION_DENIED("Outside fixture");
        job.waiting = waiting; job.cancelled = false;
        if (!waiting) {
            try {
                if (action == "evict") { FileUtils.set_contents(file.get_path(), ""); state = "online-only"; }
                else { FileUtils.set_contents(file.get_path(), "provider-content\n"); state = action == "pin" ? "pinned" : "cached"; }
                changed(uri);
            }
            catch (GLib.FileError e) { throw new IOError.FAILED(e.message); }
        }
        return new ObjectPath("/com/majoris/CloudFixture/operation");
    }
}
int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/cloud/provider-workflow", () => {
        var loop = new MainLoop();
        run.begin((obj, res) => { try { run.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        uint watchdog = Timeout.add_seconds(15, () => { error("Cloud fixture timed out"); });
        loop.run(); Source.remove(watchdog);
    });
    return Test.run();
}
async void run() throws Error {
    var root = File.new_for_path(DirUtils.make_tmp("majoris-cloud-XXXXXX"));
    var file = root.get_child("online.txt"); FileUtils.set_contents(file.get_path(), "");
    var bus = Bus.get_sync(BusType.SESSION);
    var fixture = new CloudFixture(); fixture.folder = root.get_path();
    uint service = bus.register_object("/com/majoris/CloudFixture", fixture);
    uint operation = bus.register_object("/com/majoris/CloudFixture/operation", fixture.job);
    try {
        var adapter = new DBusCloudFiles(root, bus.unique_name, "/com/majoris/CloudFixture", bus);
        var registry = new CloudFiles(); registry.register_provider(adapter);
        var token = new Cancellable();
        var state = yield registry.query(file, token);
        assert(state.online_only && state.emblem != null && state.quota_known && state.quota_used == 17);
        bool limited = false;
        try { yield registry.materialize(file, 1, token); } catch (IOError.NO_SPACE e) { limited = true; }
        assert(limited);
        bool progress = false;
        assert((yield registry.materialize(file, 1024, token, (fraction, text) => { assert(fraction == 1); progress = true; })).equal(file));
        string content; FileUtils.get_contents(file.get_path(), out content); assert(content == "provider-content\n" && progress);
        yield adapter.perform(file, "pin", 1024, token); state = yield registry.query(file, token); assert(state.state == "pinned");
        yield adapter.perform(file, "evict", 1024, token); state = yield registry.query(file, token); assert(state.online_only);
        bool unsupported = false;
        try { yield adapter.perform(file, "delete", 1024, token); } catch (IOError.NOT_SUPPORTED e) { unsupported = true; }
        assert(unsupported);
        fixture.fail = true; bool offline = false;
        try { yield registry.materialize(file, 1024, token); } catch (Error e) { offline = true; }
        assert(offline); fixture.fail = false; fixture.waiting = true;
        var cancelled = new Cancellable(); Timeout.add(100, () => { cancelled.cancel(); return Source.REMOVE; });
        bool stopped = false;
        try { yield registry.materialize(file, 1024, cancelled); } catch (IOError.CANCELLED e) { stopped = true; }
        assert(stopped && fixture.job.cancelled);
        assert((yield registry.query(root.get_parent(), token)).state == "unsupported");
    }
    finally { bus.unregister_object(operation); bus.unregister_object(service); }
    yield OperationManager.remove_tree(root, new Cancellable());
}
