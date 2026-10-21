namespace MajorisFiles {
    public interface SearchProvider : Object {
        public signal void hit(FileItem item);
        public abstract async void search(Gee.List<File> roots, SearchQuery query, bool recursive, Cancellable token) throws Error;
    }
    public class IndexedSearchProvider : Object, SearchProvider {
        Tsparql.SparqlConnection? connection;
        public IndexedSearchProvider(Tsparql.SparqlConnection? connection = null) { this.connection = connection; }
        public async void search(Gee.List<File> roots, SearchQuery query, bool recursive, Cancellable token) throws Error
        {
            if (query.text == "" && query.content == "") return;
            if (connection == null) {
                Error? failure = null;
                foreach (var service in new string[] {"org.freedesktop.LocalSearch3", "org.freedesktop.Tracker3.Miner.Files"}) {
                    try { connection = yield Tsparql.SparqlConnection.bus_new_async(service, null, null, token); break; }
                    catch (Error e) { token.set_error_if_cancelled(); failure = e; }
                }
                if (connection == null) throw new IOError.NOT_SUPPORTED(failure == null ? "No index service is available" : failure.message);
            }
            string clause = query.content == "" ?
                "GRAPH tracker:FileSystem { ?file fts:match ~terms . BIND(fts:rank(?file) AS ?score) }" :
                "GRAPH tracker:Documents { ?content nie:isStoredAs ?file; fts:match ~terms . BIND(fts:rank(?content) AS ?score) }";
            string sparql = "SELECT DISTINCT ?url ?score WHERE { GRAPH tracker:FileSystem { ?file a nfo:FileDataObject; nie:url ?url . } " + clause + " FILTER (STRSTARTS(?url, ~root)) } ORDER BY DESC(?score) ?url LIMIT 100000";
            var statement = connection.query_statement(sparql, token);
            string terms = query.content != "" ? query.content : query.text;
            statement.bind_string("terms", "\"" + terms.replace("\"", "\"\"") + "\"");
            var seen = new Gee.HashSet<string>();
            foreach (var root in roots) {
                if (!root.is_native()) continue;
                statement.bind_string("root", root.get_uri().has_suffix("/") ? root.get_uri() : root.get_uri() + "/");
                var cursor = yield statement.execute_async(token);
                try {
                    while (yield cursor.next_async(token)) {
                        string? uri = cursor.get_string(0);
                        if (uri == null || !seen.add(uri)) continue;
                        var file = File.new_for_uri(uri);
                        if (!file.is_native() || !file.has_prefix(root) || (!recursive && !root.equal(file.get_parent()))) continue;
                        try {
                            var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                            var item = new FileItem(file, info);
                            item.relevance = cursor.get_double(1) + 100;
                            hit(item);
                        }
                        catch (IOError.CANCELLED e) { throw e; }
                        catch (Error e) {} // An index can contain deleted or inaccessible files.
                    }
                }
                finally { cursor.close(); }
            }
        }
    }
}
