using MajorisFiles;
int main(string[] args)
{
    Test.init(ref args);
    Test.add_func("/filesystem/split-join", () => run_async.begin(false));
    Test.add_func("/filesystem/missing-parts", () => run_async.begin(true));
    // Async tests run within their own bounded main loop.
    Test.add_func("/filesystem/operations", () => operations_test());
    Test.add_func("/filesystem/durable-retry", () => durable_retry_test());
    Test.add_func("/filesystem/archive-roundtrip", () => archive_test());
    Test.add_func("/filesystem/content-counts-and-identity", () => {
        var loop = new MainLoop();
        bool passed = false;
        content_case.begin((obj, res) => { try { content_case.end(res);
                                                 passed = true;
                                           }
                                           catch(Error e) { error("%s", e.message);
                                           }
                                           loop.quit();
            });
        uint watchdog = Timeout.add_seconds(10, () => { error("Content/count test timed out");
            });
        loop.run();
        Source.remove(watchdog);
        assert(passed);
    });
    Test.add_func("/filesystem/chooser-destinations-and-import", () => {
        var loop = new MainLoop();
        chooser_files_case.begin((obj, res) => {
            try { chooser_files_case.end(res); }
            catch (Error e) { error("%s", e.message); }
            loop.quit();
        });
        uint timeout = Timeout.add_seconds(10, () => { error("Chooser filesystem test timed out"); });
        loop.run();
        Source.remove(timeout);
    });
    Test.add_func("/filesystem/replacement-recovery", () => {
        var loop = new MainLoop();
        replacement_case.begin((obj, res) => {
            try { replacement_case.end(res); } catch (Error e) { error("%s", e.message); }
            loop.quit();
        });
        loop.run();
    });
    Test.add_func("/search/indexed-document-content", () => {
        var loop = new MainLoop();
        indexed_content_case.begin((obj, res) => {
            try { indexed_content_case.end(res); } catch (Error e) { error("%s", e.message); }
            loop.quit();
        });
        loop.run();
    });
    Test.add_func("/search/coverage-and-unicode", () => {
        var loop = new MainLoop();
        indexed_coverage_case.begin((obj, res) => { try { indexed_coverage_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        uint timer = Timeout.add_seconds(20, () => { error("Index coverage fixture timed out"); });
        loop.run(); Source.remove(timer);
    });
    Test.add_func("/archive/sevenzip-volumes-and-encryption", () => {
        if (Environment.find_program_in_path("7z") == null && Environment.find_program_in_path("7zz") == null) { Test.skip("7-Zip is unavailable"); return; }
        var loop = new MainLoop();
        sevenzip_case.begin((obj, res) => { try { sevenzip_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    Test.add_func("/filesystem/batch-rename-swap-undo", () => {
        var loop = new MainLoop();
        batch_rename_case.begin((obj, res) => { try { batch_rename_case.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        loop.run();
    });
    return Test.run();
}
async void batch_rename_case() throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-batch-XXXXXX"));
    var first = root.get_child("first.txt"); var second = root.get_child("second.txt");
    FileUtils.set_contents(first.get_path(), "first"); FileUtils.set_contents(second.get_path(), "second");
    var metadata = new MetadataStore(root.get_child("state.db").get_path());
    metadata.set_tags(first, "First"); metadata.set_tags(second, "Second");
    var manager = new OperationManager(metadata);
    var sources = new Gee.ArrayList<File>(); sources.add(first); sources.add(second);
    var names = new Gee.ArrayList<string>(); names.add("second.txt"); names.add("first.txt");
    yield manager.batch_rename(sources, names);
    assert(metadata.tags(first) == "Second" && metadata.tags(second) == "First");
    // Reopen the journal to verify the logical rename group survives a restart.
    manager = new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
    yield manager.undo();
    string contents; FileUtils.get_contents(first.get_path(), out contents); assert(contents == "first");
    assert(metadata.tags(first) == "First");
    yield manager.redo(); FileUtils.get_contents(first.get_path(), out contents); assert(contents == "second");
    yield OperationManager.remove_tree(root, new Cancellable());
}
async void sevenzip_case() throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-7z-XXXXXX"));
    var source = root.get_child("payload.bin");
    uint8[] bytes = new uint8[3 * 1024 * 1024];
    // Nontrivial data plus store mode forces multiple native volumes.
    for (int i = 0; i < bytes.length; i++) bytes[i] = (uint8)(i % 251);
    yield source.replace_contents_async(bytes, null, false, FileCreateFlags.PRIVATE, null, null);
    var sources = new Gee.ArrayList<File>(); sources.add(source);
    yield SevenZip.create(sources, root.get_child("Backup.7z"), 1024 * 1024, 0, null, new Job("Create volumes"));
    assert(root.get_child("Backup.7z.001").query_exists() && root.get_child("Backup.7z.003").query_exists());
    yield SevenZip.verify(root.get_child("Backup.7z.001"), null, new Job("Verify volumes"));
    yield ArchiveService.extract(root.get_child("Backup.7z.001"), root.get_child("extracted"), new Job("Extract volumes"));
    var restored = root.get_child("extracted/payload.bin");
    assert((yield SplitService.checksum(source, ChecksumType.SHA256, new Cancellable())) == (yield SplitService.checksum(restored, ChecksumType.SHA256, new Cancellable())));
    yield SevenZip.create(sources, root.get_child("Encrypted.7z"), 0, 1, "fixture-only", new Job("Encrypt"));
    yield SevenZip.verify(root.get_child("Encrypted.7z"), "fixture-only", new Job("Verify encrypted"));
    bool rejected = false;
    try { yield SevenZip.verify(root.get_child("Encrypted.7z"), "wrong-fixture", new Job("Wrong password")); }
    catch (Error e) { rejected = true; }
    assert(rejected);
    yield SevenZip.create(sources,root.get_child("Secret.7z"),1024*1024,0,"fixture-only",new Job("Encrypted volumes"));
    yield ArchiveService.extract(root.get_child("Secret.7z.001"),root.get_child("secret-output"),new Job("Extract encrypted volumes"),"fixture-only");
    assert((yield SplitService.checksum(source,ChecksumType.SHA256,new Cancellable()))==(yield SplitService.checksum(root.get_child("secret-output/payload.bin"),ChecksumType.SHA256,new Cancellable())));
    rejected=false;
    try{yield ArchiveService.extract(root.get_child("Secret.7z.001"),root.get_child("wrong-output"),new Job("Wrong password"),"wrong-fixture");}catch(Error e){rejected=true;}
    assert(rejected&&!root.get_child("wrong-output").query_exists());
    uint8[] corrupted;yield root.get_child("Secret.7z.002").load_contents_async(null,out corrupted,null);corrupted[512]^=1;
    yield root.get_child("Secret.7z.002").replace_contents_async(corrupted,null,false,FileCreateFlags.NONE,null,null);
    rejected=false;try{yield ArchiveService.extract(root.get_child("Secret.7z.001"),root.get_child("corrupt-output"),new Job("Corrupt volume"),"fixture-only");}catch(Error e){rejected=true;}
    assert(rejected&&!root.get_child("corrupt-output").query_exists());
    yield root.get_child("Secret.7z.002").delete_async(Priority.DEFAULT,null);
    rejected=false;
    try{yield ArchiveService.extract(root.get_child("Secret.7z.001"),root.get_child("missing-output"),new Job("Missing volume"),"fixture-only");}catch(Error e){rejected=true;}
    assert(rejected&&!root.get_child("missing-output").query_exists());
    FileUtils.set_contents(root.get_child("Backup.7z.majoris-incomplete").get_path(),"Interrupted fixture publication");
    rejected=false;try{yield SevenZip.verify(root.get_child("Backup.7z.001"),null,new Job("Interrupted set"));}catch(Error e){rejected=true;}
    assert(rejected);
    yield OperationManager.remove_tree(root, new Cancellable());
}
async void replacement_case() throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-replacement-XXXXXX"));
    var target = root.get_child("report.txt");
    var backup = root.get_child(".majoris-backup-fixture");
    FileUtils.set_contents(target.get_path(), "previous data");
    var metadata = new MetadataStore(root.get_child("state.db").get_path());
    var journal = new ReplacementJournal(metadata);
    yield journal.prepare(target, backup);
    yield target.move_async(backup, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    FileUtils.set_contents(target.get_path(), "new or interrupted output");
    // A new journal simulates restarting after the destination was moved aside.
    var restarted = new ReplacementJournal(new MetadataStore(root.get_child("state.db").get_path()));
    assert(restarted.records.size == 1);
    var restored = yield restarted.restore(restarted.records[0], new Cancellable());
    assert(!restored.equal(target));
    string old_contents, current_contents;
    FileUtils.get_contents(restored.get_path(), out old_contents);
    FileUtils.get_contents(target.get_path(), out current_contents);
    assert(old_contents == "previous data" && current_contents == "new or interrupted output");
    assert(new ReplacementJournal(metadata).records.size == 0);
    yield OperationManager.remove_tree(root, new Cancellable());
}
async void indexed_content_case() throws Error
{
    string? extractor = Environment.find_program_in_path("localsearch-extractor-3");
    if (extractor == null && FileUtils.test("/usr/libexec/localsearch-extractor-3", FileTest.IS_EXECUTABLE)) extractor = "/usr/libexec/localsearch-extractor-3";
    if (extractor == null) { Test.skip("System document extractor not installed"); return; }
    var root = File.new_for_path(DirUtils.make_tmp("majoris-index-fixture-XXXXXX"));
    var pdf = root.get_child("report.pdf");
    var surface = new Cairo.PdfSurface(pdf.get_path(), 300, 200);
    var cr = new Cairo.Context(surface);
    cr.move_to(10, 40); cr.show_text("MajorisIndexedNeedle"); cr.show_page(); surface.finish();
    var word = root.get_child("word"); yield word.make_directory_async(Priority.DEFAULT, null);
    FileUtils.set_contents(word.get_child("document.xml").get_path(), "<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t>MajorisIndexedNeedle</w:t></w:r></w:p></w:body></w:document>");
    FileUtils.set_contents(root.get_child("[Content_Types].xml").get_path(), "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>");
    var entries = new Gee.ArrayList<File>(); entries.add(word); entries.add(root.get_child("[Content_Types].xml"));
    var docx = root.get_child("letter.docx");
    yield ArchiveService.compress(entries, docx, "zip", new Job("Index fixture"));
    var token = new Cancellable();
    var connection = yield Tsparql.SparqlConnection.new_async(Tsparql.SparqlConnectionFlags.NONE, null, File.new_for_uri("resource:///org/freedesktop/tracker/nepomuk"), token);
    foreach (var file in new File[] {pdf, docx}) {
        var process = new Subprocess.newv({extractor, "--file=" + file.get_path(), "--mime=" + (file.equal(pdf) ? "application/pdf" : "application/vnd.openxmlformats-officedocument.wordprocessingml.document"), "--output-format=turtle"}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
        string output, errors;
        yield process.communicate_utf8_async(null, token, out output, out errors);
        if (!process.get_successful()) throw new IOError.FAILED("Document extraction failed: " + errors);
        assert(output.contains("MajorisIndexedNeedle"));
        yield connection.deserialize_async(Tsparql.DeserializeFlags.NONE, Tsparql.RdfFormat.TURTLE, "http://tracker.api.gnome.org/ontology/v3/tracker#Documents", new MemoryInputStream.from_data(output.data), token);
        // The system miner adds the storage relation after extraction.
        yield connection.update_async("INSERT DATA { GRAPH tracker:Documents { <" + file.get_uri() + "> nie:isStoredAs <" + file.get_uri() + "> . } }", token);
        yield connection.update_async("INSERT DATA { GRAPH tracker:FileSystem { <" + file.get_uri() + "> a nfo:FileDataObject; nie:url \"" + file.get_uri() + "\"; nfo:fileName \"" + file.get_basename() + "\" . } }", token);
    }
    var provider = new IndexedSearchProvider(connection);
    var query = new SearchQuery(); query.content = "MajorisIndexedNeedle";
    var roots = new Gee.ArrayList<File>(); roots.add(root);
    var found = new Gee.HashSet<string>();
    provider.hit.connect((item) => { assert(item.relevance >= 100); found.add(item.name); });
    yield provider.search(roots, query, true, token);
    assert(found.contains("report.pdf") && found.contains("letter.docx"));
    connection.close();
    yield OperationManager.remove_tree(root, token);
}
async void chooser_files_case() throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-chooser-files-XXXXXX"));
    var source = root.get_child("source.txt");
    FileUtils.set_contents(source.get_path(), "test contents");
    var imported = yield ChooserImport.download(source, new Cancellable(), root.get_child("imports"));
    assert(imported.is_native() && !imported.equal(source));
    assert((yield SplitService.checksum(source, ChecksumType.SHA512, new Cancellable())) ==
           (yield SplitService.checksum(imported, ChecksumType.SHA512, new Cancellable())));
    yield imported.delete_async(Priority.DEFAULT, null);
    yield imported.get_parent().delete_async(Priority.DEFAULT, null);
    var abandoned = root.get_child("imports/.pending-2147483646-abandoned");
    yield abandoned.make_directory_async(Priority.DEFAULT, null);
    FileUtils.set_contents(abandoned.get_child("partial").get_path(), "incomplete");
    yield ChooserImport.cleanup_abandoned(root.get_child("imports"), new Cancellable());
    assert(!abandoned.query_exists());
    var large = root.get_child("large.bin");
    var output = yield large.create_async(FileCreateFlags.PRIVATE, Priority.DEFAULT, null);
    ((Seekable)output).truncate(65 * 1024 * 1024, null);
    yield output.close_async(Priority.DEFAULT, null);
    uint64 transferred = 0;
    imported = yield ChooserImport.download(large, new Cancellable(), root.get_child("imports"), new ImportPolicy(), (done, total) => { transferred = done; assert(done <= total); });
    assert(transferred == 65 * 1024 * 1024);
    yield imported.delete_async(Priority.DEFAULT, null);
    yield imported.get_parent().delete_async(Priority.DEFAULT, null);
    var cancelled = new Cancellable();
    cancelled.cancel();
    bool rejected = false;
    try { yield ChooserImport.download(source, cancelled, root.get_child("imports")); }
    catch (IOError.CANCELLED e) { rejected = true; }
    assert(rejected);
    var options = new VariantBuilder(VariantType.VARDICT);
    var names = new VariantBuilder(new VariantType("aay"));
    names.add_value(new Variant.bytestring("source.txt"));
    names.add_value(new Variant.bytestring("source.txt"));
    options.add("{sv}", "files", names.end());
    var parsed = new ChooserOptions(true, options.end(), true);
    var outputs = yield parsed.destinations(root, new Cancellable());
    assert(outputs.size == 2 && outputs[0].get_basename() == "source (1).txt" && outputs[1].get_basename() == "source (2).txt");
    var metadata = new MetadataStore(root.get_child("state.db").get_path());
    var job = new OperationManager(metadata).start("Split without manifest");
    yield SplitService.split(source, root, 4, job, false);
    assert(!root.get_child("source.txt.parts.json").query_exists());
    assert(root.get_child("source.txt.part001").query_exists());
    yield OperationManager.remove_tree(root, new Cancellable());
}
async void content_case() throws Error
{
    var temp = DirUtils.make_tmp("majoris-content-XXXXXX");
    var root = File.new_for_path(temp);
    yield root.get_child("folder").make_directory_async(Priority.DEFAULT, null);
    FileUtils.set_contents(Path.build_filename(temp, "folder", "report.txt"), "A Unicode café report");
    FileUtils.set_contents(Path.build_filename(temp, "folder", "other.txt"), "unrelated");
    yield root.get_child("linked").make_symbolic_link_async(root.get_child("folder").get_path(), Priority.DEFAULT, null);
    var query = new SearchQuery();
    query.content = "CAFÉ";
    assert(SearchQuery.deserialize(query.serialize()).content == "CAFÉ");
    var search = new SearchController();
    uint found = 0;
    search.found.connect((item) => { assert(item.name == "report.txt");
                                     found++;
        });
    yield search.search(root, query);
    assert(found == 1);
    found = 0;
    yield search.search(root, query, null, false);
    assert(found == 0);
    var search_roots = new Gee.ArrayList<File>();
    search_roots.add(root);
    search_roots.add(root.get_child("folder"));
    search_roots.add(root);
    search_roots.add(root.get_child("missing"));
    yield search.search_roots(search_roots, query);
    assert(found == 1);
    assert(search.unreadable == 1 && search.scanned == 3);
    bool cancelled = false;
    ulong cancellation = search.found.connect(() => search.cancellable.cancel());
    try {
        yield search.search_roots(search_roots, query);
    }
    catch(IOError.CANCELLED e) {
        cancelled = true;
    }
    search.disconnect(cancellation);
    assert(cancelled);
    found = 0;
    yield search.search(root, query);
    assert(found == 1 && search.unreadable == 0);
    var suggestion_metadata = new MetadataStore(Path.build_filename(temp, "suggestions.db"));
    var completion = new LocationSuggestions(suggestion_metadata);
    completion.remember(root.get_child("folder"));
    completion.remember(root.get_child("folder"));
    completion.remember(File.new_for_uri("sftp://alice:secret@example.test/private"));
    assert(completion.history().size == 1);
    var suggestions = yield completion.suggest("fol", root, new Cancellable());
    assert(suggestions.size == 1 && suggestions[0].equal(root.get_child("folder")));
    suggestions = yield completion.suggest(root.get_path() + "/", root, new Cancellable());
    assert(suggestions.size >= 1);
    foreach(var suggestion in suggestions)
        assert(suggestion.get_basename() != "other.txt");
    var cancelled_suggestions = new Cancellable();
    cancelled_suggestions.cancel();
    bool suggestion_cancelled = false;
    try {
        yield completion.suggest("fol", root, cancelled_suggestions);
    }
    catch(IOError.CANCELLED e) {
        suggestion_cancelled = true;
    }
    assert(suggestion_cancelled);
    var roots = new Gee.ArrayList<File>();
    roots.add(root.get_child("folder"));
    var counts = new FileCounts();
    yield counts.scan(roots, new Cancellable());
    assert(counts.files == 2 && counts.folders == 1 && counts.unreadable == 0);
    var file = root.get_child("folder/report.txt");
    var permission_roots = new Gee.ArrayList<File>();
    permission_roots.add(root);
    yield PermissionService.apply(permission_roots, 0600, 0700, true, null, null, new Cancellable());
    var permission_info = yield file.query_info_async("unix::mode", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
    assert((permission_info.get_attribute_uint32("unix::mode") & 0777) == 0600);
    var folder_info = yield root.get_child("folder").query_info_async("unix::mode", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    assert((folder_info.get_attribute_uint32("unix::mode") & 0777) == 0700);
    var metadata = new MetadataStore(Path.build_filename(temp, "meta.db"));
    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    metadata.reconcile(new FileItem(file, info));
    metadata.set_favorite(file, true);
    metadata.set_tags(file, "Work");
    var renamed = yield file.set_display_name_async("renamed.txt", Priority.DEFAULT, null);
    var renamed_info = yield renamed.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
    metadata.reconcile(new FileItem(renamed, renamed_info));
    if(info.has_attribute("time::created") && info.get_attribute_uint64("time::created") != 0)
    {
        assert(metadata.favorite(renamed));
        assert(metadata.tags(renamed) == "Work");
    }
    yield OperationManager.remove_tree(root, new Cancellable());
}
void archive_test()
{
    var loop = new MainLoop();
    bool passed = false;
    archive_case.begin((obj, res) => { try { archive_case.end(res);
                                             passed = true;
                                       }
                                       catch(Error e) { error("%s", e.message);
                                       }
                                       loop.quit();
        });
    uint timeout = Timeout.add_seconds(15, () => { error("Archive test timed out");
        });
    loop.run();
    Source.remove(timeout);
    assert(passed);
}
async void archive_case() throws Error
{
    var temp = DirUtils.make_tmp("majoris-archive-XXXXXX");
    var root = File.new_for_path(temp);
    FileUtils.set_contents(Path.build_filename(temp, "hello.txt"), "hello archive");
    var files = new Gee.ArrayList<File>();
    files.add(root.get_child("hello.txt"));
    var job = new Job("archive test");
    foreach(var format in new string[] {"zip", "7z", "tar", "tar.gz", "tar.xz"})
    {
        var archive = root.get_child("test." + format);
        yield ArchiveService.compress(files, archive, format, job);
        assert(job.current.contains(Paths.size(13))&&job.current.contains("archived"));
        var target = root.get_child("extracted-" + format);
        yield ArchiveService.extract(archive, target, job);
        assert(job.current.contains(Paths.size(13))&&job.current.contains("extracted"));
        string result;
        FileUtils.get_contents(target.get_child("hello.txt").get_path(), out result);
        assert(result == "hello archive");
    }
    var malicious = root.get_child("malicious.tar");
    var encrypted = root.get_child("encrypted.zip");
    yield ArchiveService.compress(files, encrypted, "zip", job, "fixture-password");
    bool wrong_password = false;
    try {
        yield ArchiveService.extract(encrypted, root.get_child("wrong-password"), job, "incorrect");
    }
    catch(Error e) {
        wrong_password = true;
    }
    assert(wrong_password && !root.get_child("wrong-password").query_exists());
    var decrypted = root.get_child("decrypted");
    yield ArchiveService.extract(encrypted, decrypted, job, "fixture-password");
    string decrypted_text;
    FileUtils.get_contents(decrypted.get_child("hello.txt").get_path(), out decrypted_text);
    assert(decrypted_text == "hello archive");
    var writer = new Archive.Write();
    writer.set_format_pax_restricted();
    writer.open_filename(malicious.get_path());
    var entry = new Archive.Entry();
    entry.set_pathname("../escaped.txt");
    entry.set_filetype(Archive.FileType.IFREG);
    entry.set_size(4);
    entry.set_perm(0600);
    writer.write_header(entry);
    writer.write_data("oops".data);
    writer.close();
    bool rejected = false;
    var target = root.get_child("unsafe");
    try {
        yield ArchiveService.extract(malicious, target, job);
    }
    catch(Error e) {
        rejected = true;
    }
    assert(rejected);
    assert(!root.get_child("escaped.txt").query_exists());
    assert(!target.query_exists());
    yield OperationManager.remove_tree(root, new Cancellable());
}
async void run_async(bool missing)
{
    // This function is invoked from a synchronous test; keep the test alive until completion.
    var loop = new MainLoop();
    bool passed = false;
    split_case.begin(missing, (obj, res) => { try { split_case.end(res);
                                                    passed = true;
                                              }
                                              catch(Error e) { error("%s", e.message);
                                              }
                                              loop.quit();
        });
    uint timeout = Timeout.add_seconds(10, () => { error("Filesystem test timed out");
                                                   return Source.REMOVE;
        });
    loop.run();
    Source.remove(timeout);
    assert(passed);
}
async void split_case(bool missing) throws Error
{
    var temp = DirUtils.make_tmp("majoris-split-XXXXXX");
    var root = File.new_for_path(temp);
    string original = "abcdefghijklmno";
    FileUtils.set_contents(Path.build_filename(temp, "original.bin"), original);
    var source = root.get_child("original.bin");
    var parts = root.get_child("parts");
    yield parts.make_directory_async(Priority.DEFAULT, null);
    var job = new Job("test");
    yield SplitService.split(source, parts, 4, job);
    var output = root.get_child("output");
    yield output.make_directory_async(Priority.DEFAULT, null);
    if(missing)
    {
        yield parts.get_child("original.bin.part003").delete_async(Priority.DEFAULT, null);
        bool rejected = false;
        try {
            yield SplitService.join(parts.get_child("original.bin.parts.json"), output, job);
        }
        catch(Error e) {
            rejected = true;
        }
        assert(rejected);
        assert(!output.get_child("original.bin").query_exists());
    }
    else {
        yield SplitService.join(parts.get_child("original.bin.parts.json"), output, job);
        string result;
        FileUtils.get_contents(output.get_child("original.bin").get_path(), out result);
        assert(result == original);
        assert((yield SplitService.checksum(source, ChecksumType.SHA256, job.cancellable)) == (yield SplitService.checksum(output.get_child("original.bin"), ChecksumType.SHA256, job.cancellable)));
        var raw = root.get_child("raw-output");
        yield raw.make_directory_async(Priority.DEFAULT, null);
        yield SplitService.join_raw(parts.get_child("original.bin.part002"), raw, job);
        FileUtils.get_contents(raw.get_child("original.bin").get_path(), out result);
        assert(result == original);
    }
    yield OperationManager.remove_tree(root, new Cancellable());
}
void operations_test()
{
    var loop = new MainLoop();
    bool passed = false;
    operation_case.begin((obj, res) => { try { operation_case.end(res);
                                               passed = true;
                                         }
                                         catch(Error e) { error("%s", e.message);
                                         }
                                         loop.quit();
        });
    uint timeout = Timeout.add_seconds(10, () => { error("Operations test timed out");
                                                   return Source.REMOVE;
        });
    loop.run();
    Source.remove(timeout);
    assert(passed);
}
async void operation_case() throws Error
{
    var temp = DirUtils.make_tmp("majoris-operations-XXXXXX");
    var root = File.new_for_path(temp);
    var metadata = new MetadataStore(Path.build_filename(temp, "metadata.db"));
    var manager = new OperationManager(metadata);
    yield manager.new_folder(root, "folder");
    assert(root.get_child("folder").query_exists());
    yield manager.undo();
    assert(!root.get_child("folder").query_exists());
    yield manager.redo();
    assert(root.get_child("folder").query_exists());
    var protected_folder = root.get_child("folder");
    var saved_folder = root.get_child("saved-folder");
    yield protected_folder.move_async(saved_folder, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    yield protected_folder.make_directory_async(Priority.DEFAULT, null);
    manager = new OperationManager(new MetadataStore(Path.build_filename(temp, "metadata.db")));
    bool replacement_rejected = false;
    try {
        yield manager.undo();
    }
    catch(MajorisFiles.FileError.CONFLICT e) {
        replacement_rejected = true;
    }
    assert(replacement_rejected && protected_folder.query_exists() && saved_folder.query_exists());
    yield protected_folder.delete_async(Priority.DEFAULT, null);
    yield saved_folder.move_async(protected_folder, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    yield manager.undo();
    assert(!protected_folder.query_exists());
    yield manager.redo();
    assert(protected_folder.query_exists());
    FileUtils.set_contents(Path.build_filename(temp, "original.txt"), "content");
    var original = root.get_child("original.txt");
    yield manager.rename(original, "renamed.txt");
    assert(root.get_child("renamed.txt").query_exists());
    manager = new OperationManager(new MetadataStore(Path.build_filename(temp, "metadata.db")));
    yield manager.undo();
    assert(original.query_exists());
    var files = new Gee.ArrayList<File>();
    files.add(original);
    yield manager.run(OperationKind.COPY, files, root.get_child("folder"));
    assert(root.get_child("folder/original.txt").query_exists());
    var links = root.get_child("links");
    yield links.make_directory_async(Priority.DEFAULT, null);
    yield manager.run(OperationKind.LINK, files, links);
    var created_link = links.get_child("original.txt");
    var link_info = yield created_link.query_info_async("standard::is-symlink,standard::symlink-target", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
    assert(link_info.get_is_symlink() && link_info.get_symlink_target() == original.get_path());
    manager = new OperationManager(new MetadataStore(Path.build_filename(temp, "metadata.db")));
    yield manager.undo();
    assert(!created_link.query_exists() && original.query_exists());
    yield manager.redo();
    assert(created_link.query_exists());
    yield manager.run(OperationKind.LINK, files, links);
    var conflict_job = (Job)manager.jobs.get_item(manager.jobs.get_n_items() - 1);
    assert(conflict_job.error != "" && original.query_exists() && created_link.query_exists());
    var retry_target = root.get_child("retry-target");
    yield retry_target.make_directory_async(Priority.DEFAULT, null);
    var pending = new Gee.ArrayList<File>();
    pending.add(original);
    var missing = root.get_child("missing.txt");
    pending.add(missing);
    yield manager.run(OperationKind.COPY, pending, retry_target);
    var failed = (Job)manager.jobs.get_item(manager.jobs.get_n_items() - 1);
    assert(failed.error != "" && failed.can_retry && failed.progress < 1);
    assert(retry_target.get_child("original.txt").query_exists());
    FileUtils.set_contents(missing.get_path(), "recovered");
    yield manager.retry(failed);
    var retried = (Job)manager.jobs.get_item(manager.jobs.get_n_items() - 1);
    assert(retried.done && retried.error == "" && !failed.can_retry);
    assert(retry_target.get_child("missing.txt").query_exists());
    // Completed jobs cannot be replayed by a second click.
    uint job_count = manager.jobs.get_n_items();
    yield manager.retry(failed);
    assert(manager.jobs.get_n_items() == job_count);
    var grouped = root.get_child("grouped");
    yield grouped.make_directory_async(Priority.DEFAULT, null);
    var group_sources = new Gee.ArrayList<File>();
    group_sources.add(original);
    group_sources.add(missing);
    yield manager.run(OperationKind.MOVE, group_sources, grouped);
    manager = new OperationManager(new MetadataStore(Path.build_filename(temp, "metadata.db")));
    yield manager.undo();
    assert(original.query_exists() && missing.query_exists());
    assert(!grouped.get_child("original.txt").query_exists() && !grouped.get_child("missing.txt").query_exists());
    yield manager.redo();
    assert(!original.query_exists() && !missing.query_exists());
    assert(grouped.get_child("original.txt").query_exists() && grouped.get_child("missing.txt").query_exists());
    yield grouped.get_child("original.txt").move_async(root.get_child("held-original.txt"), FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    FileUtils.set_contents(grouped.get_child("original.txt").get_path(), "replacement");
    bool group_rejected = false;
    try {
        yield manager.undo();
    }
    catch(MajorisFiles.FileError.CONFLICT e) {
        group_rejected = true;
    }
    assert(group_rejected && grouped.get_child("missing.txt").query_exists() && !missing.query_exists());
    // A destructive recursive operation must delete the link rather than its target.
    var outside = root.get_child("outside");
    yield outside.make_directory_async(Priority.DEFAULT, null);
    FileUtils.set_contents(Path.build_filename(temp, "outside", "keep.txt"), "keep");
    var link = root.get_child("folder/link");
    yield link.make_symbolic_link_async(outside.get_path(), Priority.DEFAULT, null);
    yield OperationManager.remove_tree(root.get_child("folder"), new Cancellable());
    assert(outside.get_child("keep.txt").query_exists());
    yield OperationManager.remove_tree(root, new Cancellable());
}

void durable_retry_test()
{
    var loop = new MainLoop();
    durable_retry_case.begin((obj, res) => { try { durable_retry_case.end(res);
                                             }
                                             catch(Error e) { error("%s", e.message);
                                             }
                                             loop.quit();
        });
    uint watchdog = Timeout.add_seconds(10, () => { error("Durable retry timed out");
        });
    loop.run();
    Source.remove(watchdog);
}
async void durable_retry_case() throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-durable-XXXXXX"));
    var destination = root.get_child("destination");
    destination.make_directory();
    var source = root.get_child("source.txt");
    FileUtils.set_contents(source.get_path(), "durable contents");
    var metadata = new MetadataStore(root.get_child("metadata.db").get_path());
    var manager = new OperationManager(metadata);
    manager.jobs.items_changed.connect((position, removed, added) => {
        if(added > 0)
        {
            var job = (Job)manager.jobs.get_item(position);
            job.notify["current"].connect(() => job.cancellable.cancel());
        }
    });
    var files = new Gee.ArrayList<File>();
    files.add(source);
    yield manager.run(OperationKind.COPY, files, destination);
    assert(((Job)manager.jobs.get_item(0)).cancelled);
    var restarted = new OperationManager(new MetadataStore(root.get_child("metadata.db").get_path()));
    assert(restarted.jobs.get_n_items() == 1);
    var recovered = (Job)restarted.jobs.get_item(0);
    assert(recovered.can_retry && recovered.done);
    // A replacement source must block retry without creating an output.
    var held = root.get_child("held.txt");
    yield source.move_async(held, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    FileUtils.set_contents(source.get_path(), "replacement");
    bool blocked = false;
    try {
        yield restarted.retry(recovered);
    }
    catch(MajorisFiles.FileError.CONFLICT e) {
        blocked = true;
    }
    assert(blocked && !destination.get_child("source.txt").query_exists() && recovered.can_retry);
    yield source.delete_async(Priority.DEFAULT, null);
    yield held.move_async(source, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
    yield restarted.retry(recovered);
    assert(destination.get_child("source.txt").query_exists());
    var completed = new OperationManager(new MetadataStore(root.get_child("metadata.db").get_path()));
    assert(completed.jobs.get_n_items() == 0);
    yield OperationManager.remove_tree(root, new Cancellable());
}

class FixtureIndexCoverage : Object, MajorisFiles.SearchCoverage {
    File root;
    public FixtureIndexCoverage(File root) { this.root = root; }
    public async bool covers(File location, bool recursive, Cancellable token) throws Error { token.set_error_if_cancelled(); return location.equal(root); }
}
async void indexed_coverage_case() throws Error {
    var root = File.new_for_path(DirUtils.make_tmp("majoris-index-coverage-XXXXXX"));
    var indexed = root.get_child("indexed"); var unindexed = root.get_child("unindexed");
    yield indexed.make_directory_async(Priority.DEFAULT, null); yield unindexed.make_directory_async(Priority.DEFAULT, null);
    var nested = indexed.get_child("nested"); yield nested.make_directory_async(Priority.DEFAULT, null);
    var files = new File[] {indexed.get_child("Straße-needle.txt"), nested.get_child("needle-two.txt")};
    var connection = yield Tsparql.SparqlConnection.new_async(Tsparql.SparqlConnectionFlags.NONE, null, File.new_for_uri("resource:///org/freedesktop/tracker/nepomuk"), null);
    foreach (var file in files) {
        FileUtils.set_contents(file.get_path(), "fixture");
        yield connection.update_async("INSERT DATA { GRAPH tracker:FileSystem { <" + file.get_uri() + "> a nfo:FileDataObject; nie:url \"" + file.get_uri() + "\"; nfo:fileName \"" + file.get_basename() + "\" . } }", null);
    }
    FileUtils.set_contents(unindexed.get_child("needle-local.txt").get_path(), "fixture");
    var provider = new IndexedSearchProvider(connection, new FixtureIndexCoverage(indexed));
    var controller = new SearchController(); controller.indexed = provider;
    var found = new Gee.HashSet<string>(); controller.found.connect((item) => found.add(item.file.get_uri()));
    var roots = new Gee.ArrayList<File>(); roots.add(indexed);
    var query = new SearchQuery(); query.text = "needle";
    yield controller.search_roots(roots, query); assert(found.size == 2 && controller.scanned == 0);
    Test.message("Complete indexed scope: %u results, %u filesystem directories scanned", found.size, controller.scanned);
    roots.add(unindexed); found.clear();
    yield controller.search_roots(roots, query); assert(found.size == 3 && controller.scanned == 1);
    Test.message("Mixed scope: %u results, %u unindexed directories scanned", found.size, controller.scanned);
    found.clear(); roots.remove(unindexed); query.text = "SS";
    yield controller.search_roots(roots, query); assert(found.size == 1 && found.contains(files[0].get_uri()) && controller.scanned == 0);
    found.clear(); controller.exhaustive = true; query.text = "needle";
    yield controller.search_roots(roots, query); assert(found.size == 2 && controller.scanned == 2);
    connection.close(); yield OperationManager.remove_tree(root, new Cancellable());
}
