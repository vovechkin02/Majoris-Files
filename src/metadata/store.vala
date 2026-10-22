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
        string filename;
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
            if(db.exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS metadata(uri TEXT PRIMARY KEY,favorite INTEGER DEFAULT 0,tags TEXT DEFAULT '',view TEXT DEFAULT 'Grid'); CREATE TABLE IF NOT EXISTS searches(name TEXT PRIMARY KEY,location TEXT,query TEXT); CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE IF NOT EXISTS identities(identity TEXT PRIMARY KEY,uri TEXT); CREATE TABLE IF NOT EXISTS tags(name TEXT PRIMARY KEY,color TEXT DEFAULT '#3584e4',position INTEGER DEFAULT 0);") != Sqlite.OK)
                storage_error = db.errmsg();
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
            changed();
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
                if(!old.equal(item.file))
                {
                    // Birth time guards inode reuse; an existing path denotes a hard link.
                    if(old.query_exists())
                        return;
                    relocate(old, item.file);
                }
            }
            var stmt = prepare("INSERT INTO identities VALUES(?,?) ON CONFLICT(identity) DO UPDATE SET uri=excluded.uri");
            if(stmt != null)
            {
                stmt.bind_text(1, identity);
                stmt.bind_text(2, item.file.get_uri());
                stmt.step();
            }
        }
        public void define_tag(owned string name, string color, int position = 0)
        {
            name = name.strip();
            if(name == "" || name.contains(",") || name.contains("\n"))
                return;
            var parsed = Gdk.RGBA();
            if(!parsed.parse(color))
                return;
            var stmt = prepare("INSERT INTO tags VALUES(?,?,?) ON CONFLICT(name) DO UPDATE SET color=excluded.color,position=excluded.position");
            if(stmt != null)
            {
                stmt.bind_text(1, name);
                stmt.bind_text(2, color);
                stmt.bind_int(3, position);
                stmt.step();
                changed();
            }
        }
        public string tag_color(string name)
        {
            var stmt = prepare("SELECT color FROM tags WHERE name=?");
            if(stmt == null)
                return "#3584e4";
            stmt.bind_text(1, name);
            return stmt.step() == Sqlite.ROW ? stmt.column_text(0).dup() : "#3584e4";
        }
        public void rename_tag(string from, owned string to)
        {
            to = to.strip();
            if(to == "" || to.contains(",") || to.contains("\n"))
                return;
            if(to != from && all_tags().contains(to))
                return;
            var files = tagged(from);
            foreach(var file in files)
            {
                string[] replacement = {};
                foreach(var tag in tags(file).split(","))
                    replacement += tag.strip() == from ? to : tag.strip();
                set_tags(file, string.joinv(",", replacement));
            }
            var stmt = prepare("UPDATE tags SET name=? WHERE name=?");
            if(stmt != null)
            {
                stmt.bind_text(1, to);
                stmt.bind_text(2, from);
                stmt.step();
            }
            changed();
        }
        public void delete_tag(string name)
        {
            foreach(var file in tagged(name))
            {
                string[] replacement = {};
                foreach(var tag in tags(file).split(","))
                    if(tag.strip() != name)
                        replacement += tag.strip();
                set_tags(file, string.joinv(",", replacement));
            }
            var stmt = prepare("DELETE FROM tags WHERE name=?");
            if(stmt != null)
            {
                stmt.bind_text(1, name);
                stmt.step();
            }
            changed();
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
            var defined = prepare("SELECT name FROM tags ORDER BY position,name");
            if(defined != null)
                while(defined.step() == Sqlite.ROW)
                    result.add(defined.column_text(0));
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
