namespace MajorisFiles {
    public class TagDefinition : Object {
        public int64 id;
        public string name;
        public string color;
        public int position;
        public bool sidebar_visible;
        public TagDefinition(int64 id, string name, string color, int position, bool visible) {
            this.id = id; this.name = name; this.color = color; this.position = position; sidebar_visible = visible;
        }
        // A different URI namespace avoids treating legacy numeric names as IDs.
        public File location() { return File.new_for_uri("majoris:///tag-id/" + id.to_string()); }
    }

    public class SavedSearch : Object {
        public string name;
        public File location;
        public string query;
        public SavedSearch(string name, string location, string query)
        {
            this.name = name;
            this.location = File.new_for_uri(location);
            this.query = query;
        }
    }
    public class MetadataStore : Object {
        Sqlite.Database? db;
        string filename;
        FileMonitor? database_monitor;
        uint database_refresh;
        int64 data_version;
        string definitions_fingerprint = "";
        public string storage_error {
            get;
            private set;
            default = "";
        }
        public bool available {
            get {
                return db != null && storage_error == "";
            }
        }
        public int usage(File file)
        {
            int count;
            return int.try_parse(state("usage:" + file.get_uri(), "0"), out count) ? count.clamp(0, 1000000) : 0;
        }
        public void record_open(File file)
        {
            set_state("usage:" + file.get_uri(), (usage(file) + 1).to_string());
        }
        public signal void changed();
        public signal void tag_definitions_changed();
        public signal void tag_assignments_changed();
        public MetadataStore(string? path = null)
        {
            filename = path ?? Path.build_filename(Environment.get_user_data_dir(), "majoris-files", "metadata.db");
            DirUtils.create_with_parents(Path.get_dirname(filename), 0700);
            Sqlite.Database connection;
            if (Sqlite.Database.open(filename, out connection) != Sqlite.OK)
            {
                storage_error = "Metadata database could not be opened";
                return;
            }
            db = (owned) connection;
            FileUtils.chmod(filename, 0600);
            db.busy_timeout(1000);
            if(db.exec("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS metadata(uri TEXT PRIMARY KEY,favorite INTEGER DEFAULT 0,tags TEXT DEFAULT '',view TEXT DEFAULT 'Grid'); CREATE TABLE IF NOT EXISTS searches(name TEXT PRIMARY KEY,location TEXT,query TEXT); CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE IF NOT EXISTS identities(identity TEXT PRIMARY KEY,uri TEXT); CREATE INDEX IF NOT EXISTS identities_by_uri ON identities(uri); CREATE TABLE IF NOT EXISTS tags(name TEXT PRIMARY KEY,color TEXT DEFAULT '#3584e4',position INTEGER DEFAULT 0);") != Sqlite.OK)
                storage_error = db.errmsg();
            if (storage_error == "") {
                try { migrate_tags(); }
                catch (Error e) { storage_error = e.message; db = null; }
            }
            if (available) watch_database();
        }
        int64 database_version() {
            var stmt = prepare("PRAGMA data_version"); return stmt != null && stmt.step() == Sqlite.ROW ? stmt.column_int64(0) : 0;
        }
        string fingerprint() {
            var value = new StringBuilder();
            foreach (var tag in tag_definitions()) value.append_printf("%s|%d:%s|%s|%d|%d;", tag.id.to_string(), tag.name.length, tag.name, tag.color, tag.position, tag.sidebar_visible ? 1 : 0);
            return value.str;
        }
        void watch_database() {
            if (database_monitor != null) database_monitor.cancel();
            data_version = database_version(); definitions_fingerprint = fingerprint();
            database_monitor = monitor_for(this);
        }
        static FileMonitor? monitor_for(MetadataStore store) {
            try {
                var monitor = File.new_for_path(Path.get_dirname(store.filename)).monitor_directory(FileMonitorFlags.NONE);
                weak MetadataStore self = store; string basename = Path.get_basename(store.filename);
                monitor.changed.connect((file) => {
                    if (self == null || (file.get_basename() != basename && file.get_basename() != basename + "-wal") || self.database_refresh != 0) return;
                    self.database_refresh = Timeout.add(120, () => {
                        if (self == null) return Source.REMOVE;
                        self.database_refresh = 0; if (!self.available) return Source.REMOVE;
                        int64 version = self.database_version(); if (version == self.data_version) return Source.REMOVE;
                        self.data_version = version; string current = self.fingerprint();
                        if (current != self.definitions_fingerprint) { self.definitions_fingerprint = current; self.tag_definitions_changed(); }
                        self.tag_assignments_changed(); self.changed(); return Source.REMOVE;
                    });
                }); return monitor;
            } catch (Error e) { return null; }
        }
        protected override void dispose() {
            if (database_refresh != 0) { Source.remove(database_refresh); database_refresh = 0; }
            if (database_monitor != null) { database_monitor.cancel(); database_monitor = null; }
            base.dispose();
        }
        public string recover() throws Error
        {
            if(available)
                return "";
            db = null;
            var backup = filename + ".recovery-" + Uuid.string_random();
            foreach(var suffix in new string[] {"", "-wal", "-shm"})
            {
                var file = File.new_for_path(filename + suffix);
                if(file.query_exists())
                    file.move(File.new_for_path(backup + suffix), FileCopyFlags.NONE, null, null);
            }
            var replacement = new MetadataStore(filename);
            db = (owned)replacement.db;
            storage_error = replacement.storage_error;
            if(!available)
                throw new FileError.INVALID(storage_error + ". Previous database preserved at " + backup);
            watch_database(); tag_definitions_changed(); tag_assignments_changed(); changed();
            return backup;
        }
        public void reconcile(FileItem item)
        {
            if(!item.file.is_native() || !item.info.has_attribute("unix::inode") || !item.info.has_attribute("time::created") || item.info.get_attribute_uint64("time::created") == 0)
                return;
            var identity = "%u:%" + uint64.FORMAT + ":%" + uint64.FORMAT + ":%u";
            identity = identity.printf(item.info.get_attribute_uint32("unix::device"), item.info.get_attribute_uint64("unix::inode"), item.info.get_attribute_uint64("time::created"), item.info.get_attribute_uint32("time::created-usec"));
            var lookup = prepare("SELECT uri FROM identities WHERE identity=?");
            if(lookup == null)
                return;
            lookup.bind_text(1, identity);
            if(lookup.step() == Sqlite.ROW)
            {
                var old = File.new_for_uri(lookup.column_text(0));
                if (old.equal(item.file)) return;
                // Birth time guards inode reuse; an existing path denotes a hard link.
                if (old.query_exists()) return;
                relocate(old, item.file);
                return;
            }
            var stmt = prepare("INSERT INTO identities VALUES(?,?) ON CONFLICT(identity) DO UPDATE SET uri=excluded.uri");
            if(stmt != null)
            {
                stmt.bind_text(1, identity);
                stmt.bind_text(2, item.file.get_uri());
                stmt.step();
            }
        }
        void sql(string command) throws Error {
            if (db == null || db.exec(command) != Sqlite.OK) throw new FileError.INVALID(db == null ? _("Metadata storage is unavailable") : db.errmsg());
        }
        Sqlite.Statement statement(string query) throws Error {
            var result = prepare(query);
            if (result == null || storage_error != "") throw new FileError.INVALID(_("Metadata storage is unavailable") + ": " + storage_error);
            return (owned)result;
        }
        void done(Sqlite.Statement stmt) throws Error {
            if (stmt.step() != Sqlite.DONE) throw new FileError.INVALID(db.errmsg());
        }
        void migrate_tags() throws Error {
            if (state("tags-schema-v1") == "complete") return;
            sql("BEGIN IMMEDIATE");
            try {
                if (state("tags-schema-v1") == "complete") { sql("COMMIT"); return; }
                sql("CREATE TABLE tag_definitions(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL UNIQUE COLLATE BINARY,color TEXT NOT NULL DEFAULT '',position INTEGER NOT NULL DEFAULT 0,sidebar_visible INTEGER NOT NULL DEFAULT 1); CREATE TABLE file_tag_assignments(uri TEXT NOT NULL,tag_id INTEGER NOT NULL REFERENCES tag_definitions(id) ON DELETE CASCADE,ordinal INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(uri,tag_id)); CREATE INDEX assignments_by_tag ON file_tag_assignments(tag_id,uri); CREATE TABLE tag_uri_aliases(name TEXT PRIMARY KEY,tag_id INTEGER NOT NULL REFERENCES tag_definitions(id) ON DELETE CASCADE)");
                var definitions = statement("SELECT name,color,position FROM tags ORDER BY position,rowid");
                while (definitions.step() == Sqlite.ROW) {
                    var insert = statement("INSERT OR IGNORE INTO tag_definitions(name,color,position) VALUES(?,?,?)");
                    insert.bind_text(1, definitions.column_text(0)); insert.bind_text(2, definitions.column_text(1) ?? ""); insert.bind_int(3, definitions.column_int(2)); done(insert);
                }
                var legacy = statement("SELECT uri,tags FROM metadata WHERE tags<>''");
                while (legacy.step() == Sqlite.ROW) {
                    int ordinal = 0;
                    foreach (var raw in legacy.column_text(1).split(",")) {
                        string name = raw.strip(); if (name == "") continue;
                        var insert = statement("INSERT OR IGNORE INTO tag_definitions(name,color,position) SELECT ?,'#9CA3AF',COALESCE(MAX(position)+1,0) FROM tag_definitions"); insert.bind_text(1, name); done(insert);
                        var relation = statement("INSERT OR IGNORE INTO file_tag_assignments(uri,tag_id,ordinal) SELECT ?,id,? FROM tag_definitions WHERE name=?");
                        relation.bind_text(1, legacy.column_text(0)); relation.bind_int(2, ordinal++); relation.bind_text(3, name); done(relation);
                    }
                }
                string[] names = {"Work", "Projects", "Personal", "Important", "Archive"};
                string[] colors = {"#EF4444", "#F59E0B", "#3B82F6", "#A855F7", "#9CA3AF"};
                for (int i = 0; i < names.length; i++) {
                    var insert = statement("INSERT OR IGNORE INTO tag_definitions(name,color,position) SELECT ?,?,COALESCE(MAX(position)+1,0) FROM tag_definitions"); insert.bind_text(1, names[i]); insert.bind_text(2, colors[i]); done(insert);
                }
                sql("INSERT INTO tag_uri_aliases(name,tag_id) SELECT name,id FROM tag_definitions");
                var marker = statement("INSERT INTO state(key,value) VALUES('tags-schema-v1','complete')"); done(marker);
                sql("COMMIT");
            } catch (Error e) { db.exec("ROLLBACK"); throw e; }
        }
        public static void validate_tag_name(string name) throws Error {
            if (!name.validate() || name.strip() == "" || name != name.strip() || name.char_count() > 128 || name.contains(",")) throw new FileError.INVALID(_("Use a unique name of 1–128 characters, without commas or surrounding spaces."));
            foreach (uint8 c in name.data) if (c < 32 || c == 127) throw new FileError.INVALID(_("Tag names cannot contain control characters."));
        }
        public static string validate_tag_color(string color) throws Error {
            if (color == "") return "";
            Gdk.RGBA rgba = Gdk.RGBA();
            if (!rgba.parse(color) || rgba.alpha < 1) throw new FileError.INVALID(_("Choose an opaque tag colour."));
            return "#%02X%02X%02X".printf((uint)(rgba.red * 255 + 0.5), (uint)(rgba.green * 255 + 0.5), (uint)(rgba.blue * 255 + 0.5));
        }
        TagDefinition read_tag(Sqlite.Statement stmt) { return new TagDefinition(stmt.column_int64(0), stmt.column_text(1), stmt.column_text(2), stmt.column_int(3), stmt.column_int(4) != 0); }
        public Gee.ArrayList<TagDefinition> tag_definitions() {
            var result = new Gee.ArrayList<TagDefinition>(); var stmt = prepare("SELECT id,name,color,position,sidebar_visible FROM tag_definitions ORDER BY position,id");
            if (stmt != null) while (stmt.step() == Sqlite.ROW) result.add(read_tag(stmt)); return result;
        }
        public TagDefinition? tag_by_id(int64 id) {
            var stmt = prepare("SELECT id,name,color,position,sidebar_visible FROM tag_definitions WHERE id=?"); if (stmt == null) return null; stmt.bind_int64(1, id); return stmt.step() == Sqlite.ROW ? read_tag(stmt) : null;
        }
        public TagDefinition? tag_by_name(string name) {
            var stmt = prepare("SELECT id,name,color,position,sidebar_visible FROM tag_definitions WHERE name=?"); if (stmt == null) return null; stmt.bind_text(1, name); return stmt.step() == Sqlite.ROW ? read_tag(stmt) : null;
        }
        public static bool is_tag_location(File file) { return file.get_uri().has_prefix("majoris:///tag-id/") || file.get_uri().has_prefix("majoris:///tag/"); }
        public TagDefinition? tag_at(File location) {
            string uri = location.get_uri();
            if (uri.has_prefix("majoris:///tag-id/")) { int64 id; return int64.try_parse(uri.substring(18), out id) && id > 0 ? tag_by_id(id) : null; }
            if (!uri.has_prefix("majoris:///tag/")) return null;
            string? name = Uri.unescape_string(uri.substring(15)); if (name == null) return null;
            var alias = prepare("SELECT tag_id FROM tag_uri_aliases WHERE name=?");
            if (alias != null) { alias.bind_text(1, name); if (alias.step() == Sqlite.ROW) return tag_by_id(alias.column_int64(0)); }
            return tag_by_name(name);
        }
        void definitions_updated() { definitions_fingerprint = fingerprint(); tag_definitions_changed(); changed(); }
        public TagDefinition create_tag(string name, string color = "", Gee.List<File>? files = null) throws Error {
            validate_tag_name(name); string normalized = validate_tag_color(color);
            if (tag_by_name(name) != null) throw new FileError.CONFLICT(_("A tag with this exact name already exists."));
            if (files != null && files.size == 0) throw new FileError.INVALID(_("Select files or folders before creating an assigned tag."));
            if (files != null) foreach (var file in files) if (!taggable(file)) throw new FileError.UNSUPPORTED(_("Only real files and folders can be tagged."));
            int64 id;
            sql("BEGIN IMMEDIATE");
            try {
                var stmt = statement("INSERT INTO tag_definitions(name,color,position) SELECT ?,?,COALESCE(MAX(position)+1,0) FROM tag_definitions"); stmt.bind_text(1, name); stmt.bind_text(2, normalized); done(stmt); id = db.last_insert_rowid();
                if (files != null) {
                    var assign = statement("INSERT OR IGNORE INTO file_tag_assignments(uri,tag_id,ordinal) VALUES(?,?,(SELECT COALESCE(MAX(ordinal)+1,0) FROM file_tag_assignments WHERE uri=?))");
                    foreach (var file in files) { assign.reset(); assign.clear_bindings(); assign.bind_text(1, file.get_uri()); assign.bind_int64(2, id); assign.bind_text(3, file.get_uri()); done(assign); }
                }
                sql("COMMIT");
            } catch (Error e) { db.exec("ROLLBACK"); throw e; }
            var tag = tag_by_id(id); if (files != null) tag_assignments_changed(); definitions_updated(); return tag;
        }
        public void update_tag(int64 id, string name, string color, bool visible) throws Error {
            var old = tag_by_id(id);
            if (old == null) throw new FileError.INVALID(_("This tag no longer exists."));
            if (name != old.name) validate_tag_name(name);
            string normalized = color == old.color ? color : validate_tag_color(color);
            if (name == old.name && color == old.color && visible == old.sidebar_visible) return;
            var duplicate = tag_by_name(name); if (duplicate != null && duplicate.id != id) throw new FileError.CONFLICT(_("A tag with this exact name already exists."));
            sql("BEGIN IMMEDIATE");
            try {
                var alias = statement("INSERT OR IGNORE INTO tag_uri_aliases(name,tag_id) VALUES(?,?)"); alias.bind_text(1, old.name); alias.bind_int64(2, id); done(alias);
                var stmt = statement("UPDATE tag_definitions SET name=?,color=?,sidebar_visible=? WHERE id=?"); stmt.bind_text(1, name); stmt.bind_text(2, normalized); stmt.bind_int(3, visible ? 1 : 0); stmt.bind_int64(4, id); done(stmt); sql("COMMIT");
            } catch (Error e) { db.exec("ROLLBACK"); throw e; }
            definitions_updated();
        }
        public void move_tag(int64 id, int index) throws Error {
            var tags = tag_definitions(); TagDefinition? moving = null; foreach (var tag in tags) if (tag.id == id) moving = tag;
            if (moving == null) throw new FileError.INVALID(_("This tag no longer exists."));
            tags.remove(moving); tags.insert(index.clamp(0, tags.size), moving); sql("BEGIN IMMEDIATE");
            try { var stmt = statement("UPDATE tag_definitions SET position=? WHERE id=?"); for (int i = 0; i < tags.size; i++) { stmt.reset(); stmt.clear_bindings(); stmt.bind_int(1, i); stmt.bind_int64(2, tags[i].id); done(stmt); } sql("COMMIT"); }
            catch (Error e) { db.exec("ROLLBACK"); throw e; } definitions_updated();
        }
        public void remove_tag(int64 id) throws Error {
            var stmt = statement("DELETE FROM tag_definitions WHERE id=?"); stmt.bind_int64(1, id); done(stmt); tag_assignments_changed(); definitions_updated();
        }
        public Gee.ArrayList<TagDefinition> tags_for(File file) {
            var result = new Gee.ArrayList<TagDefinition>(); var stmt = prepare("SELECT t.id,t.name,t.color,t.position,t.sidebar_visible FROM file_tag_assignments f JOIN tag_definitions t ON t.id=f.tag_id WHERE f.uri=? ORDER BY f.ordinal,t.id");
            if (stmt != null) { stmt.bind_text(1, file.get_uri()); while (stmt.step() == Sqlite.ROW) result.add(read_tag(stmt)); } return result;
        }
        public bool has_tag(File file, int64 id) {
            var stmt = prepare("SELECT 1 FROM file_tag_assignments WHERE uri=? AND tag_id=?"); if (stmt == null) return false; stmt.bind_text(1, file.get_uri()); stmt.bind_int64(2, id); return stmt.step() == Sqlite.ROW;
        }
        public bool matches_tag(File file, string name) { foreach (var tag in tags_for(file)) if (tag.name.casefold() == name.strip().casefold()) return true; return false; }
        public Gee.ArrayList<File> files_for_tag(int64 id) {
            var files = new Gee.ArrayList<File>(); var stmt = prepare("SELECT uri FROM file_tag_assignments WHERE tag_id=? ORDER BY uri"); if (stmt != null) { stmt.bind_int64(1, id); while (stmt.step() == Sqlite.ROW) files.add(File.new_for_uri(stmt.column_text(0))); } return files;
        }
        public static bool taggable(File file) { return file.get_uri_scheme() != null && !(file.get_uri_scheme() in new string[] {"majoris", "recent", "trash"}); }
        public void set_tag_for_files(Gee.List<File> files, int64 id, bool assigned) throws Error {
            if (tag_by_id(id) == null) throw new FileError.INVALID(_("This tag no longer exists."));
            foreach (var file in files) if (!taggable(file)) throw new FileError.UNSUPPORTED(_("Only real files and folders can be tagged."));
            sql("BEGIN IMMEDIATE");
            try {
                var stmt = statement(assigned ? "INSERT OR IGNORE INTO file_tag_assignments(uri,tag_id,ordinal) VALUES(?,?,(SELECT COALESCE(MAX(ordinal)+1,0) FROM file_tag_assignments WHERE uri=?))" : "DELETE FROM file_tag_assignments WHERE uri=? AND tag_id=?");
                foreach (var file in files) { stmt.reset(); stmt.clear_bindings(); stmt.bind_text(1, file.get_uri()); stmt.bind_int64(2, id); if (assigned) stmt.bind_text(3, file.get_uri()); done(stmt); }
                sql("COMMIT");
            } catch (Error e) { db.exec("ROLLBACK"); throw e; }
            tag_assignments_changed(); changed();
        }
        public string tag_summary(File file) { string[] names = {}; foreach (var tag in tags_for(file)) names += tag.name; return string.joinv(", ", names); }
        public string tag_set_key(File file) { var ids = new Gee.ArrayList<string>(); foreach (var tag in tags_for(file)) ids.add(tag.id.to_string()); ids.sort((a, b) => strcmp(a, b)); return string.joinv(";", ids.to_array()); }
        // Compatibility adapters only. Normal UI uses stable identities and deltas.
        public void define_tag(string name, string color, int position = 0) {
            try { var tag = tag_by_name(name); if (tag == null) tag = create_tag(name, color); else update_tag(tag.id, tag.name, color, tag.sidebar_visible); var stmt = statement("UPDATE tag_definitions SET position=? WHERE id=?"); stmt.bind_int(1, position); stmt.bind_int64(2, tag.id); done(stmt); definitions_updated(); } catch (Error e) { storage_error = e.message; }
        }
        public string tag_color(string name) { var tag = tag_by_name(name); return tag == null ? "" : tag.color; }
        public void rename_tag(string from, string to) { var tag = tag_by_name(from); if (tag != null) try { update_tag(tag.id, to, tag.color, tag.sidebar_visible); } catch (Error e) {} }
        public void delete_tag(string name) { var tag = tag_by_name(name); if (tag != null) try { remove_tag(tag.id); } catch (Error e) {} }
        Sqlite.Statement? prepare(string sql) {
            if (db == null)
                return null;
            Sqlite.Statement stmt;
            if (db.prepare_v2(sql, -1, out stmt) != Sqlite.OK)
                return null;
            return (owned) stmt;
        }
        public bool favorite(File file)
        {
            var stmt = prepare("SELECT favorite FROM metadata WHERE uri=?");
            if (stmt == null)
                return false;
            stmt.bind_text(1, file.get_uri());
            return stmt.step() == Sqlite.ROW && stmt.column_int(0) == 1;
        }
        public void set_favorite(File file, bool enabled)
        {
            var stmt = prepare("INSERT INTO metadata(uri,favorite) VALUES(?,?) ON CONFLICT(uri) DO UPDATE SET favorite=excluded.favorite");
            if (stmt == null)
                return;
            stmt.bind_text(1, file.get_uri());
            stmt.bind_int(2, enabled ? 1 : 0);
            stmt.step();
            changed();
        }
        public string tags(File file) { string[] names = {}; foreach (var tag in tags_for(file)) names += tag.name; return string.joinv(",", names); }
        public void set_tags(File file, string names) {
            try {
                if (!taggable(file)) throw new FileError.UNSUPPORTED("Only real files can be tagged");
                var ids = new Gee.ArrayList<TagDefinition>();
                foreach (var raw in names.split(",")) { string name = raw.strip(); if (name == "") continue; var tag = tag_by_name(name); if (tag == null) tag = create_tag(name); ids.add(tag); }
                sql("BEGIN IMMEDIATE");
                try {
                    var clear = statement("DELETE FROM file_tag_assignments WHERE uri=?"); clear.bind_text(1, file.get_uri()); done(clear);
                    var insert = statement("INSERT OR IGNORE INTO file_tag_assignments(uri,tag_id,ordinal) VALUES(?,?,?)");
                    for (int i = 0; i < ids.size; i++) { insert.reset(); insert.clear_bindings(); insert.bind_text(1, file.get_uri()); insert.bind_int64(2, ids[i].id); insert.bind_int(3, i); done(insert); } sql("COMMIT");
                } catch (Error e) { db.exec("ROLLBACK"); throw e; }
                tag_assignments_changed(); changed();
            } catch (Error e) { storage_error = e.message; }
        }
        public Gee.ArrayList<File> favorites()
        {
            var result = new Gee.ArrayList<File>();
            var stmt = prepare("SELECT uri FROM metadata WHERE favorite=1");
            if (stmt != null)
                while (stmt.step() == Sqlite.ROW)
                    result.add(File.new_for_uri(stmt.column_text(0)));
            return result;
        }
        public void relocate(File from, File to) {
            if (from.equal(to)) return;
            try {
                string source = from.get_uri(), destination = to.get_uri();
                string prefix = source.has_suffix("/") ? source : source + "/";
                sql("BEGIN IMMEDIATE");
                try {
                    var uris = new Gee.ArrayList<string>();
                    var lookup = statement("SELECT uri FROM metadata WHERE uri=? OR (uri>=? AND uri<?) UNION SELECT uri FROM file_tag_assignments WHERE uri=? OR (uri>=? AND uri<?) UNION SELECT uri FROM identities WHERE uri=? OR (uri>=? AND uri<?)");
                    for (int i = 0; i < 3; i++) { lookup.bind_text(i * 3 + 1, source); lookup.bind_text(i * 3 + 2, prefix); lookup.bind_text(i * 3 + 3, prefix + "\x7f"); }
                    while (lookup.step() == Sqlite.ROW) uris.add(lookup.column_text(0));
                    foreach (var uri in uris) {
                        string target = uri == source ? destination : destination + "/" + uri.substring(prefix.length);
                        var clear = statement("DELETE FROM file_tag_assignments WHERE uri=?"); clear.bind_text(1, target); done(clear);
                        var clear_metadata = statement("DELETE FROM metadata WHERE uri=?"); clear_metadata.bind_text(1, target); done(clear_metadata);
                        var stmt = statement("UPDATE metadata SET uri=? WHERE uri=?"); stmt.bind_text(1, target); stmt.bind_text(2, uri); done(stmt);
                        var move = statement("UPDATE file_tag_assignments SET uri=? WHERE uri=?"); move.bind_text(1, target); move.bind_text(2, uri); done(move);
                        var identity = statement("UPDATE identities SET uri=? WHERE uri=?"); identity.bind_text(1, target); identity.bind_text(2, uri); done(identity);
                    }
                    sql("COMMIT");
                } catch (Error e) { db.exec("ROLLBACK"); throw e; }
                tag_assignments_changed(); changed();
            } catch (Error e) { storage_error = e.message; }
        }
        public void save_search(string name, File folder, string query)
        {
            var stmt = prepare("INSERT OR REPLACE INTO searches VALUES(?,?,?)");
            if (stmt == null)
                return;
            stmt.bind_text(1, name);
            stmt.bind_text(2, folder.get_uri());
            stmt.bind_text(3, query);
            stmt.step();
            changed();
        }
        public Gee.ArrayList<SavedSearch> saved_searches()
        {
            var result = new Gee.ArrayList<SavedSearch>();
            var stmt = prepare("SELECT name,location,query FROM searches ORDER BY name");
            if(stmt != null)
                while(stmt.step() == Sqlite.ROW)
                    result.add(new SavedSearch(stmt.column_text(0), stmt.column_text(1), stmt.column_text(2)));
            return result;
        }
        public Gee.ArrayList<string> all_tags() { var result = new Gee.ArrayList<string>(); foreach (var tag in tag_definitions()) result.add(tag.name); return result; }
        public Gee.ArrayList<File> tagged(string name) { var tag = tag_by_name(name); return tag == null ? new Gee.ArrayList<File>() : files_for_tag(tag.id); }
        public string state(string key, string fallback = "")
        {
            var stmt = prepare("SELECT value FROM state WHERE key=?");
            if(stmt == null)
                return fallback;
            stmt.bind_text(1, key);
            return stmt.step() == Sqlite.ROW ? stmt.column_text(0).dup() : fallback;
        }
        public void set_state(string key, string value)
        {
            var stmt = prepare("INSERT OR REPLACE INTO state VALUES(?,?)");
            if(stmt == null)
                return;
            stmt.bind_text(1, key);
            stmt.bind_text(2, value);
            stmt.step();
        }
        public void set_state_checked(string key, string value) throws Error
        {
            var stmt = prepare("INSERT OR REPLACE INTO state VALUES(?,?)");
            if (stmt == null || !available)
                throw new FileError.INVALID("Durable operation storage is unavailable");
            stmt.bind_text(1, key);
            stmt.bind_text(2, value);
            if (stmt.step() != Sqlite.DONE)
                throw new FileError.INVALID("Could not persist the operation recovery record");
        }
        public void set_states_checked(string[] keys,string[] values) throws Error {
            if(!available||db==null||keys.length!=values.length||keys.length>32)throw new FileError.INVALID("Durable operation storage is unavailable");
            if(db.exec("BEGIN IMMEDIATE")!=Sqlite.OK)throw new FileError.INVALID("Could not begin operation history transaction");
            try{
                for(int i=0;i<keys.length;i++)set_state_checked(keys[i],values[i]);
                if(db.exec("COMMIT")!=Sqlite.OK)throw new FileError.INVALID("Could not commit operation history");
            }catch(Error e){db.exec("ROLLBACK");throw e;}
        }
    }
}
