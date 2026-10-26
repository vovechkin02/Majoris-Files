using MajorisFiles;
string fixture_root;
string executable_path;
string configuration;
string bookmarks_path;
string original_bookmarks;
int main(string[] args) {
    if(args.length>1&&args[1]=="--probe") {
        var places=new Places();foreach(var place in places.entries)stdout.printf("%s|%s|%s\n",place.section,place.label,place.file.get_uri());return 0;
    }
    try {
        fixture_root=DirUtils.make_tmp("majoris-sidebar-XXXXXX");
        Environment.set_variable("HOME",fixture_root,true);
        Environment.set_variable("XDG_CONFIG_HOME",fixture_root+"/config",true);
        Environment.set_variable("XDG_DATA_HOME",fixture_root+"/data",true);
        Environment.set_variable("XDG_CACHE_HOME",fixture_root+"/cache",true);
        DirUtils.create_with_parents(fixture_root+"/config/gtk-3.0",0700);
        configuration=fixture_root+"/config/user-dirs.dirs";
        string content="";string[] kinds={"DESKTOP","DOCUMENTS","DOWNLOAD","PICTURES","MUSIC","VIDEOS"};
        for(int i=0;i<kinds.length;i++)content+="XDG_"+kinds[i]+"_DIR=\"$HOME/Redirected/"+kinds[i]+"\"\n";
        FileUtils.set_contents(configuration,content);
        bookmarks_path=fixture_root+"/config/gtk-3.0/bookmarks";
        original_bookmarks=File.new_for_path(fixture_root+"/Redirected/DOCUMENTS").get_uri()+" Documents\n"+File.new_for_path(fixture_root+"/Redirected/DOWNLOAD").get_uri()+" Downloads\n"+"sftp://example.invalid/other Remote\n";
        FileUtils.set_contents(bookmarks_path,original_bookmarks);
    }catch(Error e){error("%s",e.message);}
    executable_path=args[0];
    Test.init(ref args);
    Test.add_func("/sidebar/xdg-and-bookmarks",()=>{
        var places=new Places();assert(places.entries[0].label=="Home"&&places.entries[0].file.get_uri()=="recent:///");
        assert(places.entries[1].label=="Favorites");
        string[] names={"Desktop","Documents","Downloads","Pictures","Music","Videos"};string[] suffixes={"DESKTOP","DOCUMENTS","DOWNLOAD","PICTURES","MUSIC","VIDEOS"};
        for(int i=0;i<6;i++){assert(places.entries[i+2].section=="Folders"&&places.entries[i+2].label==names[i]);assert(places.entries[i+2].file.equal(File.new_for_path(fixture_root+"/Redirected/"+suffixes[i])));}
        assert(places.entries[8].system&&places.entries[8].file.equal(File.new_for_path("/")));
        assert(places.root_filesystem!="");assert(places.entries[places.entries.size-2].label=="Network"&&places.entries[places.entries.size-1].label=="Trash");
        foreach(var place in places.entries)assert(!place.file.has_uri_scheme("sftp"));
        places.reload();var restarted=new Places();assert(restarted.entries.size==places.entries.size);
        try {string bytes;FileUtils.get_contents(bookmarks_path,out bytes);assert(bytes==original_bookmarks);var process=new Subprocess.newv({executable_path,"--probe"},SubprocessFlags.STDOUT_PIPE|SubprocessFlags.STDERR_PIPE);string output,errors;process.communicate_utf8(null,null,out output,out errors);assert(process.get_successful());assert(output.split("Folders|Documents|").length==2);assert(!output.contains("example.invalid"));}catch(Error e){error("%s",e.message);}
    });
    Test.add_func("/sidebar/folder-location-identity",()=>{
        string?[] paths={fixture_root+"/Desktop",fixture_root+"/Work/Documents",fixture_root+"/Work/../Work/Documents",fixture_root+"/Pictures",fixture_root,fixture_root+"/missing"};
        var folders=Places.standard_folders(paths);assert(folders.size==4);assert(folders[1].label=="Documents"&&folders[1].file.get_path()==fixture_root+"/Work/Documents");assert(folders[2].label=="Pictures"&&folders[3].label=="Videos");assert(!folders[3].file.query_exists());
        string?[] renamed={null,fixture_root+"/Moved Documents",null,null,null,null};var moved=Places.standard_folders(renamed);assert(moved.size==1&&moved[0].label=="Documents"&&moved[0].file.get_path()==fixture_root+"/Moved Documents");
    });
    Test.add_func("/sidebar/device-projection",()=>{
        var folders=new Gee.ArrayList<Place>();var devices=new Gee.ArrayList<SidebarDevice>();
        devices.add(device("Main Disk","/","root",1));devices.add(device("Root Alias","/mnt/root-alias","root",1));
        devices.add(device("Data","/mnt/data","data",1));devices.add(device("Data Alias","/media/data","data",1));
        devices.add(device("Same Label","/media/usb-a","usb-a",2));devices.add(device("Same Label","/media/usb-b","usb-b",2));
        devices.add(device("Partition One","/mnt/part1","disk-part1",1));devices.add(device("Partition Two","/mnt/part2","disk-part2",1));
        devices.add(device("Unmounted","majoris:///device/unmounted","unmounted",1));devices.add(device("Optical Drive","majoris:///device/optical","optical",3));devices.add(device("Camera","gphoto2://camera/","camera",4));
        foreach(var name in new string[]{"EFI","swap","recovery"}){var hidden=device(name,"majoris:///device/"+name,name,1);hidden.visible=false;devices.add(hidden);}
        var result=Places.compose(folders,devices,"root");assert(result[2].system&&result[2].section=="Devices");assert(result.size==13);
        int same=0,root=0;foreach(var place in result){if(place.label=="Same Label")same++;if(place.system||place.label=="Main Disk"||place.label=="Root Alias")root++;assert(place.label!="EFI"&&place.label!="swap"&&place.label!="recovery");}assert(same==2&&root==1);
        for(int i=devices.size-1;i>=0;i--)if(devices[i].identity=="usb-a")devices.remove_at(i);
        var disconnected=Places.compose(folders,devices,"root");assert(disconnected.size==result.size-1);
        var empty=Places.compose(folders,new Gee.ArrayList<SidebarDevice>());assert(empty.size==5&&empty[2].system&&empty[2].section=="Devices");
    });
    Test.add_func("/sidebar/kernel-filesystem-identity",()=>{
        var identities=Places.parse_mount_identities(
            "1 0 8:2 / / rw - ext4 /dev/mapper/root rw\n"+
            "2 1 8:2 / /mnt/root-alias rw - ext4 /dev/mapper/root rw\n"+
            "3 1 0:30 / /mnt/tmp-a rw - tmpfs tmpfs rw\n"+
            "4 1 0:31 / /mnt/tmp-b rw - tmpfs tmpfs rw\n"+
            "5 1 0:32 /@ /mnt/subvolume rw - btrfs /dev/mapper/data rw\n"+
            "6 1 0:32 /@home /mnt/other\\040subvolume rw - btrfs /dev/mapper/data rw\n"+
            "incomplete\n");
        assert(identities.size==6&&identities["/"]==identities["/mnt/root-alias"]);
        assert(identities["/mnt/tmp-a"]!=identities["/mnt/tmp-b"]);
        assert(identities["/mnt/subvolume"]!=identities["/mnt/other subvolume"]);
    });
    Test.add_func("/sidebar/explicit-favorites",()=>{
        try {var file=File.new_for_path(fixture_root+"/favorite.txt");var folder=File.new_for_path(fixture_root+"/favorite-folder");FileUtils.set_contents(file.get_path(),"retain");folder.make_directory();var metadata=new MetadataStore(fixture_root+"/metadata.db");assert(metadata.favorites().size==0);metadata.set_favorite(file,true);metadata.set_favorite(folder,true);var places=new Places(metadata);assert(metadata.favorites().size==2);int count=0;foreach(var place in places.entries){if(place.file.get_uri()=="majoris:///favorites")count++;assert(!place.file.equal(file)&&!place.file.equal(folder));}assert(count==1);var reopened=new MetadataStore(fixture_root+"/metadata.db");assert(reopened.favorite(file)&&reopened.favorite(folder));metadata.set_favorite(file,false);metadata.set_favorite(folder,false);assert(file.query_exists()&&folder.query_exists());string bytes;FileUtils.get_contents(bookmarks_path,out bytes);assert(bytes==original_bookmarks);}catch(Error e){error("%s",e.message);}
    });
    Test.add_func("/sidebar/xdg-live-update",()=>{
        try {
            var places=new Places();var loop=new MainLoop();bool observed=false;
            places.changed.connect(()=>{foreach(var place in places.entries)if(place.label=="Documents"&&place.file.get_path()==fixture_root+"/new-documents"){observed=true;loop.quit();}});
            string content;FileUtils.get_contents(configuration,out content);FileUtils.set_contents(configuration,content.replace("$HOME/Redirected/DOCUMENTS","$HOME/new-documents"));
            uint timeout=Timeout.add_seconds(5,()=>{loop.quit();return Source.REMOVE;});loop.run();assert(observed);Source.remove(timeout);
        }catch(Error e){error("%s",e.message);}
    });
    return Test.run();
}
SidebarDevice device(string name,string path,string identity,int order) {
    var file=Uri.parse_scheme(path)==null?File.new_for_path(path):File.new_for_uri(path);return new SidebarDevice(new Place(name,file),identity,order);
}
