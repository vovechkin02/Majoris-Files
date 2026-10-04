using MajorisFiles;
int main(string[] args)
{
    Test.init(ref args);
    Test.add_func("/filesystem/split-join", () => run_async.begin(false));
    Test.add_func("/filesystem/missing-parts", () => run_async.begin(true));
    // Async tests run within their own bounded main loop.
    Test.add_func("/filesystem/operations", () => operations_test());
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
    return Test.run();
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
        var target = root.get_child("extracted-" + format);
        yield ArchiveService.extract(archive, target, job);
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
