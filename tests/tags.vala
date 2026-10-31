using MajorisFiles;
string database() throws Error { return Path.build_filename(DirUtils.make_tmp("majoris-tags-test-XXXXXX"), "metadata.db"); }
Sqlite.Database open_db(string path) { Sqlite.Database db; assert(Sqlite.Database.open(path, out db) == Sqlite.OK); db.busy_timeout(1000); return (owned)db; }
int64 number(Sqlite.Database db, string sql) { Sqlite.Statement stmt; assert(db.prepare_v2(sql, -1, out stmt) == Sqlite.OK); assert(stmt.step() == Sqlite.ROW); return stmt.column_int64(0); }
Gee.ArrayList<File> file_list(params string[] uris) { var result = new Gee.ArrayList<File>(); foreach (var uri in uris) result.add(File.new_for_uri(uri)); return result; }
void defaults() throws Error {
    string path = database(); var store = new MetadataStore(path); assert(store.available);
    string[] names = {"Work", "Projects", "Personal", "Important", "Archive"}; string[] colors = {"#EF4444", "#F59E0B", "#3B82F6", "#A855F7", "#9CA3AF"};
    var tags = store.tag_definitions(); assert(tags.size == 5);
    for (int i = 0; i < 5; i++) { assert(tags[i].name == names[i] && tags[i].color == colors[i] && tags[i].position == i && tags[i].sidebar_visible); assert(store.files_for_tag(tags[i].id).size == 0); }
    int64 work = tags[0].id; store.update_tag(work, "Business", tags[0].color, true); store.remove_tag(tags[4].id);
    store.update_tag(tags[2].id, "Personal", "#123456", true); store.update_tag(tags[3].id, "Important", tags[3].color, false);
    var reopened = new MetadataStore(path); assert(reopened.available && reopened.tag_definitions().size == 4 && reopened.tag_by_name("Work") == null && reopened.tag_by_name("Archive") == null);
    assert(reopened.tag_by_name("Business").id == work && reopened.tag_by_name("Personal").color == "#123456" && !reopened.tag_by_name("Important").sidebar_visible);
    var numeric = reopened.create_tag("123"); assert(reopened.tag_at(File.new_for_uri("majoris:///tag/123")).id == numeric.id);
    assert(reopened.tag_at(File.new_for_uri("majoris:///tag/Work")).id == work);
    assert(reopened.tag_at(numeric.location()).id == numeric.id);
    reopened.create_tag("work"); bool duplicate = false; try { reopened.create_tag("work"); } catch (Error e) { duplicate = true; } assert(duplicate);
    foreach (var invalid in new string[] {"", " ", "leading ", "a,b", "a\nb", string.nfill(129, 'a')}) { bool rejected = false; try { reopened.create_tag(invalid); } catch (Error e) { rejected = true; } assert(rejected); }
    assert(reopened.available);
}
void migration() throws Error {
    string path = database(); var db = open_db(path);
    assert(db.exec("CREATE TABLE tags(name TEXT PRIMARY KEY,color TEXT,position INTEGER); CREATE TABLE metadata(uri TEXT PRIMARY KEY,favorite INTEGER,tags TEXT,view TEXT); INSERT INTO tags VALUES('Work','#abcdef',8),('資料','#12ab34',3),('work','#000000',9); INSERT INTO metadata VALUES('file:///tmp/a',1,'Work,Implicit,Work,資料','List'),('sftp://example.test/folder/b',0,'Implicit,work','Gallery')") == Sqlite.OK);
    var store = new MetadataStore(path); assert(store.available); var work = store.tag_by_name("Work"); assert(work.color == "#abcdef" && work.position == 8);
    assert(store.tag_by_name("資料").position == 3 && store.tag_by_name("Implicit").color == "#9CA3AF");
    assert(store.favorite(File.new_for_uri("file:///tmp/a")) && store.tags_for(File.new_for_uri("file:///tmp/a")).size == 3);
    assert(store.files_for_tag(store.tag_by_name("Implicit").id).size == 2 && store.tag_by_name("work").id != work.id);
    assert(number(db, "SELECT count(*) FROM file_tag_assignments") == 5 && number(db, "SELECT count(*) FROM metadata WHERE view='List'") == 1);
    assert(db.exec("CREATE TRIGGER assignments_not_rewritten BEFORE UPDATE ON file_tag_assignments BEGIN SELECT RAISE(ABORT,'No assignment rewrites'); END") == Sqlite.OK);
    store.update_tag(work.id, "Paid work", "#abcdef", false); assert(store.has_tag(File.new_for_uri("file:///tmp/a"), work.id));
    assert(store.tag_at(File.new_for_uri("majoris:///tag/Work")).id == work.id);
    db.exec("DROP TRIGGER assignments_not_rewritten"); store.remove_tag(work.id);
    assert(store.favorite(File.new_for_uri("file:///tmp/a")) && store.tags_for(File.new_for_uri("file:///tmp/a")).size == 2);
    assert(new MetadataStore(path).tag_by_name("Work") == null);
    // DDL and assignment conversion are rolled back together on a schema failure.
    string broken_path = database(); var broken = open_db(broken_path);
    broken.exec("CREATE TABLE metadata(uri TEXT PRIMARY KEY,favorite INTEGER,tags TEXT,view TEXT); INSERT INTO metadata VALUES('file:///keep',1,'Keep','Grid'); CREATE TABLE tag_uri_aliases(unsupported TEXT)");
    var failed = new MetadataStore(broken_path); assert(!failed.available);
    assert(number(broken, "SELECT count(*) FROM sqlite_master WHERE name='tag_definitions'") == 0);
    assert(number(broken, "SELECT count(*) FROM metadata WHERE favorite=1 AND tags='Keep'") == 1);
    assert(number(broken, "SELECT count(*) FROM state WHERE key='tags-schema-v1'") == 0);
}
void bulk_and_lifecycle() throws Error {
    string path = database(); var store = new MetadataStore(path); int changes = 0; store.tag_assignments_changed.connect(() => changes++);
    var files = file_list("file:///tmp/a", "file:///tmp/b", "sftp://example.test/folder/c"); var work = store.tag_by_name("Work"); var personal = store.tag_by_name("Personal");
    store.set_tag_for_files(files, work.id, true); assert(changes == 1); store.set_tag_for_files(file_list("file:///tmp/a"), personal.id, true);
    store.set_tag_for_files(files, work.id, false); assert(store.has_tag(files[0], personal.id) && !store.has_tag(files[0], work.id));
    var created = store.create_tag("During assignment", "", files); foreach (var file in files) assert(store.has_tag(file, created.id));
    bool rejected = false; try { store.set_tag_for_files(file_list("file:///tmp/a", "majoris:///tag-id/1"), work.id, true); } catch (Error e) { rejected = true; } assert(rejected && !store.has_tag(files[0], work.id));
    store.set_favorite(files[0], true); store.relocate(files[0], File.new_for_uri("file:///tmp/renamed")); assert(store.available && store.has_tag(File.new_for_uri("file:///tmp/renamed"), personal.id) && !store.has_tag(files[0], personal.id));
    assert(store.favorite(File.new_for_uri("file:///tmp/renamed")));
    store.set_tag_for_files(file_list("file:///tmp/tree/child", "file:///tmp/tree/deep/file"), work.id, true); store.relocate(File.new_for_uri("file:///tmp/tree"), File.new_for_uri("file:///tmp/moved"));
    assert(store.has_tag(File.new_for_uri("file:///tmp/moved/child"), work.id) && store.has_tag(File.new_for_uri("file:///tmp/moved/deep/file"), work.id));
    store.set_tag_for_files(file_list("file:///tmp/original"), personal.id, true); assert(!store.has_tag(File.new_for_uri("file:///tmp/copied"), personal.id));
    var places = new Places(store); int sidebar_changes = 0; places.changed.connect(() => sidebar_changes++);
    int devices = -1, tags = -1, network = -1; for (int i = 0; i < places.entries.size; i++) { var place = places.entries[i]; if (place.section == "Devices") devices = i; if (place.section == "Tags" && tags == -1) tags = i; if (place.file.has_uri_scheme("network")) network = i; } assert(devices < tags && tags < network);
    store.set_tag_for_files(files, work.id, true); assert(sidebar_changes == 0);
    store.update_tag(work.id, work.name, work.color, false); assert(sidebar_changes == 1); foreach (var place in places.entries) assert(place.tag == null || place.tag.id != work.id);
    assert(store.has_tag(files[1], work.id));
}
void performance() throws Error {
    string path = database(); var store = new MetadataStore(path); for (int i = 0; i < 995; i++) store.create_tag("Performance %04d".printf(i)); assert(store.tag_definitions().size == 1000);
    var files = new Gee.ArrayList<File>(); for (int i = 0; i < 10000; i++) files.add(File.new_for_uri("file:///performance/item-%05d".printf(i)));
    int changes = 0; store.changed.connect(() => changes++); int64 started = get_monotonic_time();
    store.set_tag_for_files(files, store.tag_by_name("Work").id, true); store.set_tag_for_files(files, store.tag_by_name("Projects").id, true);
    assert(changes == 2 && store.files_for_tag(store.tag_by_name("Work").id).size == 10000);
    var work = store.tag_by_name("Work"); store.update_tag(work.id, "Renamed performance", work.color, true); assert(store.files_for_tag(work.id).size == 10000);
    var db = open_db(path); assert(number(db, "SELECT count(*) FROM file_tag_assignments") == 20000);
    Sqlite.Statement plan; assert(db.prepare_v2("EXPLAIN QUERY PLAN SELECT uri FROM file_tag_assignments WHERE tag_id=1", -1, out plan) == Sqlite.OK); assert(plan.step() == Sqlite.ROW && plan.column_text(3).contains("assignments_by_tag"));
    Test.message("10,000-file bulk/query/rename: %.3f seconds", (get_monotonic_time() - started) / 1000000.0);
}
void large_migration() throws Error {
    string path = database(); var db = open_db(path);
    assert(db.exec("CREATE TABLE tags(name TEXT PRIMARY KEY,color TEXT,position INTEGER); CREATE TABLE metadata(uri TEXT PRIMARY KEY,favorite INTEGER,tags TEXT,view TEXT); BEGIN") == Sqlite.OK);
    Sqlite.Statement tag_insert; db.prepare_v2("INSERT INTO tags VALUES(?,'#123456',?)", -1, out tag_insert);
    for (int i = 0; i < 1000; i++) { tag_insert.reset(); tag_insert.bind_text(1, "Legacy %04d".printf(i)); tag_insert.bind_int(2, i); assert(tag_insert.step() == Sqlite.DONE); }
    Sqlite.Statement file_insert; db.prepare_v2("INSERT INTO metadata VALUES(?,1,'Legacy 0001,Legacy 0999,Legacy 0001','List')", -1, out file_insert);
    for (int i = 0; i < 10000; i++) { file_insert.reset(); file_insert.bind_text(1, "sftp://example.test/items/%05d".printf(i)); assert(file_insert.step() == Sqlite.DONE); }
    db.exec("COMMIT"); int64 started = get_monotonic_time(); var store = new MetadataStore(path);
    assert(store.available && store.tag_definitions().size == 1005 && store.files_for_tag(store.tag_by_name("Legacy 0001").id).size == 10000);
    assert(number(db, "SELECT count(*) FROM file_tag_assignments") == 20000 && number(db, "SELECT count(*) FROM metadata WHERE favorite=1 AND view='List'") == 10000);
    db.exec("UPDATE metadata SET tags='Stale legacy values'"); assert(store.tags_for(File.new_for_uri("sftp://example.test/items/00000")).size == 2 && store.tag_by_name("Stale legacy values") == null);
    Test.message("1,000-definition / 10,000-file migration: %.3f seconds", (get_monotonic_time() - started) / 1000000.0);
}
void external_updates() throws Error {
    string path = database(); var reader = new MetadataStore(path); var writer = new MetadataStore(path); int changes = 0; reader.tag_definitions_changed.connect(() => changes++);
    var created = writer.create_tag("Another process");
    var loop = new MainLoop(); uint attempts = 0; Timeout.add(50, () => { if (changes != 0 || ++attempts > 30) { loop.quit(); return Source.REMOVE; } return Source.CONTINUE; }); loop.run();
    assert(changes == 1 && reader.tag_by_id(created.id) != null);
    var query = new SearchQuery(); query.tag = created.name;
    var files = file_list("file:///tmp/external"); writer.set_tag_for_files(files, created.id, true); assert(query.matches(new FileItem(files[0], new FileInfo()), reader));
    writer.update_tag(created.id, "Renamed outside", "#123456", true); assert(query.matches(new FileItem(files[0], new FileInfo()), reader));
    var persisted = SearchQuery.deserialize(query.serialize()); assert(persisted.tag_id == created.id && persisted.matches(new FileItem(files[0], new FileInfo()), reader));
}
int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/tags/defaults", () => { try { defaults(); } catch (Error e) { error("%s", e.message); } });
    Test.add_func("/tags/migration", () => { try { migration(); } catch (Error e) { error("%s", e.message); } });
    Test.add_func("/tags/bulk-lifecycle-sidebar", () => { try { bulk_and_lifecycle(); } catch (Error e) { error("%s", e.message); } });
    Test.add_func("/tags/performance", () => { try { performance(); } catch (Error e) { error("%s", e.message); } });
    Test.add_func("/tags/large-migration", () => { try { large_migration(); } catch (Error e) { error("%s", e.message); } });
    Test.add_func("/tags/external-updates", () => { try { external_updates(); } catch (Error e) { error("%s", e.message); } });
    return Test.run();
}
