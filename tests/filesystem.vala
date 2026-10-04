using MajorisFiles;
int main(string[] args)
{
    Test.init(ref args);
    Test.add_func("/filesystem/split-join", () => run_async.begin(false));
    Test.add_func("/filesystem/missing-parts", () => run_async.begin(true));
    // Async tests run within their own bounded main loop.
    Test.add_func("/filesystem/operations", () => operations_test());
    Test.add_func("/filesystem/archive-roundtrip",()=>archive_test());
    return Test.run();
}
void archive_test() {
    var loop=new MainLoop(); bool passed=false; archive_case.begin((obj,res)=>{ try { archive_case.end(res); passed=true; } catch(Error e) { error("%s",e.message); } loop.quit(); }); uint timeout=Timeout.add_seconds(15,()=>{ error("Archive test timed out"); }); loop.run(); Source.remove(timeout); assert(passed);
}
async void archive_case() throws Error {
    var temp=DirUtils.make_tmp("majoris-archive-XXXXXX"); var root=File.new_for_path(temp); FileUtils.set_contents(Path.build_filename(temp,"hello.txt"),"hello archive"); var files=new Gee.ArrayList<File>(); files.add(root.get_child("hello.txt")); var job=new Job("archive test");
    foreach(var format in new string[]{"zip","7z","tar","tar.gz","tar.xz"}) { var archive=root.get_child("test."+format); yield ArchiveService.compress(files,archive,format,job); var target=root.get_child("extracted-"+format); yield ArchiveService.extract(archive,target,job); string result; FileUtils.get_contents(target.get_child("hello.txt").get_path(),out result); assert(result=="hello archive"); }
    var malicious=root.get_child("malicious.tar"); var writer=new Archive.Write(); writer.set_format_pax_restricted(); writer.open_filename(malicious.get_path()); var entry=new Archive.Entry(); entry.set_pathname("../escaped.txt"); entry.set_filetype(Archive.FileType.IFREG); entry.set_size(4); entry.set_perm(0600); writer.write_header(entry); writer.write_data("oops".data); writer.close();
    bool rejected=false; var target=root.get_child("unsafe"); try { yield ArchiveService.extract(malicious,target,job); } catch(Error e) { rejected=true; } assert(rejected); assert(!root.get_child("escaped.txt").query_exists()); assert(!target.query_exists()); yield OperationManager.remove_tree(root,new Cancellable());
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
    FileUtils.set_contents(Path.build_filename(temp, "original.txt"), "content");
    var original = root.get_child("original.txt");
    yield manager.rename(original, "renamed.txt");
    assert(root.get_child("renamed.txt").query_exists());
    yield manager.undo();
    assert(original.query_exists());
    var files = new Gee.ArrayList<File>();
    files.add(original);
    yield manager.run(OperationKind.COPY, files, root.get_child("folder"));
    assert(root.get_child("folder/original.txt").query_exists());
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
