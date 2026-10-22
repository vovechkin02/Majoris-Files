namespace MajorisFiles {
    public class ExternalExtension : Object, QuickActionProvider {
        public string id;
        public string name;
        public string bus_name;
        public string object_path;
        public string[] capabilities;
        public bool enabled;
        public string failure = "";
        public string provider_id { owned get { return "extension-" + id; } }
        MetadataStore metadata;
        Gee.ArrayList<QuickAction> cached_actions = new Gee.ArrayList<QuickAction>();
        string selection_key = "";
        Gee.HashMap<string, Gee.HashMap<string, string>> fields = new Gee.HashMap<string, Gee.HashMap<string, string>>();
        Gee.HashSet<string> pending = new Gee.HashSet<string>();
        bool verified;
        public uint revision {get;private set;default=0;}
        uint request_generation;
        File manifest_file;
        string manifest_identity;
        uint owner_watch;
        string provider_owner="";
        public ExternalExtension(string manifest, bool trusted, MetadataStore metadata) throws Error
        {
            this.metadata = metadata;
            var file = File.new_for_path(manifest);
            manifest_file=file;
            var info = file.query_info("standard::size,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            if (info.get_file_type() != FileType.REGULAR || info.get_size() > 65536) throw new FileError.INVALID("Invalid extension manifest");
            var key = new KeyFile(); key.load_from_file(manifest, KeyFileFlags.NONE);
            id = key.get_string("Extension", "Id"); name = key.get_locale_string("Extension", "Name");
            bus_name = key.get_string("Extension", "BusName"); object_path = key.get_string("Extension", "ObjectPath");
            capabilities = key.get_string_list("Extension", "Capabilities");
            if (key.get_integer("Extension", "Version") != 1 || !DBus.is_name(bus_name) || !Variant.is_object_path(object_path) ||
                !Regex.match_simple("^[A-Za-z0-9_.-]{1,100}$", id) || name.length > 100 || capabilities.length > 8)
                throw new FileError.INVALID("Unsupported extension protocol or identity");
            enabled = metadata.state("extension-enabled:" + id, trusted ? "true" : "false") == "true";
            manifest_identity=Checksum.compute_for_string(ChecksumType.SHA256,key.to_data());
            owner_watch=Bus.watch_name(BusType.SESSION,bus_name,BusNameWatcherFlags.NONE,
                ()=>refresh_owner.begin(),()=>refresh_owner.begin());
        }
        async void refresh_owner(){try{var bus=yield Bus.get(BusType.SESSION);yield synchronize_owner(bus);}catch(Error e){if(provider_owner!=""){provider_owner="";invalidate();}}}
        async void synchronize_owner(DBusConnection bus) throws Error {
            var reply=yield bus.call("org.freedesktop.DBus","/org/freedesktop/DBus","org.freedesktop.DBus","GetNameOwner",new Variant("(s)",bus_name),new VariantType("(s)"),DBusCallFlags.NONE,2000,null);
            string owner=reply.get_child_value(0).get_string();if(owner!=provider_owner){provider_owner=owner;invalidate();}
        }
        void invalidate(){revision++;verified=false;cached_actions.clear();fields.clear();failure="";metadata.changed();}
        ~ExternalExtension(){if(owner_watch!=0)Bus.unwatch_name(owner_watch);}
        public void set_enabled(bool value)
        {
            enabled = value; metadata.set_state("extension-enabled:" + id, value ? "true" : "false");
            invalidate();
        }
        public async Variant call(string method, Variant? arguments, string reply, Cancellable? token = null) throws Error
        {
            if (!enabled) throw new IOError.PERMISSION_DENIED("Extension is disabled");
            var current=new KeyFile();
            try{current.load_from_file(manifest_file.get_path(),KeyFileFlags.NONE);}
            catch(Error e){invalidate();throw new IOError.NOT_FOUND("Extension was uninstalled; reopen extension preferences after reinstalling it");}
            if(Checksum.compute_for_string(ChecksumType.SHA256,current.to_data())!=manifest_identity){invalidate();throw new IOError.INVALID_DATA("Extension registration changed; reload Files before invoking it");}
            var connection = yield Bus.get(BusType.SESSION, token);
            try{yield synchronize_owner(connection);}
            catch(IOError.CANCELLED e){throw e;}
            catch(Error e){
                var activated=yield connection.call(bus_name,object_path,"com.majoris.Files.Extension1","GetVersion",null,new VariantType("(u)"),DBusCallFlags.NONE,2000,token);
                if(activated.get_child_value(0).get_uint32()!=1)throw new FileError.UNSUPPORTED("Incompatible extension protocol");
                yield synchronize_owner(connection);verified=true;
            }
            if (!verified) {
                var version = yield connection.call(provider_owner, object_path, "com.majoris.Files.Extension1", "GetVersion", null, new VariantType("(u)"), DBusCallFlags.NONE, 2000, token);
                if (version.get_child_value(0).get_uint32() != 1) throw new FileError.UNSUPPORTED("Incompatible extension protocol");
                verified = true;
            }
            return yield connection.call(provider_owner, object_path, "com.majoris.Files.Extension1", method, arguments, new VariantType(reply), DBusCallFlags.NONE, 2000, token);
        }
        static string[] uris(Gee.List<FileItem> selection)
        {
            string[] result = {};
            foreach (var item in selection) {
                // Do not pass credential-bearing remote URIs to extensions.
                try {
                    var uri = Uri.parse(item.file.get_uri(), UriFlags.HAS_PASSWORD);
                    if (uri.get_password() != null) continue;
                }
                catch (Error e) { continue; }
                result += item.file.get_uri();
            }
            return result;
        }
        public async void prepare(Gee.List<FileItem> selection)
        {
            uint epoch = ++request_generation;
            cached_actions.clear(); selection_key = string.joinv("\n", uris(selection));
            if (!enabled || !("actions" in capabilities) || selection.size == 0 || selection.size > 1000) return;
            try {
                var result = yield call("GetActions", new Variant("(^as)", uris(selection)), "(a(ss))");
                if (epoch != request_generation || !enabled) return;
                var actions = result.get_child_value(0);
                if (actions.n_children() > 64) throw new FileError.INVALID("Too many extension actions");
                for (size_t i = 0; i < actions.n_children(); i++) {
                    var action = actions.get_child_value(i);
                    string action_id = action.get_child_value(0).get_string(), label = action.get_child_value(1).get_string();
                    if (action_id == "" || action_id.length > 100 || label == "" || label.length > 200) throw new FileError.INVALID("Invalid extension action");
                    cached_actions.add(new QuickAction(action_id, name + ": " + label));
                }
                failure = "";
            }
            catch (Error e) { failure = e.message; cached_actions.clear(); verified = false; }
        }
        public Gee.List<QuickAction> actions(Gee.List<FileItem> selection)
        {
            return enabled && selection_key == string.joinv("\n", uris(selection)) ? cached_actions : new Gee.ArrayList<QuickAction>();
        }
        public async void execute(string action_id, Gee.List<FileItem> selection, Gtk.Window parent) throws Error
        {
            yield prepare(selection);
            bool allowed = false; foreach (var action in cached_actions) if (action.id == action_id) allowed = true;
            if (!allowed) throw new FileError.UNSUPPORTED("The extension action is no longer available");
            yield call("Activate", new Variant("(s^as)", action_id, uris(selection)), "()");
        }
        public async Gee.HashMap<string, string> file_info(FileItem item,Cancellable? token=null) throws Error
        {
            var selection = new Gee.ArrayList<FileItem>(); selection.add(item);
            if (uris(selection).length == 0) throw new FileError.UNSUPPORTED("Credential-bearing locations are not passed to extensions");
            var result = new Gee.HashMap<string, string>();
            var reply = yield call("GetFileInfo", new Variant("(s)", item.file.get_uri()), "(a{ss})",token);
            var values = reply.get_child_value(0);
            if (values.n_children() > 64) throw new FileError.INVALID("Too much extension metadata");
            var iterator = values.iterator(); string key, value;
            while (iterator.next("{ss}", out key, out value)) {
                if (key.length > 100 || value.length > 16384) throw new FileError.INVALID("Extension metadata exceeds the limit");
                result[key] = value;
            }
            return result;
        }
        public static string safe_uri(FileItem item) throws Error
        {
            var selection = new Gee.ArrayList<FileItem>(); selection.add(item);
            var result = uris(selection);
            if (result.length != 1) throw new FileError.UNSUPPORTED("Credential-bearing locations are not passed to extensions");
            return result[0];
        }
        public string column_value(FileItem item, string key)
        {
            if (!enabled) return "";
            string uri = item.file.get_uri();
            if (fields.has_key(uri)) return fields[uri][key] ?? "";
            if (pending.size < 32 && pending.add(uri)) load_info.begin(item);
            return "…";
        }
        async void load_info(FileItem item)
        {
            string uri = item.file.get_uri();
            try { fields[uri] = yield file_info(item); }
            catch (Error e) { fields[uri] = new Gee.HashMap<string, string>(); failure = e.message; }
            pending.remove(uri);
            if (fields.size > 512) { var retained = fields[uri]; fields.clear(); fields[uri] = retained; }
            metadata.changed();
        }
    }
    public class ExternalColumn : Object, ColumnProvider {
        ExternalExtension extension;
        string field;
        string label;
        Gee.HashMap<string,string> sort_values=new Gee.HashMap<string,string>();
        Gee.HashMap<string,string> sort_stamps=new Gee.HashMap<string,string>();
        uint sort_revision=uint.MAX;
        public bool sort_ready {get{return extension.enabled&&sort_revision==extension.revision;}}
        public string title { owned get { return label; } }
        public ExternalColumn(ExternalExtension extension, string field, string label) { this.extension = extension; this.field = field; this.label = label; }
        public string text(FileItem item, MetadataStore metadata) { return extension.column_value(item, field); }
        public int compare(FileItem a, FileItem b, MetadataStore metadata) { return Paths.natural_compare(sort_values[a.file.get_uri()]??"",sort_values[b.file.get_uri()]??""); }
        public void release_sort(){sort_values.clear();sort_stamps.clear();sort_revision=uint.MAX;}
        public async void prepare_sort(ListModel model,Cancellable token) throws Error {
            if(model.get_n_items()>100000)throw new IOError.NO_SPACE("Extension sorting exceeds the 100,000-item limit");
            yield extension.call("GetVersion",null,"(u)",token);uint revision=extension.revision;
            var items=new Gee.ArrayList<FileItem>();for(uint i=0;i<model.get_n_items();i++)items.add((FileItem)model.get_item(i));
            var values=new Gee.HashMap<string,string>();var stamps=new Gee.HashMap<string,string>();uint64 bytes=0;int64 deadline=get_monotonic_time()+30*1000000L;
            for(int start=0;start<items.size;start+=32){
                token.set_error_if_cancelled();if(get_monotonic_time()>deadline)throw new IOError.TIMED_OUT("Preparing extension sort exceeded 30 seconds");
                int pending=0;bool dispatching=true;Error? failure=null;
                for(int i=start;i<int.min(start+32,items.size);i++){
                    var item=items[i];string uri=item.file.get_uri();string stamp=new Variant("(stt)",item.info.get_attribute_string("etag::value")??"",item.info.get_attribute_uint64("time::modified")*1000000+item.info.get_attribute_uint32("time::modified-usec"),item.bytes).print(true);stamps[uri]=stamp;
                    if(sort_revision==revision&&sort_stamps[uri]==stamp&&sort_values.has_key(uri)){values[uri]=sort_values[uri];bytes+=values[uri].length;if(bytes>16*1024*1024){failure=new IOError.NO_SPACE("Extension sort values exceed 16 MiB");break;}continue;}
                    pending++;
                    extension.file_info.begin(item,token,(obj,res)=>{
                        try{var fields=extension.file_info.end(res);string value=fields[field]??"";bytes+=value.length;if(bytes>16*1024*1024)throw new IOError.NO_SPACE("Extension sort values exceed 16 MiB");values[item.file.get_uri()]=value;}
                        catch(Error e){if(failure==null)failure=e;}
                        pending--;if(pending==0&&!dispatching)Idle.add(()=>{prepare_sort.callback();return Source.REMOVE;});
                    });
                }
                dispatching=false;if(pending>0)yield;else{Idle.add(()=>{prepare_sort.callback();return Source.REMOVE;});yield;}if(failure!=null)throw failure;
            }
            token.set_error_if_cancelled();if(revision!=extension.revision)throw new IOError.BUSY("Extension restarted while sort values were loading");
            sort_values=values;sort_stamps=stamps;sort_revision=revision;
        }
    }
    public class ExtensionManager : Object {
        static ExtensionManager? instance;
        public Gee.ArrayList<ExternalExtension> extensions = new Gee.ArrayList<ExternalExtension>();
        public static ExtensionManager get_default(MetadataStore metadata)
        {
            if (instance == null) instance = new ExtensionManager(metadata);
            return instance;
        }
        public ExtensionManager(MetadataStore metadata, string[]? folders = null)
        {
            string[] locations = folders ?? new string[] {"/usr/share/majoris-files/extensions", Path.build_filename(Environment.get_user_data_dir(), "majoris-files", "extensions")};
            var seen = new Gee.HashSet<string>();
            foreach (var folder in locations) {
                try {
                    var directory = Dir.open(folder); string? name;
                    while ((name = directory.read_name()) != null && extensions.size < 128) {
                        if (!name.has_suffix(".extension")) continue;
                        try {
                            var extension = new ExternalExtension(Path.build_filename(folder, name), folder == "/usr/share/majoris-files/extensions", metadata);
                            if (seen.add(extension.id)) extensions.add(extension);
                        }
                        catch (Error e) {} // Invalid manifests are not providers.
                    }
                }
                catch (Error e) {}
            }
        }
        public async void prepare(Gee.List<FileItem> selection)
        {
            int pending = 0; bool dispatching = true;
            foreach (var extension in extensions) {
                pending++;
                extension.prepare.begin(selection, (obj, res) => {
                    extension.prepare.end(res); pending--;
                    if (pending == 0 && !dispatching) Idle.add(() => { prepare.callback(); return Source.REMOVE; });
                });
            }
            dispatching = false;
            if (pending > 0) yield;
        }
        public async void columns(Browser browser)
        {
            var signature=new StringBuilder();foreach(var extension in extensions)signature.append(extension.id+":"+extension.enabled.to_string()+":"+extension.revision.to_string()+";");
            if(browser.extension_columns_signature==signature.str)return;browser.extension_columns_signature=signature.str;
            var retained=new Gee.HashSet<string>();var providers=new Gee.ArrayList<ExternalColumn>();
            int total = 0;
            foreach (var extension in extensions) {
                if (!extension.enabled || !("columns" in extension.capabilities)) continue;
                try {
                    var reply = yield extension.call("GetColumns", null, "(a(ss))");
                    var columns = reply.get_child_value(0);
                    if (columns.n_children() > 16) throw new FileError.INVALID("Too many extension columns");
                    for (size_t i = 0; i < columns.n_children(); i++) {
                        if (total++ >= 32) break;
                        var column = columns.get_child_value(i);
                        string title=extension.name+": "+column.get_child_value(1).get_string();retained.add(title);
                        if(!browser.has_column(title))providers.add(new ExternalColumn(extension,column.get_child_value(0).get_string(),title));
                    }
                }
                catch (Error e) { extension.failure = e.message; }
            }
            if(browser.extension_columns_signature!=signature.str)return;
            browser.remove_extension_columns(retained);
            foreach(var provider in providers)try{browser.register_column(provider);}catch(Error e){}
        }
    }
}
