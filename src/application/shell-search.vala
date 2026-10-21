namespace MajorisFiles {
    [DBus(name = "org.gnome.Shell.SearchProvider2")]
    public class ShellSearchProvider : Object {
        Gtk.Application application;
        MetadataStore metadata;
        Places places;
        OperationManager operations;
        SearchController search = new SearchController();
        Gee.HashMap<string, FileItem> results = new Gee.HashMap<string, FileItem>();
        uint generation;
        Gee.List<File>? roots;
        public ShellSearchProvider(Gtk.Application application, MetadataStore metadata, Places places, OperationManager operations, Gee.List<File>? roots = null)
        {
            this.application = application; this.metadata = metadata; this.places = places; this.operations = operations;
            this.roots = roots;
        }
        public async string[] get_initial_result_set(string[] terms) throws DBusError, IOError
        {
            uint epoch = ++generation;
            search.cancellable.cancel();
            results.clear();
            string text = string.joinv(" ", terms).strip();
            if (text.length < 2 || text.length > 4096 || terms.length > 32) return {};
            var query = new SearchQuery(); query.text = text; query.scope = "everywhere";
            var found = new Gee.ArrayList<string>();
            results.clear(); application.hold();
            ulong handler = search.found.connect((item) => {
                if (epoch != generation || found.size >= 50) return;
                string id = item.file.get_uri(); results[id] = item; found.add(id);
                if (found.size == 50) search.cancellable.cancel();
            });
            uint timer = Timeout.add_seconds(5, () => { if (epoch == generation) search.cancellable.cancel(); return Source.REMOVE; });
            Source? source = MainContext.default().find_source_by_id(timer);
            try { yield search.search_roots(roots ?? places.search_roots(), query, metadata); }
            catch (Error e) {} // A bounded partial result set is valid for shell search.
            finally {
                search.disconnect(handler);
                if (source != null && !source.is_destroyed()) Source.remove(timer);
                application.release();
            }
            return found.to_array();
        }
        public async string[] get_subsearch_result_set(string[] previous_results, string[] terms) throws DBusError, IOError
        {
            return yield get_initial_result_set(terms);
        }
        public HashTable<string, Variant>[] get_result_metas(string[] identifiers) throws DBusError, IOError
        {
            HashTable<string, Variant>[] output = {};
            if (identifiers.length > 50) throw new DBusError.INVALID_ARGS("Too many result identifiers");
            foreach (var id in identifiers) {
                if (!results.has_key(id)) continue;
                var item = results[id];
                var fields = new HashTable<string, Variant>(str_hash, str_equal);
                fields["id"] = new Variant.string(id); fields["name"] = new Variant.string(item.name);
                fields["description"] = new Variant.string(item.file.get_parent().get_parse_name());
                fields["gicon"] = new Variant.string(item.info.get_icon() == null ? "text-x-generic" : item.info.get_icon().to_string());
                output += fields;
            }
            return output;
        }
        public void activate_result(string identifier, string[] terms, uint timestamp) throws DBusError, IOError
        {
            if (!results.has_key(identifier)) throw new DBusError.INVALID_ARGS("Unknown or expired search result");
            var item = results[identifier];
            var window = new FilesWindow(application, metadata, places, operations, item.directory ? item.file : item.file.get_parent());
            if (!item.directory) window.current.select_file(item.file);
            window.present();
        }
        public void launch_search(string[] terms, uint timestamp) throws DBusError, IOError
        {
            if (terms.length > 32) throw new DBusError.INVALID_ARGS("Too many search terms");
            var window = new FilesWindow(application, metadata, places, operations, File.new_for_path(Environment.get_home_dir()));
            var query = new SearchQuery(); query.text = string.joinv(" ", terms); query.scope = "everywhere";
            try { window.current.restore_session_state(new Variant("(sbb^asdd)", query.serialize(), true, true, new string[] {}, 0.0, 0.0).print(true)); }
            catch (Error e) { throw new DBusError.FAILED(e.message); }
            window.present();
        }
    }
}
