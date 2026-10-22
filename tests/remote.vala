using MajorisFiles;
int main(string[] args){
    Gtk.init();Adw.init();
    var loop=new MainLoop();int status=0;
    run.begin(args[1],(obj,res)=>{try{run.end(res);}catch(Error e){stderr.printf("Remote fixture failed: %s\n",e.message);status=1;}loop.quit();});
    uint watchdog=Timeout.add_seconds(90,()=>{stderr.printf("Remote fixture timeout\n");Process.exit(2);return Source.REMOVE;});
    loop.run();Source.remove(watchdog);return status;
}
async void run(string uri) throws Error {
    var root=File.new_for_uri(uri);var token=new Cancellable();
    var operation=new MountOperation();
    operation.ask_question.connect(()=>{operation.set_choice(0);operation.reply(MountOperationResult.HANDLED);});
    operation.ask_password.connect(()=>{operation.set_username(Environment.get_variable("MAJORIS_FIXTURE_USER")??"fixture");operation.set_password(Environment.get_variable("MAJORIS_FIXTURE_PASSWORD")??"");operation.set_password_save(PasswordSave.NEVER);operation.reply(MountOperationResult.HANDLED);});
    try{yield root.mount_enclosing_volume(MountMountFlags.NONE,operation,token);}catch(IOError.ALREADY_MOUNTED e){}
    assert(!root.is_native());
    var temporary=File.new_for_path(DirUtils.make_tmp("majoris-remote-client-XXXXXX"));
    var source=root.get_child("payload.txt");var imports=temporary.get_child("imports");
    uint progress=0;
    var downloaded=yield ChooserImport.download(source,token,imports,new ImportPolicy(),(done,total)=>{assert(done<=total);progress++;});
    uint8[] bytes;yield downloaded.load_contents_async(token,out bytes,null);
    assert((string)bytes=="remote fixture\n"&&progress>0);
    var large=root.get_child("large.bin");var limit=new ImportPolicy();limit.maximum_bytes=1024*1024;
    bool refused=false;try{yield ChooserImport.download(large,token,imports,limit);}catch(Error e){refused=true;}assert(refused);
    var cancel=new Cancellable();refused=false;
    try{yield ChooserImport.download(large,cancel,imports,new ImportPolicy(),(done,total)=>cancel.cancel());}catch(IOError.CANCELLED e){refused=true;}assert(refused);
    var metadata=new MetadataStore(temporary.get_child("state.db").get_path());
    foreach(bool save in new bool[]{false,true,true}){
        var options=new ChooserOptions(save,new VariantBuilder(VariantType.VARDICT).end());options.initial=root;options.initial_provided=true;options.current_name="chooser-save.txt";
        var window=new ChooserWindow(options,metadata,new Places(metadata));window.present();
        bool complete=false,unsupported=false;string selected="";
        window.completed.connect((code,result)=>{complete=true;if(code==0)selected=result.lookup_value("uris",new VariantType("as")).get_child_value(0).get_string();});
        for(int i=0;i<500&&(window.browser.directory.loading||!window.browser.location.equal(root));i++){Timeout.add(20,()=>{run.callback();return Source.REMOVE;});yield;}
        assert(!window.browser.directory.loading&&window.browser.location.equal(root));
        if(!save)window.browser.select_file(source);
        bool returned=false;
        window.accept_selection.begin((obj,res)=>{window.accept_selection.end(res);returned=true;});
        for(int i=0;i<1000&&!returned;i++){
            var dialog=window.visible_dialog as Adw.AlertDialog;
            if(dialog!=null){if(dialog.has_response("apply"))dialog.response("apply");else{unsupported=true;dialog.response("close");}}
            Timeout.add(20,()=>{run.callback();return Source.REMOVE;});yield;
        }
        assert(returned);
        if(save&&Environment.get_variable("MAJORIS_EXPECT_NO_FUSE")=="1")assert(selected=="");
        var remaining=window.visible_dialog as Adw.AlertDialog;
        if(remaining!=null){stdout.printf("Chooser diagnostic: %s\n",remaining.body);unsupported=remaining.body.contains("no local GVfs bridge");remaining.response("close");}
        if(save&&selected==""){assert(unsupported&&!complete);window.cancel_request();stdout.printf("Remote Save: explicitly unsupported without GVfs/FUSE\n");}
        else{
            assert(complete&&selected.has_prefix("file://"));var local=File.new_for_uri(selected);
            if(save){yield local.replace_contents_async("saved via chooser\n".data,null,false,FileCreateFlags.NONE,token,null);yield root.get_child("chooser-save.txt").load_contents_async(token,out bytes,null);assert((string)bytes=="saved via chooser\n");stdout.printf("PASS: remote Save bytes persisted through GVfs/FUSE\n");}
            else{yield local.load_contents_async(token,out bytes,null);assert((string)bytes=="remote fixture\n");}
        }
        window.destroy();
    }
    var inputs=new Gee.ArrayList<File>();inputs.add(source);
    yield ArchiveService.compress(inputs,root.get_child("remote.zip"),"zip",new Job("Remote archive"));
    yield ArchiveService.extract(root.get_child("remote.zip"),temporary.get_child("extracted"),new Job("Remote extraction"));
    yield temporary.get_child("extracted/payload.txt").load_contents_async(token,out bytes,null);assert((string)bytes=="remote fixture\n");
    yield ArchiveService.extract(root.get_child("remote.zip"),root.get_child("remote-extracted"),new Job("Publish remote extraction"));
    yield root.get_child("remote-extracted/payload.txt").load_contents_async(token,out bytes,null);assert((string)bytes=="remote fixture\n");
    var collection=root.get_child("collection");yield collection.make_directory_async(Priority.DEFAULT,token);yield source.copy_async(collection.get_child("nested.txt"),FileCopyFlags.NONE,Priority.DEFAULT,token,null);
    inputs.clear();inputs.add(collection);yield ArchiveService.compress(inputs,root.get_child("tree.zip"),"zip",new Job("Remote tree archive"));
    yield ArchiveService.extract(root.get_child("tree.zip"),temporary.get_child("tree-output"),new Job("Verify remote tree"));
    yield temporary.get_child("tree-output/collection/nested.txt").load_contents_async(token,out bytes,null);assert((string)bytes=="remote fixture\n");
    metadata.set_state("indexed-search","false");var search=new SearchController();var query=new SearchQuery();query.text="payload";uint hits=0;search.found.connect(()=>hits++);yield search.search(root,query,metadata,true);assert(hits==2&&search.scanned>=3);
    if(Environment.get_variable("MAJORIS_EXPECT_DISCONNECT")=="1"){
        refused=false;try{yield ChooserImport.download(root.get_child("disconnect.bin"),token,imports,new ImportPolicy());}catch(Error e){refused=true;}assert(refused);
        stdout.printf("PASS: interrupted remote connection returns failure without publishing an import\n");
    }
    yield OperationManager.remove_tree(temporary,token);
    stdout.printf("PASS: remote Open, bounded imports, cancellation, Save contract, remote archive publication, folder inputs and remote extraction\n");
}
