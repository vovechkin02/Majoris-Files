using MajorisFiles;
void expand_operations(Gtk.Widget widget, bool expanded) {
    if (widget is Gtk.Expander) ((Gtk.Expander)widget).expanded = expanded;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()) expand_operations(child, expanded);
}
async void operation_capture(Gtk.Window window, string output, string name) throws Error {
    stdout.printf("Capturing %s\n", name); stdout.flush(); window.queue_draw();
    yield capture(window, output, name);
}
async void evidence(string output, MainLoop loop) throws Error {
    var root=File.new_for_path(DirUtils.make_tmp("majoris-operation-ui-XXXXXX"));
    var manager=new OperationManager(new MetadataStore(root.get_child("state.db").get_path()));
    var job=new Job("Copying");job.state=JobState.RUNNING;job.structured=true;job.transfer_bytes=true;job.can_pause=true;
    job.source_description="Documents";job.destination_description="External SSD";
    job.items_total_known=true;job.items_total=248;job.items_completed=162;
    job.bytes_total_known=true;job.bytes_total=5000000000;
    job.current="ProjectAssets.zip";job.begin_file(4000000000);job.report_bytes(3400000000);
    for(int i=0;i<100;i++)job.history.add(80000000.0+(i%20)*3000000.0);
    manager.jobs.append(job);
    var window=new FileOperationsWindow(manager);window.present();yield pause_layout();
    yield operation_capture(window,output,"copy-collapsed");
    expand_operations(window,true);yield operation_capture(window,output,"copy-expanded");
    job.state=JobState.PAUSED;yield operation_capture(window,output,"paused");
    job.state=JobState.RUNNING;yield operation_capture(window,output,"resumed");
    job.state=JobState.WAITING_FOR_USER;yield operation_capture(window,output,"conflict");
    var deletion=new Job("Deleting");deletion.state=JobState.RUNNING;deletion.structured=true;deletion.items_total_known=true;deletion.items_total=132;deletion.items_completed=98;
    manager.jobs.append(deletion);yield operation_capture(window,output,"multiple-delete");
    job.state=JobState.RUNNING;job.title="Moving across filesystems";yield operation_capture(window,output,"cross-filesystem-move");
    deletion.title="Moving to Trash";yield operation_capture(window,output,"trash");
    job.error="Destination disconnected";job.can_retry=true;job.done=true;yield operation_capture(window,output,"failed-retry");
    job.items_completed=job.items_total;job.begin_file(1600000000);job.report_bytes(1600000000);deletion.items_completed=deletion.items_total;
    job.can_retry=false;job.error="";job.done=false;job.done=true;deletion.done=true;expand_operations(window,false);yield operation_capture(window,output,"completed");
    var recovery=new Job("Interrupted batch rename");recovery.done=true;recovery.recovery_action="recover-rename";manager.jobs.append(recovery);yield operation_capture(window,output,"recovery");
    window.destroy();yield OperationManager.remove_tree(root,new Cancellable());loop.quit();
}
int main(string[] args) {
    Gtk.init();Adw.init();
    if(Environment.get_variable("MAJORIS_VISUAL_DARK")=="1") Adw.StyleManager.get_default().color_scheme=Adw.ColorScheme.FORCE_DARK;
    var loop=new MainLoop();
    evidence.begin(args[1],loop,(o,r)=>{try{evidence.end(r);}catch(Error e){error("%s",e.message);}});
    loop.run();return 0;
}
