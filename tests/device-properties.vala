using MajorisFiles;
string evidence_output;
class FixtureVolume : Object, Volume {
    public int mutations;
    public bool can_eject(){return false;}
    public bool can_mount(){return true;}
    public async bool eject(MountUnmountFlags flags,Cancellable? token=null) throws Error {mutations++;return false;}
    public async bool eject_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error {mutations++;return false;}
    public string[] enumerate_identifiers(){return {VolumeIdentifier.UNIX_DEVICE};}
    public File? get_activation_root(){return null;}
    public Drive? get_drive(){return null;}
    public Icon get_icon(){return new ThemedIcon("drive-removable-media-symbolic");}
    public Icon get_symbolic_icon(){return get_icon();}
    public string? get_identifier(string kind){return kind==VolumeIdentifier.UNIX_DEVICE?"/dev/test1":null;}
    public Mount? get_mount(){return null;}
    public string get_name(){return "Fixture volume";}
    public string? get_uuid(){return "fixture-volume";}
    public async bool mount(MountMountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error {mutations++;return false;}
    public bool should_automount(){return false;}
}
class FixtureMonitor : VolumeMonitor {
    public FixtureVolume? volume;
    public override GLib.List<Volume> get_volumes(){var result=new GLib.List<Volume>();if(volume!=null)result.append(volume);return result;}
    public override GLib.List<Mount> get_mounts(){return new GLib.List<Mount>();}
    public override GLib.List<Drive> get_connected_drives(){return new GLib.List<Drive>();}
}
class FixtureGioProvider : DeviceInfoProvider {
    public bool objects_fail;
    public bool filesystem_fail;
    public int filesystem_queries;
    public FixtureGioProvider(VolumeMonitor monitor){base(monitor);}
    protected override async Variant read_objects(Cancellable token) throws Error {
        token.set_error_if_cancelled();if(objects_fail)throw new IOError.NOT_FOUND("UDisks unavailable");return inventory("/dev/test1","",false,true);
    }
    protected override async FileInfo read_filesystem(File root,Cancellable token) throws Error {
        filesystem_queries++;token.set_error_if_cancelled();if(filesystem_fail)throw new IOError.FAILED("GIO unavailable");
        assert(root.equal(File.new_for_path("/")));var info=new FileInfo();info.set_attribute_uint64("filesystem::size",500);info.set_attribute_uint64("filesystem::used",200);info.set_attribute_uint64("filesystem::free",250);info.set_attribute_string("filesystem::type","fixturefs");return info;
    }
}
async void provider_cases() throws Error {
    var monitor=new FixtureMonitor();var backend=new FixtureGioProvider(monitor);var token=new Cancellable();
    var root=new Place("System Drive",File.new_for_path("/"));root.system=true;
    backend.objects_fail=true;var info=yield backend.query(root,token);assert(info.category==DeviceCategory.SYSTEM_FILESYSTEM&&info.capacity==500&&info.used==200&&info.available==250&&info.mount_point=="/"&&info.filesystem=="fixturefs");
    backend.filesystem_fail=true;info=yield backend.query(root,token);assert(info.capacity==null&&info.used==null&&!info.show_usage);
    var volume=new FixtureVolume();monitor.volume=volume;var place=new Place("Old name",File.new_for_uri("majoris:///device/fixture"));place.volume=volume;
    backend.objects_fail=false;int queries=backend.filesystem_queries;info=yield backend.query(place,token);assert(info.name=="Fixture volume"&&!info.mounted&&info.status=="Not mounted"&&info.capacity==null&&info.volume_size==1000&&info.physical_size==10000&&info.category==DeviceCategory.REMOVABLE_VOLUME);assert(volume.mutations==0&&backend.filesystem_queries==queries);
    monitor.volume=null;info=yield backend.query(place,token);assert(!info.connected&&info.capacity==null&&info.physical_size==null);
    monitor.volume=new FixtureVolume();info=yield backend.query(place,token);assert(!info.connected); // reused device path is a different GIO object
    var tape_root=DirUtils.make_tmp("majoris-tape-info-XXXXXX");DirUtils.create(tape_root+"/device",0700);FileUtils.set_contents(tape_root+"/device/vendor","Fixture Vendor");FileUtils.set_contents(tape_root+"/device/model","Fixture Tape");
    var tape=new Place("Tape",File.new_for_path("/dev/nst-fixture"));tape.tape_sysfs=tape_root;var node=File.new_for_path(tape_root).query_info("unix::inode",FileQueryInfoFlags.NOFOLLOW_SYMLINKS);tape.tape_inode=node.get_attribute_uint64("unix::inode");
    info=yield backend.query(tape,token);assert(info.category==DeviceCategory.TAPE_DRIVE&&info.model=="Fixture Tape"&&info.capacity==null&&!info.show_usage);tape.tape_inode=tape.tape_inode+1;info=yield backend.query(tape,token);assert(!info.connected&&info.model=="");FileUtils.remove(tape_root+"/device/vendor");FileUtils.remove(tape_root+"/device/model");DirUtils.remove(tape_root+"/device");DirUtils.remove(tape_root);
    token.cancel();bool cancelled=false;try{yield backend.query(root,token);}catch(IOError.CANCELLED e){cancelled=true;}assert(cancelled&&volume.mutations==0);
}

class FixtureProvider : Object, DeviceInformationProvider {
    public DeviceInfo value = new DeviceInfo();
    public int queries;
    public bool fail;
    public bool delay;
    public async DeviceInfo query(Place place, Cancellable token) throws Error {
        queries++;
        var result=value;
        if(delay) { Timeout.add(60,()=>{query.callback();return Source.REMOVE;});yield; }
        token.set_error_if_cancelled();
        if(fail)throw new IOError.FAILED("Fixture unavailable");return result;
    }
    public void update(DeviceInfo info){value=info;changed();}
}
Variant properties(string[] keys, Variant[] values) {
    var builder=new VariantBuilder(VariantType.VARDICT);
    for(int i=0;i<keys.length;i++)builder.add("{sv}",keys[i],values[i]);return builder.end();
}
Variant interfaces(Variant block, Variant? drive=null, Variant? loop=null) {
    var result=new VariantBuilder(new VariantType("a{sa{sv}}"));
    if(drive==null)result.add("{s@a{sv}}","org.freedesktop.UDisks2.Block",block);
    else result.add("{s@a{sv}}","org.freedesktop.UDisks2.Drive",drive);
    if(loop!=null)result.add("{s@a{sv}}","org.freedesktop.UDisks2.Loop",loop);
    return result.end();
}
Variant inventory(string device="/dev/test1", string media="", bool optical=false, bool removable=false, bool loop=false, bool floppy=false) {
    var block=properties({"Device","PreferredDevice","Drive","IdType","IdLabel","IdUUID","Size","ReadOnly"},
        {new Variant.bytestring(device),new Variant.bytestring(device),new Variant.object_path("/drives/test"),new Variant.string("ext4"),new Variant.string("Duplicate label"),new Variant.string(device),new Variant.uint64(1000),new Variant.boolean(optical)});
    var drive=properties({"ConnectionBus","Model","Media","Optical","MediaAvailable","MediaChangeDetected","Removable","RotationRate","Size","OpticalBlank","OpticalNumAudioTracks","OpticalNumDataTracks","MediaCompatibility"},
        {new Variant.string(removable?"usb":"ata"),new Variant.string("Fixture hardware"),new Variant.string(media),new Variant.boolean(optical),new Variant.boolean(media!=""),new Variant.boolean(true),new Variant.boolean(removable),new Variant.int32(0),new Variant.uint64(10000),new Variant.boolean(media=="optical_dvd_rw"),new Variant.uint32(media=="optical_cd"?12:0),new Variant.uint32(media=="optical_cd"?0:1),new Variant.strv(floppy?new string[]{"floppy"}:optical?new string[]{"optical_dvd"}:new string[]{})});
    var result=new VariantBuilder(new VariantType("a{oa{sa{sv}}}"));
    result.add("{o@a{sa{sv}}}","/blocks/test",interfaces(block,null,loop?properties({"BackingFile"},{new Variant.bytestring("/fixtures/image.iso")}):null));
    result.add("{o@a{sa{sv}}}","/drives/test",interfaces(block,drive));
    return result.end();
}
void calculations() {
    var info=new DeviceInfo();info.mounted=true;
    var fs=new FileInfo();fs.set_attribute_uint64("filesystem::size",1000);fs.set_attribute_uint64("filesystem::used",0);fs.set_attribute_uint64("filesystem::free",950);
    info.filesystem_info(fs);assert(info.used==0&&info.show_usage&&!info.used_estimated);
    fs.remove_attribute("filesystem::used");info.filesystem_info(fs);assert(info.used==50&&info.used_estimated);
    fs.remove_attribute("filesystem::free");info=new DeviceInfo();info.mounted=true;info.filesystem_info(fs);assert(info.used==null&&!info.show_usage);
    fs.set_attribute_string("filesystem::used","wrong type");info.filesystem_info(fs);assert(info.used==null);
    fs.set_attribute_uint64("filesystem::used",1100);info.filesystem_info(fs);assert(!info.show_usage&&info.used==1100);
    fs.set_attribute_uint64("filesystem::size",uint64.MAX);fs.set_attribute_uint64("filesystem::used",uint64.MAX/2);info.filesystem_info(fs);assert(info.show_usage);
    fs.set_attribute_uint64("filesystem::size",1474560);fs.set_attribute_uint64("filesystem::used",1000000);info.filesystem_info(fs);assert(info.show_usage);
    fs.set_attribute_boolean("filesystem::readonly",true);info.filesystem_info(fs);assert(info.read_only==true);
    info.category=DeviceCategory.OPTICAL_DRIVE;assert(!info.show_usage);info.category=DeviceCategory.TAPE_DRIVE;assert(!info.show_usage);info.category=DeviceCategory.PORTABLE_DEVICE;assert(!info.show_usage);
    info=new DeviceInfo();assert(info.capacity==null&&info.used==null&&!info.show_usage);
}
void mapping() {
    foreach(string media in new string[]{"","optical_cd","optical_dvd","optical_bd","optical_dvd_rw","unsupported"}) {
        var info=new DeviceInfo();DeviceInfoProvider.enrich(info,inventory("/dev/test1",media,true),"/dev/test1");
        assert(info.optical&&info.physical_size==null&&info.volume_size==1000&&info.capacity==null&&!info.show_usage);
        assert(info.media_presence==(media==""?MediaPresence.ABSENT:MediaPresence.PRESENT));
        assert(media==""?info.media_size==null:info.media_size==10000);
        if(media=="optical_cd")assert(info.audio_tracks==12&&info.data_tracks==0);
    }
    var usb=new DeviceInfo();DeviceInfoProvider.enrich(usb,inventory("/dev/usb1","flash_sd",false,true),"/dev/usb1");assert(usb.category==DeviceCategory.REMOVABLE_VOLUME&&usb.media=="flash_sd");
    var image=new DeviceInfo();DeviceInfoProvider.enrich(image,inventory("/dev/loop0","",false,false,true),"/dev/loop0");assert(image.category==DeviceCategory.DISK_IMAGE&&image.backing_file=="/fixtures/image.iso"&&image.model=="");
    var floppy=new DeviceInfo();DeviceInfoProvider.enrich(floppy,inventory("/dev/fd0","",false,true,false,true),"/dev/fd0");assert(floppy.category==DeviceCategory.FLOPPY_DRIVE);
    var root=new DeviceInfo();root.category=DeviceCategory.SYSTEM_FILESYSTEM;root.capacity=500;DeviceInfoProvider.enrich(root,inventory(),"/dev/test1");assert(root.category==DeviceCategory.SYSTEM_FILESYSTEM&&root.capacity==500&&root.physical_size==10000);
    var layered=new DeviceInfo();layered.category=DeviceCategory.SYSTEM_FILESYSTEM;layered.filesystem="btrfs";DeviceInfoProvider.enrich(layered,inventory(),"/dev/test1");assert(layered.model==""&&layered.physical_size==null);
    var missing=new DeviceInfo();DeviceInfoProvider.enrich(missing,inventory(),"/dev/other");assert(missing.model==""&&missing.capacity==null);
    var first=new DeviceInfo();var second=new DeviceInfo();DeviceInfoProvider.enrich(first,inventory("/dev/a1"),"/dev/a1");DeviceInfoProvider.enrich(second,inventory("/dev/a2"),"/dev/a2");assert(first.label==second.label&&first.uuid!=second.uuid);
}
Gtk.Widget? find_title(Gtk.Widget widget,string title) {
    if(widget is Adw.PreferencesRow&&((Adw.PreferencesRow)widget).title==title)return widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=find_title(child,title);if(found!=null)return found;}return null;
}
Gtk.Widget? find_bar(Gtk.Widget widget) {if(widget is Gtk.ProgressBar)return widget;for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=find_bar(child);if(found!=null)return found;}return null;}
DeviceInfo fixture(int index) {
    var info=new DeviceInfo();
    string[] names={"System Drive","Data HDD","External USB SSD","USB Flash Drive","Unmounted NTFS Volume","Empty DVD Drive","Data DVD","Audio CD","USB Floppy Drive","SCSI Tape Drive","Mounted ISO Image","Disconnected Drive"};
    info.name=names[index];info.status=_("Mounted");info.mounted=true;info.filesystem="ext4";info.mount_point="/fixtures/volume";info.capacity=1000000000;info.used=350000000;info.available=600000000;info.device="/dev/fixture1";info.model="Fixture Model";info.connection="ata";info.serial="LONG-IDENTIFIER-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ-0123456789";
    info.category=DeviceCategory.INTERNAL_VOLUME;
    switch(index) {
    case 0:info.category=DeviceCategory.SYSTEM_FILESYSTEM;info.mount_point="/";break;
    case 1:info.hardware_type="Hard disk drive";break;
    case 2:case 3:info.category=DeviceCategory.REMOVABLE_VOLUME;info.connection="usb";info.filesystem="exfat";break;
    case 4:info.mounted=false;info.mount_point="";info.status="Not mounted";info.filesystem="ntfs";info.capacity=null;info.used=null;info.available=null;info.volume_size=2000000000;break;
    case 5:case 6:case 7:info.category=DeviceCategory.OPTICAL_DRIVE;info.read_only=true;info.media_presence=index==5?MediaPresence.ABSENT:MediaPresence.PRESENT;info.media=index==7?"Audio CD":"DVD-ROM";info.data_tracks=index==6?1:0;info.audio_tracks=index==7?12:0;if(index!=6){info.capacity=null;info.used=null;info.available=null;info.mount_point="";info.filesystem="";info.mounted=false;}else info.filesystem="udf";if(index==5){info.status="Not mounted";info.media="";info.read_only=null;info.audio_tracks=null;info.data_tracks=null;}if(index==7)info.status="Media inserted";break;
    case 8:info.category=DeviceCategory.FLOPPY_DRIVE;info.filesystem="FAT12";info.capacity=1474560;info.used=1000000;info.available=474560;break;
    case 9:info.category=DeviceCategory.TAPE_DRIVE;info.mounted=false;info.capacity=null;info.used=null;info.available=null;info.filesystem="";info.mount_point="";info.device="/dev/nst0";info.connection="SCSI";info.status="Unavailable";break;
    case 10:info.category=DeviceCategory.DISK_IMAGE;info.backing_file="/fixtures/archive.iso";info.read_only=true;break;
    case 11:info=new DeviceInfo();info.name=names[index];info.connected=false;info.status="Disconnected";break;
    }
    return info;
}
async void scenarios(string output) throws Error {
    var window=new Adw.Window();window.set_default_size(760,760);window.present();
    var place=new Place("Fixture",File.new_for_uri("majoris:///device/fixture"));place.section="Devices";
    var provider=new FixtureProvider();
    Gtk.CssProvider? theme_css=null;
    foreach(bool dark in new bool[]{false,true}) {
        var theme=Environment.get_variable("MAJORIS_DEVICE_THEME");
        if(theme!=null){if(theme_css!=null)Gtk.StyleContext.remove_provider_for_display(Gdk.Display.get_default(),theme_css);theme_css=new Gtk.CssProvider();theme_css.load_from_path(theme+"/gtk-4.0/"+(dark?"gtk-dark.css":"gtk.css"));Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),theme_css,Gtk.STYLE_PROVIDER_PRIORITY_USER);}
        Adw.StyleManager.get_default().color_scheme=dark?Adw.ColorScheme.FORCE_DARK:Adw.ColorScheme.FORCE_LIGHT;
        for(int i=0;i<12;i++) {
            provider.value=fixture(i);place.icon_name=i==9?"media-tape-symbolic":i==8?"media-floppy-symbolic":i>=5&&i<=7?"drive-optical-symbolic":i==0?"drive-harddisk-system-symbolic":"drive-harddisk-symbolic";var dialog=new DevicePropertiesDialog(place,provider);dialog.present(window);yield pause_layout();
            assert(dialog.information==provider.value);assert(find_title(dialog.general,"Type")!=null);
            assert((find_bar(dialog.general)!=null)==provider.value.show_usage);
            if(i==5||i==7||i==9||i==11)assert(find_bar(dialog.general)==null);
            if(output!="")yield capture(window,output,"%s-%02d".printf(dark?"dark":"light",i));
            if(i==2){((Adw.ActionRow)find_title(dialog.general,"Hardware Details")).activated();yield pause_layout();assert(find_title(dialog.hardware,"Serial number")!=null);if(output!="")yield capture(window,output,dark?"dark-hardware":"light-hardware");}
            dialog.close();yield pause_layout();
        }
    }
    provider.value=fixture(2);var dialog=new DevicePropertiesDialog(place,provider);dialog.present(window);yield pause_layout();
    provider.update(fixture(11));yield pause_layout();assert(dialog.information.connected==false&&find_bar(dialog.general)==null&&find_title(dialog.hardware,"Serial number")==null);
    provider.delay=true;provider.update(fixture(3));yield pause_layout();provider.update(fixture(11));dialog.close();yield pause_layout();int queries=provider.queries;provider.changed();yield pause_layout();assert(provider.queries==queries);
    provider.delay=false;
    provider.value=fixture(2);var released=new DevicePropertiesDialog(place,provider);var weak_dialog=WeakRef(released);released.present(window);yield pause_layout();released.close();yield pause_layout();released=null;yield pause_layout();assert(weak_dialog.get()==null);
    provider.fail=true;dialog=new DevicePropertiesDialog(place,provider);dialog.present(window);yield pause_layout();assert(dialog.information.status=="Unavailable"&&find_bar(dialog.general)==null);dialog.close();yield pause_layout();window.destroy();
}
int main(string[] args) {
    evidence_output=Environment.get_variable("MAJORIS_DEVICE_EVIDENCE")??"";
    Test.init(ref args);Gtk.init();Adw.init();
    Test.add_func("/devices/calculations",calculations);Test.add_func("/devices/mapping",mapping);
    Test.add_func("/devices/provider",()=>{var loop=new MainLoop();provider_cases.begin((o,r)=>{try{provider_cases.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    Test.add_func("/devices/tape-discovery",()=>{try{var path=DirUtils.make_tmp("majoris-tapes-XXXXXX");assert(Places.tape_devices(path).size==0);DirUtils.create(path+"/st0",0700);DirUtils.create(path+"/nst0",0700);var tapes=Places.tape_devices(path);assert(tapes.size==1&&tapes[0].file.get_path()=="/dev/nst0");DirUtils.remove(path+"/st0");DirUtils.remove(path+"/nst0");DirUtils.remove(path);}catch(Error e){error("%s",e.message);}});
    Test.add_func("/devices/dialog",()=>{var loop=new MainLoop();scenarios.begin(evidence_output,(o,r)=>{try{scenarios.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    return Test.run();
}
