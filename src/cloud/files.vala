namespace MajorisFiles {
    public class CloudFileState : Object {
        public string state = "unsupported";
        public string error = "";
        public string mime = "";
        public string[] capabilities = {};
        public uint64 size;
        public bool size_known;
        public uint64 quota_used;
        public uint64 quota_total;
        public bool quota_known;
        public double progress = -1;
        public bool online_only { get { return state == "online-only"; } }
        public string? emblem {
            get {
                switch (state) {
                    case "online-only": return "network-server-symbolic";
                    case "pinned": return "emblem-favorite-symbolic";
                    case "cached": case "completed": return "emblem-ok-symbolic";
                    case "downloading": case "uploading": case "syncing": return "emblem-synchronizing-symbolic";
                    case "error": case "unavailable": case "quota-exceeded": return "dialog-warning-symbolic";
                    default: return null;
                }
            }
        }
        public static CloudFileState parse(Variant values) throws Error
        {
            var result = new CloudFileState();
            values.lookup("state", "s", out result.state);
            if (!(result.state in new string[] {"local", "online-only", "cached", "pinned", "downloading", "uploading", "syncing", "completed", "error", "unavailable", "quota-exceeded", "unsupported"}))
                throw new IOError.INVALID_DATA("Invalid cloud file state");
            var caps = values.lookup_value("capabilities", VariantType.STRING_ARRAY);
            if (caps != null) result.capabilities = caps.dup_strv();
            if (result.capabilities.length > 8) throw new IOError.INVALID_DATA("Too many cloud capabilities");
            result.size_known = values.lookup("size", "t", out result.size);
            result.quota_known = values.lookup("quota-used", "t", out result.quota_used) && values.lookup("quota-total", "t", out result.quota_total);
            if (result.quota_known && result.quota_used > result.quota_total) result.quota_known = false;
            if (!values.lookup("progress", "d", out result.progress)) result.progress = -1;
            values.lookup("mime", "s", out result.mime);
            if (result.mime == null) result.mime = "";
            if (result.mime.length > 255 || (result.mime != "" && !Regex.match_simple("^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$", result.mime))) throw new IOError.INVALID_DATA("Invalid provider MIME type");
            values.lookup("error", "s", out result.error);
            if (result.error == null) result.error = "";
            if (result.error.length > 4096 || !result.progress.is_finite()) throw new IOError.INVALID_DATA("Invalid cloud status");
            return result;
        }
    }
    public delegate void CloudProgress(double progress, string message);
    public interface CloudFileProvider : Object {
        public abstract File root { get; }
        public signal void changed(string uri);
        public abstract async CloudFileState query(File file, Cancellable token) throws Error;
        public abstract async File perform(File file, string action, uint64 maximum_bytes, Cancellable token, CloudProgress? progress = null) throws Error;
    }
    // Optional provider adapters declare their API explicitly. libcloudproviders
    // itself has no per-file or materialisation API; account status is never
    // converted into a made-up file status.
    public class DBusCloudFiles : Object, CloudFileProvider {
        File provider_root;
        public File root { get { return provider_root; } }
        string bus_name;
        string object_path;
        DBusConnection connection;
        uint subscription;
        uint owner_watch;
        public DBusCloudFiles(File root, string name, string path, DBusConnection connection) throws Error
        {
            if (!DBus.is_name(name) || !Variant.is_object_path(path)) throw new IOError.INVALID_ARGUMENT("Invalid cloud adapter");
            provider_root = root; bus_name = name; object_path = path; this.connection = connection;
            owner_watch=Bus.watch_name_on_connection(connection,name,BusNameWatcherFlags.NONE,()=>changed(""),()=>changed(""));
            subscription = connection.signal_subscribe(name, "com.majoris.Files.CloudFiles1", "Changed", path, null, DBusSignalFlags.NONE, (bus, sender, path, iface, signal_name, parameters) => {
                if (parameters.is_of_type(new VariantType("(s)"))) changed(parameters.get_child_value(0).get_string());
            });
        }
        public void close(){if(owner_watch!=0){Bus.unwatch_name(owner_watch);owner_watch=0;}if(subscription!=0){connection.signal_unsubscribe(subscription);subscription=0;}}
        async Variant call(string path, string iface, string method, Variant? args, string reply, Cancellable? token) throws Error
        {
            return yield connection.call(bus_name, path, iface, method, args, new VariantType(reply), DBusCallFlags.NONE, 3000, token);
        }
        public async CloudFileState query(File file, Cancellable token) throws Error
        {
            var version = yield call(object_path, "com.majoris.Files.CloudFiles1", "GetVersion", null, "(u)", token);
            if (version.get_child_value(0).get_uint32() != 1) throw new IOError.NOT_SUPPORTED("Unsupported cloud adapter version");
            var reply = yield call(object_path, "com.majoris.Files.CloudFiles1", "GetFileState", new Variant("(s)", file.get_uri()), "(a{sv})", token);
            return CloudFileState.parse(reply.get_child_value(0));
        }
        public async File perform(File file, string action, uint64 maximum_bytes, Cancellable token, CloudProgress? progress = null) throws Error
        {
            var state = yield query(file, token);
            if (!(action in state.capabilities)) throw new IOError.NOT_SUPPORTED("The cloud provider does not support this operation");
            if (action != "evict" && (!state.size_known || state.size > maximum_bytes)) throw new IOError.NO_SPACE("Cloud content exceeds the configured limit or has no verified size");
            var reply = yield call(object_path, "com.majoris.Files.CloudFiles1", "StartOperation", new Variant("(sst)", file.get_uri(), action, maximum_bytes), "(o)", token);
            string operation = reply.get_child_value(0).get_string();
            if (!operation.has_prefix(object_path == "/" ? "/" : object_path + "/")) throw new IOError.INVALID_DATA("Invalid cloud operation handle");
            int64 deadline = get_monotonic_time() + 1800L * 1000000;
            try {
                while (true) {
                    token.set_error_if_cancelled();
                    if (get_monotonic_time() > deadline) throw new IOError.TIMED_OUT("Cloud operation timed out");
                    var status = yield call(operation, "com.majoris.Files.CloudOperation1", "GetStatus", null, "(sa{sv})", token);
                    string phase = status.get_child_value(0).get_string();
                    var fields = status.get_child_value(1); double fraction = -1; string message = "";
                    if (!fields.lookup("progress", "d", out fraction)) fraction = -1;
                    fields.lookup("message", "s", out message);
                    if (message != null && message.length > 4096) throw new IOError.INVALID_DATA("Cloud status message exceeds the limit");
                    if (progress != null) progress(fraction.is_finite() ? fraction.clamp(-1, 1) : -1, message ?? "");
                    if (phase == "completed") {
                        // Providers materialise in their own authoritative namespace;
                        // arbitrary returned host paths never become portal grants.
                        changed(file.get_uri()); return file;
                    }
                    if(phase=="cancelled")throw new IOError.CANCELLED("The cloud operation was cancelled");
                    if (phase == "error") throw new IOError.FAILED(message ?? "The cloud operation failed");
                    if (phase != "running") throw new IOError.INVALID_DATA("Invalid cloud operation status");
                    Timeout.add(200, () => { perform.callback(); return Source.REMOVE; }); yield;
                }
            }
            catch (Error e) {
                if ("cancel" in state.capabilities)
                    try { yield call(operation, "com.majoris.Files.CloudOperation1", "Cancel", null, "()", null); } catch (Error ignored) {}
                throw e;
            }
        }
        ~DBusCloudFiles() { close(); }
    }
    public class CloudFiles : Object {
        static CloudFiles? instance;
        public Gee.ArrayList<CloudFileProvider> providers = new Gee.ArrayList<CloudFileProvider>();
        Gee.HashMap<string, CloudFileState> cache = new Gee.HashMap<string, CloudFileState>();
        Gee.HashSet<string> pending = new Gee.HashSet<string>();
        uint epoch;
        Gee.HashMap<string, uint?> revisions = new Gee.HashMap<string, uint?>();
        public signal void changed(string uri);
        MetadataStore? settings;
        string configuration = "";
        Gee.ArrayList<CloudFileProvider> discovered = new Gee.ArrayList<CloudFileProvider>();
        Gee.HashMap<CloudFileProvider,ulong?> handlers=new Gee.HashMap<CloudFileProvider,ulong?>();
        Gee.HashMap<string,FileMonitor> monitors=new Gee.HashMap<string,FileMonitor>();
        uint discover_timer;
        void schedule_discovery(){if(discover_timer==0)discover_timer=Timeout.add(250,()=>{discover_timer=0;discover.begin();return Source.REMOVE;});}
        public void configure(MetadataStore metadata) {
            if (settings != null) return;
            settings = metadata;
            metadata.changed.connect(schedule_discovery);
            discover.begin();
        }
        bool discovering;
        async void discover() {
            if (discovering || settings == null) return;
            discovering = true;
            try {
                var descriptions = new Gee.ArrayList<KeyFile>();
                var signature = new StringBuilder();
                foreach (var folder in new string[] {"/usr/share/majoris-files/extensions", Path.build_filename(Environment.get_user_data_dir(), "majoris-files", "extensions")}) {
                    try {
                        foreach(var watched in new string[]{folder,Path.get_dirname(folder)})if(!monitors.has_key(watched)&&FileUtils.test(watched,FileTest.IS_DIR)){
                            var monitor=File.new_for_path(watched).monitor_directory(FileMonitorFlags.NONE);monitor.changed.connect(schedule_discovery);monitors[watched]=monitor;
                        }
                        var directory = Dir.open(folder); string? name;uint examined=0;
                        while ((name = directory.read_name()) != null && descriptions.size < 128 && examined++<512) {
                            if (!name.has_suffix(".extension")) continue;
                            try{
                            var file = File.new_for_path(Path.build_filename(folder, name));
                            var info = file.query_info("standard::type,standard::size", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                            if (info.get_file_type() != FileType.REGULAR || info.get_size() > 65536) continue;
                            var key = new KeyFile(); key.load_from_file(file.get_path(), KeyFileFlags.NONE);
                            if (!("cloud" in key.get_string_list("Extension", "Capabilities"))) continue;
                            string id = key.get_string("Extension", "Id");
                            if (settings.state("extension-enabled:" + id, folder.has_prefix("/usr/") ? "true" : "false") != "true") continue;
                            descriptions.add(key); signature.append(key.to_data());
                            }catch(Error invalid){} // One bad descriptor cannot hide other providers.
                        }
                    }
                    catch (Error e) {} // Unsupported or absent adapters remain unavailable.
                }
                if (signature.str == configuration) return;
                var connection = yield Bus.get(BusType.SESSION);
                foreach (var old in discovered){if(handlers.has_key(old)){old.disconnect(handlers[old]);handlers.unset(old);}if(old is DBusCloudFiles)((DBusCloudFiles)old).close();providers.remove(old);}
                discovered.clear(); cache.clear(); epoch++;
                foreach (var key in descriptions) {
                    try {
                        if (key.get_integer("Extension", "Version") != 1) continue;
                        string uri = key.get_string("Cloud", "RootURI");
                        var parsed = Uri.parse(uri, UriFlags.HAS_PASSWORD);
                        if (parsed.get_scheme() == null || parsed.get_userinfo() != null) continue;
                        var adapter = new DBusCloudFiles(File.new_for_uri(uri), key.get_string("Extension", "BusName"), key.get_string("Extension", "ObjectPath"), connection);
                        register_provider(adapter); discovered.add(adapter);
                    }
                    catch (Error e) {}
                }
                configuration = signature.str; changed("");
            }
            catch (Error e) {}
            finally { discovering = false; }
        }
        public static CloudFiles get_default() { if (instance == null) instance = new CloudFiles(); return instance; }
        public void register_provider(CloudFileProvider provider) {
            providers.add(provider);
            handlers[provider]=provider.changed.connect((uri) => {
                if (uri == "") { epoch++; cache.clear(); revisions.clear(); }
                else {
                    var file = File.new_for_uri(uri);
                    if (!file.equal(provider.root) && !file.has_prefix(provider.root)) return;
                    revisions[uri] = (revisions[uri] ?? 0u) + 1;
                    if(revisions.size>4096){epoch++;revisions.clear();cache.clear();}
                    cache.unset(uri);
                }
                changed(uri);
            });
        }
        public CloudFileProvider? provider(File file) {
            CloudFileProvider? best = null;
            foreach (var entry in providers)
                if ((file.equal(entry.root) || file.has_prefix(entry.root)) && (best == null || entry.root.get_uri().length > best.root.get_uri().length)) best = entry;
            return best;
        }
        public CloudFileState? peek(File file) {
            string uri = file.get_uri();
            if (cache.has_key(uri)) return cache[uri];
            if (provider(file) != null && pending.size < 32 && pending.add(uri)) load.begin(file);
            return null;
        }
        public CloudFileState? cached(File file) { return cache[file.get_uri()]; }
        async void load(File file) {
            uint generation = epoch;
            string uri = file.get_uri(); uint revision = revisions[uri] ?? 0u;
            try { var result = yield query(file, new Cancellable()); if (generation == epoch && revision == (revisions[uri] ?? 0u)) cache[uri] = result; }
            catch (Error e) { if (generation == epoch && revision == (revisions[uri] ?? 0u)) { var failure = new CloudFileState(); failure.state = "unavailable"; failure.error = e.message; cache[uri] = failure; } }
            pending.remove(file.get_uri());
            if (generation != epoch || revision != (revisions[uri] ?? 0u)) { changed(uri); return; }
            if (cache.size > 2048) { var recent = cache[file.get_uri()]; cache.clear(); cache[file.get_uri()] = recent; }
            changed(file.get_uri());
        }
        public async CloudFileState query(File file, Cancellable token) throws Error {
            var entry = provider(file);
            return entry == null ? new CloudFileState() : yield entry.query(file, token);
        }
        public async File materialize(File file, uint64 limit, Cancellable token, CloudProgress? progress = null) throws Error {
            var entry = provider(file);
            if (entry == null) return file;
            var state = yield entry.query(file, token);
            if (state.state == "error" || state.state == "unavailable" || state.state == "quota-exceeded") throw new IOError.FAILED(state.error);
            if (!state.online_only) return file;
            if (!state.size_known || state.size > limit) throw new IOError.NO_SPACE("Cloud file exceeds the configured materialisation limit or has no verified size");
            if (file.is_native()) {
                var parent = file.get_parent();
                if (parent == null) throw new IOError.INVALID_ARGUMENT("Invalid cloud cache location");
                var space = yield parent.query_filesystem_info_async("filesystem::free", Priority.LOW, token);
                if (!space.has_attribute("filesystem::free") || space.get_attribute_uint64("filesystem::free") < state.size + 32 * 1024 * 1024)
                    throw new IOError.NO_SPACE("Insufficient verified local storage for cloud materialisation");
            }
            return yield entry.perform(file, "materialize", limit, token, progress);
        }
    }
}
