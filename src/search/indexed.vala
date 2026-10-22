namespace MajorisFiles {
    public interface SearchProvider : Object {
        public signal void hit(FileItem item);
        public abstract async void search(Gee.List<File> roots, SearchQuery query, bool recursive, Cancellable token) throws Error;
    }
    public interface SearchCoverage : Object {
        public abstract async bool covers(File root, bool recursive, Cancellable token) throws Error;
    }
    public interface CoveredSearchProvider : SearchProvider {
        public abstract async bool covers(File root, SearchQuery query, bool recursive, Cancellable token) throws Error;
    }
    public class SystemIndexCoverage : Object, SearchCoverage {
        public async bool covers(File root, bool recursive, Cancellable token) throws Error {
            if (!root.is_native()) return false;
            var source = SettingsSchemaSource.get_default(); if (source == null) return false;
            SettingsSchema? schema = source.lookup("org.freedesktop.Tracker3.Miner.Files", true);
            if (schema == null) schema = source.lookup("org.freedesktop.Tracker.Miner.Files", true);
            if (schema == null) return false;
            foreach (var key in new string[] {"index-recursive-directories", "index-single-directories", "ignored-directories", "ignored-directories-with-content", "ignored-files", "enable-monitors"})
                if (!schema.has_key(key)) return false;
            var settings = new Settings.full(schema, null, null);
            if (!settings.get_boolean("enable-monitors") || settings.get_strv("ignored-files").length != 0 || settings.get_strv("ignored-directories-with-content").length != 0) return false;
            foreach (var pattern in settings.get_strv("ignored-directories"))
                if (!pattern.has_prefix(".") || pattern.contains("/")) return false; // GIO also omits hidden descendants.
            bool configured = false;
            foreach (var value in settings.get_strv("index-recursive-directories")) {
                var folder = location(value);
                if (folder != null && (root.equal(folder) || root.has_prefix(folder))) configured = true;
            }
            if (!recursive)
                foreach (var value in settings.get_strv("index-single-directories")) {
                    var folder = location(value); if (folder != null && root.equal(folder)) configured = true;
                }
            if (!configured) return false;
            // Nested mounts can have independent exclusion policies. Unknown
            // coverage remains a filesystem scan, never an inferred guarantee.
            foreach (var mount in VolumeMonitor.get().get_mounts())
                if (mount.get_root().has_prefix(root)) return false;
            var bus = yield Bus.get(BusType.SESSION, token);
            foreach (var service in new string[] {"org.freedesktop.LocalSearch3", "org.freedesktop.Tracker3.Miner.Files"}) {
                try {
                    var status = yield bus.call(service, "/org/freedesktop/Tracker3/Miner/Files", "org.freedesktop.Tracker3.Miner", "GetStatus", null, new VariantType("(s)"), DBusCallFlags.NO_AUTO_START, 1000, token);
                    if (status.get_child_value(0).get_string() == "") return false;
                    var progress = yield bus.call(service, "/org/freedesktop/Tracker3/Miner/Files", "org.freedesktop.Tracker3.Miner", "GetProgress", null, new VariantType("(d)"), DBusCallFlags.NO_AUTO_START, 1000, token);
                    var pauses = yield bus.call(service, "/org/freedesktop/Tracker3/Miner/Files", "org.freedesktop.Tracker3.Miner", "GetPauseDetails", null, new VariantType("(asas)"), DBusCallFlags.NO_AUTO_START, 1000, token);
                    return progress.get_child_value(0).get_double() >= 1 && pauses.get_child_value(0).n_children() == 0;
                }
                catch (IOError.CANCELLED e) { throw e; }
                catch (Error e) {}
            }
            return false;
        }
        static File? location(string value) {
            if (value == "$HOME" || value == "~") return File.new_for_path(Environment.get_home_dir());
            string[] names = {"&DESKTOP", "&DOCUMENTS", "&DOWNLOAD", "&MUSIC", "&PICTURES", "&PUBLIC_SHARE", "&TEMPLATES", "&VIDEOS"};
            UserDirectory[] directories = {UserDirectory.DESKTOP, UserDirectory.DOCUMENTS, UserDirectory.DOWNLOAD, UserDirectory.MUSIC, UserDirectory.PICTURES, UserDirectory.PUBLIC_SHARE, UserDirectory.TEMPLATES, UserDirectory.VIDEOS};
            for (int i = 0; i < names.length; i++) if (value == names[i]) {
                string? path = Environment.get_user_special_dir(directories[i]);
                return path == null || path == Environment.get_home_dir() ? null : File.new_for_path(path);
            }
            return Path.is_absolute(value) ? File.new_for_path(value) : null;
        }
    }
    public class IndexedSearchProvider : Object, SearchProvider, CoveredSearchProvider {
        Tsparql.SparqlConnection? connection;
        SearchCoverage coverage;
        Gee.HashSet<string> completed = new Gee.HashSet<string>();
        uint generation;
        public IndexedSearchProvider(Tsparql.SparqlConnection? connection = null, SearchCoverage? coverage = null) { this.connection = connection; this.coverage = coverage ?? new SystemIndexCoverage(); }
        public async bool covers(File root, SearchQuery query, bool recursive, Cancellable token) throws Error {
            // The miner's filesystem progress does not certify that the separate
            // extractor has indexed every byte that direct text scanning reads.
            if (query.content != "" && coverage is SystemIndexCoverage) return false;
            return completed.contains(root.get_uri()) && (yield coverage.covers(root, recursive, token));
        }
        public async void search(Gee.List<File> roots, SearchQuery query, bool recursive, Cancellable token) throws Error
        {
            completed.clear();
            uint epoch = ++generation;
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
                "GRAPH tracker:FileSystem { ?file nfo:fileName ?name . FILTER(CONTAINS(tracker:case-fold(?name), ~filename)) } BIND(IF(tracker:case-fold(?name) = ~filename, 30, IF(STRSTARTS(tracker:case-fold(?name), ~filename), 20, 10)) AS ?score)" :
                "GRAPH tracker:Documents { ?content nie:isStoredAs ?file; fts:match ~terms . BIND(fts:rank(?content) AS ?score) }";
            string sparql = "SELECT DISTINCT ?url ?score WHERE { GRAPH tracker:FileSystem { ?file a nfo:FileDataObject; nie:url ?url . } " + clause + " FILTER (STRSTARTS(?url, ~root)) } ORDER BY DESC(?score) ?url LIMIT 100001";
            var statement = connection.query_statement(sparql, token);
            string terms = query.content != "" ? query.content : query.text;
            if (query.content == "") statement.bind_string("filename", query.text.casefold());
            else statement.bind_string("terms", "\"" + terms.replace("\"", "\"\"") + "\"");
            var seen = new Gee.HashSet<string>();
            foreach (var root in roots) {
                if (!root.is_native()) continue;
                statement.bind_string("root", root.get_uri().has_suffix("/") ? root.get_uri() : root.get_uri() + "/");
                var cursor = yield statement.execute_async(token);
                uint count = 0;
                try {
                    while (yield cursor.next_async(token)) {
                        if (++count > 100000) throw new IOError.NO_SPACE("Indexed result limit reached; filesystem reconciliation is required");
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
                if (epoch == generation) completed.add(root.get_uri());
            }
        }
    }
}
