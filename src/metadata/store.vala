namespace MajorisFiles {
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
        public signal void changed();
        public MetadataStore(string? path = null)
        {
            string filename = path ?? Path.build_filename(Environment.get_user_data_dir(), "majoris-files", "metadata.db");
            DirUtils.create_with_parents(Path.get_dirname(filename), 0700);
            Sqlite.Database connection;
            if (Sqlite.Database.open(filename, out connection) != Sqlite.OK)
                return;
            db = (owned) connection;
            FileUtils.chmod(filename,0600);
            db.busy_timeout(1000);
            db.exec("PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS metadata(uri TEXT PRIMARY KEY,favorite INTEGER DEFAULT 0,tags TEXT DEFAULT '',view TEXT DEFAULT 'Grid'); CREATE TABLE IF NOT EXISTS searches(name TEXT PRIMARY KEY,location TEXT,query TEXT); CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,value TEXT);");
        }
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
        public string tags(File file)
        {
            var stmt = prepare("SELECT tags FROM metadata WHERE uri=?");
            if (stmt == null)
                return "";
            stmt.bind_text(1, file.get_uri());
            return stmt.step() == Sqlite.ROW ? stmt.column_text(0).dup() : "";
        }
        public void set_tags(File file, string tags)
        {
            var stmt = prepare("INSERT INTO metadata(uri,tags) VALUES(?,?) ON CONFLICT(uri) DO UPDATE SET tags=excluded.tags");
            if (stmt == null)
                return;
            stmt.bind_text(1, file.get_uri());
            stmt.bind_text(2, tags);
            stmt.step();
            changed();
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
        public void relocate(File from, File to)
        {
            var stmt = prepare("UPDATE metadata SET uri=? WHERE uri=?");
            if (stmt == null)
                return;
            stmt.bind_text(1, to.get_uri());
            stmt.bind_text(2, from.get_uri());
            stmt.step();
            changed();
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
        public Gee.ArrayList<string> all_tags()
        {
            var result = new Gee.ArrayList<string>();
            var stmt = prepare("SELECT tags FROM metadata WHERE tags<>''");
            if(stmt != null)
                while(stmt.step() == Sqlite.ROW)
                    foreach(var tag in stmt.column_text(0).split(","))
                    {
                        var name = tag.strip();
                        if(name != "" && !result.contains(name))
                            result.add(name);
                    }
            return result;
        }
        public Gee.ArrayList<File> tagged(string tag)
        {
            var result = new Gee.ArrayList<File>();
            var stmt = prepare("SELECT uri,tags FROM metadata WHERE tags<>''");
            if(stmt != null)
                while(stmt.step() == Sqlite.ROW)
                    foreach(var stored in stmt.column_text(1).split(","))
                        if(stored.strip() == tag)
                        {
                            result.add(File.new_for_uri(stmt.column_text(0)));
                            break;
                        }
            return result;
        }
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
    }
}
