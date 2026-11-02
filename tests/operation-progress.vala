using MajorisFiles;
async void exercise(bool cancel = false) throws Error {
    var root = File.new_for_path(DirUtils.make_tmp("majoris-progress-XXXXXX"));
    var input = root.get_child("input"); yield input.make_directory_async();
    var nested = input.get_child("nested"); yield nested.make_directory_async();
    uint8[] data = new uint8[4 * 1024 * 1024];
    for (int i=0;i<data.length;i++) data[i]=(uint8)(i%251);
    FileUtils.set_data(nested.get_child("large").get_path(), data);
    FileUtils.set_contents(input.get_child("empty").get_path(), "");
    yield input.get_child("link").make_symbolic_link_async("nested/large", Priority.DEFAULT, null);
    var target = root.get_child("target"); yield target.make_directory_async();
    var manager = new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
    Job? job=null; bool paused=false; double previous=0;
    manager.jobs.items_changed.connect((position, removed, added) => {
        if (added==0) return; job=(Job)manager.jobs.get_item(position);
        job.notify["bytes-completed"].connect(() => {
            assert(job.progress>=previous); previous=job.progress;
            if (!paused && job.bytes_completed>0) { paused=true; job.request_pause(); }
        });
        job.notify["state"].connect(() => {
            if(job.state==JobState.PAUSED) {
                uint64 stopped=job.bytes_completed;
                Timeout.add(30,()=>{assert(job.bytes_completed==stopped);assert(!target.get_child("input/nested/large").query_exists());if(cancel)job.cancellable.cancel();else job.resume();return Source.REMOVE;});
            }
        });
    });
    var selection=new Gee.ArrayList<File>(); selection.add(input);
    yield manager.run(OperationKind.COPY,selection,target);
    if (cancel) {
        assert(job.done && job.state==JobState.CANCELLED);
        assert(nested.get_child("large").query_exists());
        assert(!target.get_child("input/nested/large").query_exists());
        yield OperationManager.remove_tree(root,new Cancellable()); return;
    }
    assert(job.done && job.state==JobState.COMPLETED); assert(paused);
    assert(job.bytes_completed==data.length && job.bytes_total==data.length);
    assert(job.items_completed==5 && job.items_total==5); assert(job.progress==1);
    uint8[] copied; FileUtils.get_data(target.get_child("input/nested/large").get_path(),out copied);
    assert(data.length==copied.length); for(int i=0;i<data.length;i++)assert(data[i]==copied[i]);
    var original_metadata=yield nested.get_child("large").query_info_async("unix::mode,time::modified,time::modified-usec",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.DEFAULT,null);
    var copied_metadata=yield target.get_child("input/nested/large").query_info_async("unix::mode,time::modified,time::modified-usec",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.DEFAULT,null);
    assert(original_metadata.get_attribute_uint32("unix::mode")==copied_metadata.get_attribute_uint32("unix::mode"));
    assert(original_metadata.get_attribute_uint64("time::modified")==copied_metadata.get_attribute_uint64("time::modified"));
    var link_info=yield target.get_child("input/link").query_info_async("standard::is-symlink",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.DEFAULT,null);
    assert(link_info.get_is_symlink());
    var moved=root.get_child("moved");yield moved.make_directory_async();
    var moving=new Gee.ArrayList<File>();moving.add(target.get_child("input"));
    yield manager.run(OperationKind.MOVE,moving,moved);
    assert(job.done && job.error=="");assert(job.items_completed==5 && job.items_total==5);
    assert(!target.get_child("input").query_exists() && moved.get_child("input/nested/large").query_exists());
    yield OperationManager.remove_tree(root,new Cancellable());
}
async void cross_move() throws Error {
    var root=File.new_for_path(DirUtils.make_tmp("majoris-cross-progress-XXXXXX"));
    var target=File.new_for_path("/dev/shm").get_child("majoris-progress-"+Uuid.string_random());
    yield target.make_directory_async();
    var source=root.get_child("data");uint8[] data=new uint8[1024*1024];for(int i=0;i<data.length;i++)data[i]=(uint8)(i%251);
    FileUtils.set_data(source.get_path(),data);
    var manager=new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
    var selected=new Gee.ArrayList<File>();selected.add(source);
    yield manager.run(OperationKind.MOVE,selected,target);
    var job=(Job)manager.jobs.get_item(0);assert(job.done&&job.error=="");
    assert(job.items_completed==1&&job.items_total==1);assert(!source.query_exists());
    uint8[] result;FileUtils.get_data(target.get_child("data").get_path(),out result);assert(result.length==data.length);
    for(int i=0;i<data.length;i++)assert(result[i]==data[i]);
    yield OperationManager.remove_tree(target,new Cancellable());yield OperationManager.remove_tree(root,new Cancellable());
}
int main(string[] args) {
    Test.init(ref args);
    Test.add_func("/progress/aggregate-pause-copy",()=>{
        var loop=new MainLoop();
        uint timeout=Timeout.add_seconds(20,()=>{error("Progress test timed out");});
        exercise.begin(false,(o,r)=>{try{exercise.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});
        loop.run();Source.remove(timeout);
    });
    Test.add_func("/progress/cancel-paused-copy",()=>{
        var loop=new MainLoop();
        uint timeout=Timeout.add_seconds(20,()=>{error("Cancellation test timed out");});
        exercise.begin(true,(o,r)=>{try{exercise.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});
        loop.run();Source.remove(timeout);
    });
    Test.add_func("/progress/cross-filesystem-move",()=>{
        if(!File.new_for_path("/dev/shm").query_exists()){Test.skip("No tmpfs mount available");return;}
        var loop=new MainLoop();uint timeout=Timeout.add_seconds(20,()=>{error("Cross-filesystem move timed out");});
        cross_move.begin((o,r)=>{try{cross_move.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});
        loop.run();Source.remove(timeout);
    });
    Test.add_func("/progress/statistics",()=>{
        var job=new Job("Test");job.structured=true;job.transfer_bytes=true;job.bytes_total_known=true;job.bytes_total=8000000000;
        job.state=JobState.RUNNING;job.begin_file(4000000000);job.report_bytes(2000000000);job.report_bytes(2000000000);
        assert(job.bytes_completed==2000000000);double fraction=job.progress;
        job.begin_file(4000000000);job.report_bytes(1000000000);assert(job.progress>fraction);
        int64 now=GLib.get_monotonic_time();job.sample(now+1000000);job.sample(now+2000000);job.sample(now+3000000);
        assert(job.bytes_per_second>=0);assert(job.eta_seconds>=0);
        job.state=JobState.PAUSED;assert(job.eta_seconds<0);
        job.bytes_total_known=false;assert(!job.progress_known);
        job.error="Finalisation failed";job.done=true;assert(job.state==JobState.FAILED);assert(job.progress<1);
    });
    return Test.run();
}
