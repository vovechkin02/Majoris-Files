using MajorisFiles;
[CCode(cname = "_exit", cheader_filename = "unistd.h")]
extern void immediate_exit(int status);
int main(string[] args) {
    if(args.length==5&&args[1]=="--edit-child"){
        var root=File.new_for_path(args[2]);var manager=new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
        manager.edit_checkpoint.connect((phase)=>{if(phase==args[4])immediate_exit(77);});var loop=new MainLoop();
        if(args[3]=="undo")manager.undo.begin(null,(obj,res)=>{try{manager.undo.end(res);}catch(Error e){stderr.printf("%s\n",e.message);}immediate_exit(78);});
        else manager.redo.begin((obj,res)=>{try{manager.redo.end(res);}catch(Error e){stderr.printf("%s\n",e.message);}immediate_exit(78);});loop.run();return 1;
    }
    if(args.length==4&&args[1]=="--rename-child"){
        var root=File.new_for_path(args[2]);var manager=new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
        var files=new Gee.ArrayList<File>();files.add(root.get_child("a"));files.add(root.get_child("b"));var names=new Gee.ArrayList<string>();names.add("b");names.add("a");
        manager.rename_checkpoint.connect((phase)=>{if(phase==args[3])immediate_exit(77);});
        var loop=new MainLoop();manager.batch_rename.begin(files,names,null,(obj,res)=>{try{manager.batch_rename.end(res);}catch(Error e){stderr.printf("%s\n",e.message);}immediate_exit(78);});loop.run();return 1;
    }
    if(args.length==3&&args[1]=="--disk-full"){
        var loop=new MainLoop();int status=0;
        disk_full.begin(args[2],(obj,res)=>{try{disk_full.end(res);}catch(Error e){stderr.printf("%s\n",e.message);status=1;}loop.quit();});loop.run();return status;
    }
    if (args.length == 4 && args[1] == "--child") {
        var root = File.new_for_path(args[2]);
        var manager = new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
        manager.replacement_checkpoint.connect((phase) => { if (phase == args[3]) immediate_exit(77); });
        var loop = new MainLoop();
        manager.replace_existing.begin(root.get_child("source"), root.get_child("target"), false, new Job("Crash fixture"), false, null, (obj, res) => {
            try { manager.replace_existing.end(res); } catch (Error e) { stderr.printf("%s\n", e.message); }
            immediate_exit(78);
        });
        loop.run(); return 1;
    }
    Test.init(ref args);
    Test.add_func("/replacement/process-crash-boundaries", () => {
        var loop = new MainLoop();
        run.begin((obj, res) => { try { run.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); });
        uint watchdog = Timeout.add_seconds(40, () => { error("Replacement crash fixture timed out"); });
        loop.run(); Source.remove(watchdog);
    });
    return Test.run();
}
async void disk_full(string path) throws Error {
    if(!path.has_prefix("/tmp/majoris-enospc-")||path.contains(".."))throw new IOError.INVALID_ARGUMENT("Use the private fixture mount");
    var temporary=File.new_for_path(DirUtils.make_tmp("majoris-full-source-XXXXXX"));
    var source=temporary.get_child("source");var target=File.new_for_path(path).get_child("target");
    uint8[] data=new uint8[20*1024*1024];for(int i=0;i<data.length;i++)data[i]=(uint8)(i%251);
    yield source.replace_contents_async(data,null,false,FileCreateFlags.NONE,null,null);
    FileUtils.set_contents(target.get_path(),"original destination survives ENOSPC");
    var manager=new OperationManager(new MetadataStore(temporary.get_child("state.db").get_path()));
    bool failed=false;try{yield manager.replace_existing(source,target,false,new Job("Disk full"));}catch(Error e){failed=true;}
    assert(failed);string contents;FileUtils.get_contents(target.get_path(),out contents);assert(contents=="original destination survives ENOSPC");
    assert(source.query_exists());
    yield OperationManager.remove_tree(temporary,new Cancellable());
    stdout.printf("PASS: actual ENOSPC preserves source and original destination\n");
}
async void run() throws Error {
    string executable = FileUtils.read_link("/proc/self/exe");
    foreach (var phase in new string[] {"prepared", "writing", "written", "staged", "exchanged", "published", "cleaned"}) {
        var root = File.new_for_path(DirUtils.make_tmp("majoris-crash-XXXXXX"));
        FileUtils.set_contents(root.get_child("source").get_path(), "new content");
        FileUtils.set_contents(root.get_child("target").get_path(), "original content");
        var process = new Subprocess.newv({executable, "--child", root.get_path(), phase}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE);
        yield process.wait_async(null); assert(process.get_if_exited() && process.get_exit_status() == 77);
        var journal = new ReplacementJournal(new MetadataStore(root.get_child("state.db").get_path()));
        assert(journal.records.size == 1);
        string current; FileUtils.get_contents(root.get_child("target").get_path(), out current);
        if (phase in new string[] {"prepared", "writing", "written", "staged"}) assert(current == "original content");
        else assert(current == "new content");
        if (phase == "exchanged" || phase == "published") {
            var recovered = yield journal.restore(journal.records[0], new Cancellable());
            string original; FileUtils.get_contents(recovered.get_path(), out original); assert(original == "original content");
            FileUtils.get_contents(root.get_child("target").get_path(), out current); assert(current == "new content");
        }
        if (phase == "cleaned") { yield journal.reconcile(new Cancellable()); assert(journal.records.size == 0); }
        Test.message("Verified process exit at %s", phase);
        yield OperationManager.remove_tree(root, new Cancellable());
    }
    foreach(var phase in new string[]{"prepared","writing","written","staged","exchanged","published"}){
        var directory=File.new_for_path(DirUtils.make_tmp("majoris-directory-crash-XXXXXX"));
        DirUtils.create_with_parents(directory.get_child("source/nested").get_path(),0700);DirUtils.create_with_parents(directory.get_child("target/nested").get_path(),0700);
        FileUtils.set_contents(directory.get_child("source/nested/file").get_path(),"new tree");FileUtils.set_contents(directory.get_child("target/nested/file").get_path(),"original tree");
        var process=new Subprocess.newv({executable,"--child",directory.get_path(),phase},SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_PIPE);yield process.wait_async(null);assert(process.get_exit_status()==77);
        var journal=new ReplacementJournal(new MetadataStore(directory.get_child("state.db").get_path()));
        string contents;
        if(phase=="exchanged"||phase=="published"){
            var recovered=yield journal.restore(journal.records[0],new Cancellable());FileUtils.get_contents(recovered.get_child("nested/file").get_path(),out contents);
        }else FileUtils.get_contents(directory.get_child("target/nested/file").get_path(),out contents);
        assert(contents=="original tree");yield OperationManager.remove_tree(directory,new Cancellable());
    }
    foreach(var phase in new string[]{"prepared","staged:0","staged:1","published:0","published:1","committed"}){
        var directory=File.new_for_path(DirUtils.make_tmp("majoris-rename-crash-XXXXXX"));
        FileUtils.set_contents(directory.get_child("a").get_path(),"original a");FileUtils.set_contents(directory.get_child("b").get_path(),"original b");
        var process=new Subprocess.newv({executable,"--rename-child",directory.get_path(),phase},SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_PIPE);yield process.wait_async(null);assert(process.get_exit_status()==77);
        var manager=new OperationManager(new MetadataStore(directory.get_child("state.db").get_path()));
        if(phase=="committed"){assert(!manager.rename_recovery.pending);yield manager.undo();}
        else{assert(manager.rename_recovery.pending);yield manager.rename_recovery.recover(new Cancellable());}
        string a,b;FileUtils.get_contents(directory.get_child("a").get_path(),out a);FileUtils.get_contents(directory.get_child("b").get_path(),out b);assert(a=="original a"&&b=="original b");
        yield OperationManager.remove_tree(directory,new Cancellable());
    }
    foreach(var direction in new string[]{"undo","redo"})foreach(var phase in new string[]{"prepared","exchanged","committed"}){
        var directory=File.new_for_path(DirUtils.make_tmp("majoris-edit-crash-XXXXXX"));var database=directory.get_child("state.db").get_path();
        FileUtils.set_contents(directory.get_child("source").get_path(),"edited bytes");FileUtils.set_contents(directory.get_child("target").get_path(),"original bytes");
        var setup=new OperationManager(new MetadataStore(database));yield setup.replace_existing(directory.get_child("source"),directory.get_child("target"),false,new Job("Edit fixture"),true);
        if(direction=="redo")yield setup.undo();
        var process=new Subprocess.newv({executable,"--edit-child",directory.get_path(),direction,phase},SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_PIPE);yield process.wait_async(null);assert(process.get_exit_status()==77);
        var restarted=new OperationManager(new MetadataStore(database));
        for(int attempt=0;attempt<200&&restarted.metadata.state("image-edit-pending-v1")!="";attempt++){Timeout.add(10,()=>{run.callback();return Source.REMOVE;});yield;}
        assert(restarted.metadata.state("image-edit-pending-v1")=="");
        string contents;FileUtils.get_contents(directory.get_child("target").get_path(),out contents);bool applied=phase!="prepared";
        assert(contents==(((direction=="undo")==applied)?"original bytes":"edited bytes"));
        if((direction=="undo")==applied){yield restarted.redo();FileUtils.get_contents(directory.get_child("target").get_path(),out contents);assert(contents=="edited bytes");}
        else{yield restarted.undo();FileUtils.get_contents(directory.get_child("target").get_path(),out contents);assert(contents=="original bytes");}
        yield OperationManager.remove_tree(directory,new Cancellable());
    }
    var root = File.new_for_path(DirUtils.make_tmp("majoris-concurrent-XXXXXX"));
    var source = root.get_child("source"); var target = root.get_child("target");
    FileUtils.set_contents(source.get_path(), "incoming"); FileUtils.set_contents(target.get_path(), "original");
    var manager = new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
    manager.replacement_checkpoint.connect((phase) => { if (phase == "staged") { try { FileUtils.set_contents(target.get_path(), "external change"); } catch (Error e) { error("%s", e.message); } } });
    bool refused = false;
    try { yield manager.replace_existing(source, target, false, new Job("Concurrent fixture")); } catch (MajorisFiles.FileError.INTEGRITY e) { refused = true; }
    string external; FileUtils.get_contents(target.get_path(), out external); assert(refused && external == "external change");
    yield OperationManager.remove_tree(root, new Cancellable());
}
