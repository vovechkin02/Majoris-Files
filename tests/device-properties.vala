using MajorisFiles;
string evidence_output;
string media_evidence;
Variant media_inventory(string current,string[] compatibility,bool? media_removable=true,bool? available=true,bool? detected=true,string bus="usb",bool? removable=true,bool optical=false,string drive_path="/drives/test",bool image=false,string usage="filesystem") {
    var block=properties({"Device","PreferredDevice","Drive","IdType","IdLabel","Size","ReadOnly","IdUsage","CryptoBackingDevice"},
        {new Variant.bytestring("/dev/test1"),new Variant.bytestring("/dev/test1"),new Variant.object_path(drive_path),new Variant.string("exfat"),new Variant.string("CAMERA"),new Variant.uint64(123456789),new Variant.boolean(false),new Variant.string(usage),new Variant.object_path("/blocks/encrypted")});
    var drive=new VariantBuilder(VariantType.VARDICT);
    drive.add("{sv}","Media",new Variant.string(current));drive.add("{sv}","MediaCompatibility",new Variant.strv(compatibility));drive.add("{sv}","ConnectionBus",new Variant.string(bus));
    drive.add("{sv}","Model",new Variant.string("Fixture Reader"));drive.add("{sv}","Size",new Variant.uint64(987654321));drive.add("{sv}","RotationRate",new Variant.int32(0));
    drive.add("{sv}","Optical",new Variant.boolean(optical));drive.add("{sv}","OpticalBlank",new Variant.boolean(true));drive.add("{sv}","OpticalNumAudioTracks",new Variant.uint32(2));drive.add("{sv}","OpticalNumDataTracks",new Variant.uint32(1));
    if(media_removable!=null)drive.add("{sv}","MediaRemovable",new Variant.boolean(media_removable));
    if(available!=null)drive.add("{sv}","MediaAvailable",new Variant.boolean(available));
    if(detected!=null)drive.add("{sv}","MediaChangeDetected",new Variant.boolean(detected));
    if(removable!=null)drive.add("{sv}","Removable",new Variant.boolean(removable));
    var objects=new VariantBuilder(new VariantType("a{oa{sa{sv}}}"));
    objects.add("{o@a{sa{sv}}}","/blocks/test",interfaces(block,null,image?properties({"BackingFile"},{new Variant.bytestring("/fixtures/media.iso")}):null));
    if(drive_path!="/")objects.add("{o@a{sa{sv}}}",drive_path,interfaces(block,drive.end()));
    return objects.end();
}
DeviceInfo media_info(string current,string[] compatibility,bool? media_removable=true,bool? available=true,bool? detected=true,string bus="usb",bool? removable=true,DeviceCategory category=DeviceCategory.GENERIC_STORAGE) {
    var info=new DeviceInfo();info.category=category;
    DeviceInfoProvider.enrich(info,media_inventory(current,compatibility,media_removable,available,detected,bus,removable),"/dev/test1");return info;
}
void media_table() {
    string[] identifiers={"thumb","flash","flash_cf","flash_ms","flash_sm","flash_sd","flash_sdhc","flash_sdxc","flash_sdio","flash_sd_combo","flash_mmc","floppy","floppy_zip","floppy_jaz","optical","optical_cd","optical_cd_r","optical_cd_rw","optical_dvd","optical_dvd_r","optical_dvd_rw","optical_dvd_ram","optical_dvd_plus_r","optical_dvd_plus_rw","optical_dvd_plus_r_dl","optical_dvd_plus_rw_dl","optical_bd","optical_bd_r","optical_bd_re","optical_hddvd","optical_hddvd_r","optical_hddvd_rw","optical_mo","optical_mrw","optical_mrw_w"};
    string[] names={"USB flash drive","Flash memory card","CompactFlash","Memory Stick","SmartMedia","SD card","SDHC card","SDXC card","SDIO","SDIO combination card","MultiMediaCard","Floppy disk","Zip disk","Jaz disk","Optical disc","CD","CD-R","CD-RW","DVD","DVD-R","DVD-RW","DVD-RAM","DVD+R","DVD+RW","DVD+R DL","DVD+RW DL","Blu-ray Disc","BD-R","BD-RE","HD DVD","HD DVD-R","HD DVD-RW","Magneto-optical disc","Mount Rainier compatibility","Mount Rainier writing capability"};
    assert(identifiers.length==35&&MediaIdentity.identifiers().length==35);
    for(int i=0;i<identifiers.length;i++) {
        string raw=identifiers[i];var descriptor=MediaIdentity.describe(raw);assert(descriptor.recognised&&descriptor.identifier==raw&&descriptor.description==names[i]);
        var info=media_info(raw,{raw});
        DeviceCategory expected=i==0?DeviceCategory.REMOVABLE_VOLUME:i<11?DeviceCategory.MEMORY_CARD:i==11?DeviceCategory.FLOPPY_DRIVE:i<14?DeviceCategory.REMOVABLE_CARTRIDGE:DeviceCategory.OPTICAL_DRIVE;
        assert(info.category==expected&&info.media==raw&&info.media_compatibility[0]==raw);
        if(i>0&&i<11){var embedded=media_info(raw,{raw},false,true,true,"ata",false);assert(embedded.category==DeviceCategory.INTERNAL_VOLUME);}
        assert(descriptor.capability?info.media_description()=="":info.media_description()==names[i]);
        assert(info.capacity==null&&info.used==null&&info.available==null); // no format-derived sizes
    }
}
void media_presence_cases() {
    var card=media_info("flash_sdxc",{"flash_sd","flash_mmc"});assert(card.media_presence==MediaPresence.PRESENT&&card.media_description()=="SDXC card"&&card.type_name()=="Memory card");
    var reader=media_info("",{"flash_sd","flash_sdhc","flash_sdxc","flash_mmc"},true,false);assert(reader.category==DeviceCategory.MEMORY_CARD&&reader.type_name()=="Memory card reader"&&reader.media_description()==""&&reader.media_presence==MediaPresence.ABSENT&&reader.capacity==null&&reader.volume_size==null&&reader.filesystem==""&&!reader.show_usage);
    assert(reader.supported_media()=="SD card, SDHC card, SDXC card, MultiMediaCard");
    var single=media_info("",{"flash_sd"},true,false);assert(single.type_name()=="SD card reader"&&single.media=="");
    foreach(bool? detected in new bool?[]{null,false}){var unknown=media_info("",{"flash_sd"},true,false,detected);assert(unknown.media_presence==MediaPresence.UNKNOWN&&unknown.media_description()==""&&unknown.type_name()=="SD card reader");}
    var missing=media_info("",{"flash_sd"},true,null,true);assert(missing.media_presence==MediaPresence.UNKNOWN);
    var embedded=media_info("flash_mmc",{"flash_mmc"},false,true,true,"",false);assert(embedded.category==DeviceCategory.INTERNAL_VOLUME&&embedded.media_presence==MediaPresence.UNKNOWN);
    var thumb=media_info("thumb",{"thumb"},false,true,true);assert(thumb.category==DeviceCategory.REMOVABLE_VOLUME&&thumb.media_description()=="USB flash drive"&&thumb.media_presence==MediaPresence.UNKNOWN);
    var usb=media_info("",{},false,true,true);assert(usb.category==DeviceCategory.REMOVABLE_VOLUME&&usb.media_description()=="");
    var zip=media_info("",{"floppy_zip"},true,false);assert(zip.category==DeviceCategory.REMOVABLE_CARTRIDGE&&zip.type_name()=="Zip drive"&&zip.volume_size==null);
    var jaz=media_info("floppy_jaz",{"floppy"});assert(jaz.category==DeviceCategory.REMOVABLE_CARTRIDGE&&jaz.media_description()=="Jaz disk");
    var capability_only=media_info("optical_mrw_w",{});assert(capability_only.category==DeviceCategory.OPTICAL_DRIVE&&capability_only.media_description()==""&&capability_only.supported_media()=="Mount Rainier writing capability");
    var mrw=media_info("optical_cd_rw",{"optical_mrw","optical_mrw_w","optical_cd_rw"});assert(mrw.media_description()=="CD-RW"&&mrw.supported_media().contains("Mount Rainier writing capability"));
    var future=media_info("flash_unknown_variant",{"flash_unknown_variant"});assert(future.category==DeviceCategory.MEMORY_CARD&&future.media_description()=="Flash memory card"&&future.media=="flash_unknown_variant");
    var unknown_media=media_info("future_device",{"future_capability"},true);assert(unknown_media.media_description()=="Unknown media"&&unknown_media.supported_media()=="Unknown media"&&unknown_media.media=="future_device");
    foreach(var category in new DeviceCategory[]{DeviceCategory.SYSTEM_FILESYSTEM,DeviceCategory.TAPE_DRIVE,DeviceCategory.DISK_IMAGE,DeviceCategory.PORTABLE_DEVICE}){var explicit_info=media_info("flash_sdxc",{"flash_sdxc"},true,true,true,"usb",true,category);assert(explicit_info.category==category);}
    foreach(string bus in new string[]{"ata","nvme"}){var internal=media_info("",{},false,true,true,bus,false);assert(internal.category==DeviceCategory.INTERNAL_VOLUME);}
    var iso=new DeviceInfo();DeviceInfoProvider.enrich(iso,media_inventory("optical_dvd",{"optical_dvd"},true,true,true,"usb",true,true,"/drives/test",true),"/dev/test1");assert(iso.category==DeviceCategory.DISK_IMAGE);
    var btrfs=new DeviceInfo();btrfs.filesystem="btrfs";DeviceInfoProvider.enrich(btrfs,media_inventory("flash_sd",{"flash_sd"}),"/dev/test1");assert(btrfs.category==DeviceCategory.GENERIC_STORAGE&&btrfs.model=="");
    foreach(string usage in new string[]{"filesystem","crypto"}){var logical=new DeviceInfo();DeviceInfoProvider.enrich(logical,media_inventory("",{},null,null,null,"",null,false,"/",false,usage),"/dev/test1");assert(logical.category==DeviceCategory.GENERIC_STORAGE&&logical.model==""&&logical.backing_object=="/blocks/encrypted");if(usage=="crypto")assert(logical.status=="Locked");}
    var generic=media_info("",{},null,null,null,"",null);assert(generic.category==DeviceCategory.GENERIC_STORAGE);
    var optical=new DeviceInfo();DeviceInfoProvider.enrich(optical,media_inventory("optical_mo",{"optical_mo"},true,true,true,"ata",false,true),"/dev/test1");assert(optical.optical&&optical.audio_tracks==2&&optical.data_tracks==1&&optical.blank==true&&optical.media_size==987654321);
}
class FixtureDrive : Object, Drive {
    public FixtureVolume? volume;
    public int mutations;
    public bool can_eject(){return true;}
    public bool can_poll_for_media(){return true;}
    public bool can_start(){return false;}
    public bool can_start_degraded(){return false;}
    public bool can_stop(){return false;}
    public async bool eject(MountUnmountFlags flags,Cancellable? token=null) throws Error{mutations++;return false;}
    public async bool eject_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return false;}
    public string[] enumerate_identifiers(){return {VolumeIdentifier.UNIX_DEVICE};}
    public Icon get_icon(){return new ThemedIcon("drive-removable-media-symbolic");}
    public Icon get_symbolic_icon(){return get_icon();}
    public string? get_identifier(string kind){return kind==VolumeIdentifier.UNIX_DEVICE?"/dev/test1":null;}
    public string get_name(){return "Fixture Reader";}
    public DriveStartStopType get_start_stop_type(){return DriveStartStopType.UNKNOWN;}
    public GLib.List<Volume> get_volumes(){var result=new GLib.List<Volume>();if(volume!=null)result.append(volume);return result;}
    public bool has_media(){return volume!=null;}
    public bool has_volumes(){return volume!=null;}
    public bool is_media_check_automatic(){return true;}
    public bool is_media_removable(){return true;}
    public bool is_removable(){return true;}
    public async bool poll_for_media(Cancellable? token=null) throws Error{mutations++;return false;}
    public async bool start(DriveStartFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return false;}
    public async bool stop(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return false;}
}
class FixtureMount : Object, Mount {
    FixtureVolume volume;
    public int mutations;
    public FixtureMount(FixtureVolume volume){this.volume=volume;}
    public bool can_eject(){return true;}
    public bool can_unmount(){return true;}
    public async bool eject(MountUnmountFlags flags,Cancellable? token=null) throws Error{mutations++;return false;}
    public async bool eject_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return false;}
    public File get_default_location(){return get_root();}
    public Drive? get_drive(){return volume.drive;}
    public Icon get_icon(){return new ThemedIcon("drive-removable-media-symbolic");}
    public Icon get_symbolic_icon(){return get_icon();}
    public string get_name(){return volume.display_name;}
    public File get_root(){return File.new_for_path("/fixtures/reader");}
    public string? get_uuid(){return volume.get_uuid();}
    public Volume? get_volume(){return volume;}
    public async string[] guess_content_type(bool force,Cancellable? token=null) throws Error{return {};}
    public string[] guess_content_type_sync(bool force,Cancellable? token=null) throws Error{return {};}
    public async bool remount(MountMountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return false;}
    public async bool unmount(MountUnmountFlags flags,Cancellable? token=null) throws Error{mutations++;return false;}
    public async bool unmount_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return false;}
}
class FixtureVolume : Object, Volume {
    public int mutations;
    public FixtureDrive? drive;
    public FixtureMount? mounted;
    public string display_name="Fixture volume";
    public bool can_eject(){return false;}
    public bool can_mount(){return true;}
    public async bool eject(MountUnmountFlags flags,Cancellable? token=null) throws Error {mutations++;return false;}
    public async bool eject_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error {mutations++;return false;}
    public string[] enumerate_identifiers(){return {VolumeIdentifier.UNIX_DEVICE};}
    public File? get_activation_root(){return null;}
    public Drive? get_drive(){return drive;}
    public Icon get_icon(){return new ThemedIcon("drive-removable-media-symbolic");}
    public Icon get_symbolic_icon(){return get_icon();}
    public string? get_identifier(string kind){return kind==VolumeIdentifier.UNIX_DEVICE?"/dev/test1":null;}
    public Mount? get_mount(){return mounted;}
    public string get_name(){return display_name;}
    public string? get_uuid(){return "fixture-volume";}
    public async bool mount(MountMountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error {mutations++;return false;}
    public bool should_automount(){return false;}
}
class FixtureMonitor : VolumeMonitor {
    public FixtureVolume? volume;
    public FixtureDrive? drive;
    public override GLib.List<Volume> get_volumes(){var result=new GLib.List<Volume>();if(volume!=null)result.append(volume);return result;}
    public override GLib.List<Mount> get_mounts(){return new GLib.List<Mount>();}
    public override GLib.List<Drive> get_connected_drives(){var result=new GLib.List<Drive>();if(drive!=null)result.append(drive);return result;}
}
class FixtureGioProvider : DeviceInfoProvider {
    public bool objects_fail;
    public bool filesystem_fail;
    public int filesystem_queries;
    public int objects_queries;
    public bool objects_delay;
    public Variant? objects_override;
    public FixtureGioProvider(VolumeMonitor monitor){base(monitor);}
    protected override async Variant read_objects(Cancellable token) throws Error {
        objects_queries++;if(objects_delay){Timeout.add(40,()=>{read_objects.callback();return Source.REMOVE;});yield;}
        token.set_error_if_cancelled();if(objects_fail)throw new IOError.NOT_FOUND("UDisks unavailable");return objects_override??inventory("/dev/test1","",false,true);
    }
    protected override async FileInfo read_filesystem(File root,Cancellable token) throws Error {
        filesystem_queries++;token.set_error_if_cancelled();if(filesystem_fail)throw new IOError.FAILED("GIO unavailable");
        assert(root.equal(File.new_for_path("/"))||root.equal(File.new_for_path("/fixtures/reader")));var info=new FileInfo();info.set_attribute_uint64("filesystem::size",500);info.set_attribute_uint64("filesystem::used",200);info.set_attribute_uint64("filesystem::free",250);info.set_attribute_string("filesystem::type","fixturefs");return info;
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
    var drive=properties({"ConnectionBus","Model","Media","Optical","MediaAvailable","MediaChangeDetected","Removable","RotationRate","Size","OpticalBlank","OpticalNumAudioTracks","OpticalNumDataTracks","MediaCompatibility","MediaRemovable"},
        {new Variant.string(removable?"usb":"ata"),new Variant.string("Fixture hardware"),new Variant.string(media),new Variant.boolean(optical),new Variant.boolean(media!=""),new Variant.boolean(true),new Variant.boolean(removable),new Variant.int32(0),new Variant.uint64(10000),new Variant.boolean(media=="optical_dvd_rw"),new Variant.uint32(media=="optical_cd"?12:0),new Variant.uint32(media=="optical_cd"?0:1),new Variant.strv(floppy?new string[]{"floppy"}:optical?new string[]{"optical_dvd"}:new string[]{}),new Variant.boolean(optical||floppy||media.has_prefix("flash"))});
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
        assert(info.optical&&info.physical_size==null&&(media==""?info.volume_size==null:info.volume_size==1000)&&info.capacity==null&&!info.show_usage);
        assert(info.media_presence==(media==""?MediaPresence.ABSENT:MediaPresence.PRESENT));
        assert(media==""?info.media_size==null:info.media_size==10000);
        if(media=="optical_cd")assert(info.audio_tracks==12&&info.data_tracks==0);
    }
    var usb=new DeviceInfo();DeviceInfoProvider.enrich(usb,inventory("/dev/usb1","flash_sd",false,true),"/dev/usb1");assert(usb.category==DeviceCategory.MEMORY_CARD&&usb.media=="flash_sd");
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
    case 5:case 6:case 7:info.category=DeviceCategory.OPTICAL_DRIVE;info.read_only=true;info.media_presence=index==5?MediaPresence.ABSENT:MediaPresence.PRESENT;info.media=index==7?"optical_cd":"optical_dvd";info.data_tracks=index==6?1:0;info.audio_tracks=index==7?12:0;if(index!=6){info.capacity=null;info.used=null;info.available=null;info.mount_point="";info.filesystem="";info.mounted=false;}else info.filesystem="udf";if(index==5){info.status="Not mounted";info.media="";info.read_only=null;info.audio_tracks=null;info.data_tracks=null;}if(index==7)info.status="Media inserted";break;
    case 8:info.category=DeviceCategory.FLOPPY_DRIVE;info.filesystem="FAT12";info.capacity=1474560;info.used=1000000;info.available=474560;break;
    case 9:info.category=DeviceCategory.TAPE_DRIVE;info.mounted=false;info.capacity=null;info.used=null;info.available=null;info.filesystem="";info.mount_point="";info.device="/dev/nst0";info.connection="SCSI";info.status="Unavailable";break;
    case 10:info.category=DeviceCategory.DISK_IMAGE;info.backing_file="/fixtures/archive.iso";info.read_only=true;break;
    case 11:info=new DeviceInfo();info.name=names[index];info.connected=false;info.status="Disconnected";break;
    }
    return info;
}
async void cache_cases() throws Error {
    var backend=new FixtureGioProvider(new FixtureMonitor());backend.objects_delay=true;
    var one=new Cancellable();var two=new Cancellable();int done=0;
    backend.media_snapshot.begin(one,(o,r)=>{try{backend.media_snapshot.end(r);}catch(Error e){error("%s",e.message);}done++;});
    backend.media_snapshot.begin(two,(o,r)=>{try{backend.media_snapshot.end(r);}catch(Error e){error("%s",e.message);}done++;});
    yield pause_layout();assert(done==2&&backend.objects_queries==1);
    yield backend.media_snapshot(one);assert(backend.objects_queries==1);
    backend.changed();yield backend.media_snapshot(one);assert(backend.objects_queries==2);
    backend.changed();done=0;bool cancelled=false;
    backend.media_snapshot.begin(one,(o,r)=>{try{backend.media_snapshot.end(r);}catch(Error e){error("%s",e.message);}done++;});
    backend.media_snapshot.begin(two,(o,r)=>{try{backend.media_snapshot.end(r);}catch(IOError.CANCELLED e){cancelled=true;}catch(Error e){error("%s",e.message);}done++;});
    two.cancel();yield pause_layout();assert(done==2&&cancelled&&backend.objects_queries==3);
    backend.changed();done=0;
    backend.media_snapshot.begin(one,(o,r)=>{try{backend.media_snapshot.end(r);}catch(Error e){error("%s",e.message);}done++;});
    backend.changed();yield pause_layout();assert(done==1&&backend.objects_queries==5); // invalidated in-flight result is retried
}
async void reader_cases() throws Error {
    foreach(bool cartridge in new bool[]{false,true}) {
        var monitor=new FixtureMonitor();var drive=new FixtureDrive();monitor.drive=drive;
        var backend=new FixtureGioProvider(monitor);var token=new Cancellable();
        var reader=new Place("Reader",File.new_for_uri("majoris:///device/reader"));reader.drive=drive;
        string[] compatibility=cartridge?new string[]{"floppy_zip"}:new string[]{"flash_sd","flash_sdxc"};
        backend.objects_override=media_inventory("",compatibility,true,false);var info=yield backend.query(reader,token);
        assert(!info.mounted&&info.media_presence==MediaPresence.ABSENT&&info.capacity==null&&backend.filesystem_queries==0);
        if(cartridge)assert(info.type_name()=="Zip drive");else assert(info.type_name()=="Memory card reader");
        var volume=new FixtureVolume();volume.drive=drive;volume.display_name="CAMERA";drive.volume=volume;monitor.volume=volume;
        string raw=cartridge?"floppy_zip":"flash_sd";
        backend.objects_override=media_inventory(raw,compatibility);backend.changed();info=yield backend.query(reader,token);
        assert(info.media==raw&&!info.mounted&&info.capacity==null&&info.name=="CAMERA"&&backend.filesystem_queries==0);
        volume.mounted=new FixtureMount(volume);backend.changed();info=yield backend.query(reader,token);
        assert(info.mounted&&info.capacity==500&&info.used==200&&info.available==250&&info.show_usage&&backend.filesystem_queries==1);
        volume.mounted=null;backend.changed();info=yield backend.query(reader,token);assert(!info.mounted&&info.capacity==null&&info.used==null&&backend.filesystem_queries==1);
        drive.volume=null;monitor.volume=null;backend.objects_override=media_inventory("",compatibility,true,false);backend.changed();info=yield backend.query(reader,token);assert(info.media_presence==MediaPresence.ABSENT&&!info.mounted&&info.volume_size==null&&info.filesystem=="");
        // A new volume in the original reader is allowed; a replacement reader is not.
        var next=new FixtureVolume();next.drive=drive;drive.volume=next;monitor.volume=next;raw=cartridge?"floppy_zip":"flash_sdxc";
        backend.objects_override=media_inventory(raw,compatibility);backend.changed();info=yield backend.query(reader,token);assert(info.connected&&info.media==raw&&!info.show_usage);
        monitor.drive=new FixtureDrive();monitor.volume=null;info=yield backend.query(reader,token);assert(!info.connected);
        assert(drive.mutations==0&&volume.mutations==0&&next.mutations==0);drive.volume=null;next.drive=null;volume.drive=null;
    }
}
Gtk.ListBoxRow? sidebar_row(Gtk.Widget widget,Place place) {
    if(widget is Gtk.ListBoxRow&&widget.get_data<Place>("majoris-place")==place)return (Gtk.ListBoxRow)widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=sidebar_row(child,place);if(found!=null)return found;}return null;
}
async void sidebar_widget_case(Adw.Window window) throws Error {
    var provider=new FixtureGioProvider(new FixtureMonitor());provider.objects_override=media_inventory("",{"flash_sd","flash_mmc"},true,false);
    var places=new Places(null,provider);var place=new Place("Card Reader",File.new_for_uri("majoris:///device/fixture"));place.drive=new FixtureDrive();place.section="Devices";place.icon=new ThemedIcon("drive-harddisk-symbolic");places.entries.add(place);
    var temporary=DirUtils.make_tmp("majoris-media-sidebar-XXXXXX");var metadata=new MetadataStore(temporary+"/state.db");var browser=new Browser(metadata,places);window.content=browser;yield pause_layout();
    var row=sidebar_row(browser,place);assert(row!=null);var image=((Gtk.Box)row.child).get_first_child() as Gtk.Image;assert(image!=null);
    places.apply_media_snapshot(media_inventory("flash_sd",{"flash_sd"}));assert(sidebar_row(browser,place)==row&&place.device_info.category==DeviceCategory.MEMORY_CARD);
    assert(((ThemedIcon)image.get_gicon()).get_names()[0]=="media-flash-symbolic");
    places.apply_media_snapshot(media_inventory("floppy_zip",{"floppy_zip"}));assert(sidebar_row(browser,place)==row&&place.device_info.category==DeviceCategory.REMOVABLE_CARTRIDGE);
    assert(((ThemedIcon)image.get_gicon()).get_names()[0]=="drive-removable-media-symbolic");
    places.apply_media_snapshot(media_inventory("",{"flash_sd","flash_mmc"},true,false));assert(sidebar_row(browser,place)==row&&place.device_info.media==""&&place.device_info.type_name()=="Memory card reader");
    assert(((Gtk.Label)((Gtk.Box)row.child).get_last_child()).label=="Card Reader");assert(provider.objects_queries==1);
    places.set_device_information(place,null);assert(((ThemedIcon)image.get_gicon()).get_names()[0]=="drive-harddisk-symbolic");window.content=null;
}
string property_value(Gtk.Widget widget,string title) {
    var row=find_title(widget,title) as PropertiesInformationRow;assert(row!=null);return row.value;
}
async void media_scenarios() throws Error {
    string[] media={"flash_sd","flash_sdhc","flash_sdxc","flash_cf","flash_ms","flash_sm","flash_mmc","","floppy_zip","floppy_jaz","optical_dvd_ram","optical_hddvd","optical_mo","future_variant"};
    string[] names={"SD card","SDHC card","SDXC card","CompactFlash","Memory Stick","SmartMedia","MultiMediaCard","Card Reader","Zip Drive","Jaz Drive","DVD-RAM","HD DVD","Magneto-optical","Unknown Removable"};
    string[] descriptions={"SD card","SDHC card","SDXC card","CompactFlash","Memory Stick","SmartMedia","MultiMediaCard","","Zip disk","Jaz disk","DVD-RAM","HD DVD","Magneto-optical disc","Unknown media"};
    var window=new Adw.Window();window.set_default_size(760,820);window.present();var place=new Place("CAMERA",File.new_for_uri("majoris:///device/fixture"));place.icon_name="drive-removable-media-symbolic";
    var provider=new FixtureProvider();Gtk.CssProvider? theme_css=null;
    foreach(bool dark in new bool[]{false,true}) {
        var theme=Environment.get_variable("MAJORIS_DEVICE_THEME");if(theme!=null){if(theme_css!=null)Gtk.StyleContext.remove_provider_for_display(Gdk.Display.get_default(),theme_css);theme_css=new Gtk.CssProvider();theme_css.load_from_path(theme+"/gtk-4.0/"+(dark?"gtk-dark.css":"gtk.css"));Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),theme_css,Gtk.STYLE_PROVIDER_PRIORITY_USER);}
        Adw.StyleManager.get_default().color_scheme=dark?Adw.ColorScheme.FORCE_DARK:Adw.ColorScheme.FORCE_LIGHT;
        for(int i=0;i<media.length;i++) {
            string[] compatibility=i==7?new string[]{"flash_sd","flash_sdhc","flash_sdxc","flash_mmc"}:new string[]{media[i]};
            var info=new DeviceInfo();info.name=i<7?"CAMERA":names[i];info.status="Mounted";info.mounted=i!=7;info.mount_point="/fixtures/CAMERA";
            DeviceInfoProvider.enrich(info,media_inventory(media[i],compatibility,true,i!=7,true,"usb",true,i>=10&&i<=12),"/dev/test1");
            if(i>=10&&i<=12){info.blank=false;info.audio_tracks=0;}if(i==12){info.audio_tracks=null;info.data_tracks=null;}
            if(i!=7){var fs=new FileInfo();fs.set_attribute_uint64("filesystem::size",90000000);fs.set_attribute_uint64("filesystem::used",20000000);fs.set_attribute_uint64("filesystem::free",65000000);fs.set_attribute_string("filesystem::type",i>=10&&i<=12?"udf":"exfat");info.filesystem_info(fs);}
            provider.value=info;var dialog=new DevicePropertiesDialog(place,provider);dialog.present(window);yield pause_layout();
            string expected=i<7?"Memory card":i==7?"Memory card reader":i<10?"Removable disk cartridge":i<=12?"Optical disc drive":"Removable storage";
            assert(property_value(dialog.general,"Type")==expected);assert((find_bar(dialog.general)!=null)==info.show_usage);
            if(i==7){assert(find_title(dialog.general,"Media type")==null&&find_bar(dialog.general)==null);assert(property_value(dialog.general,"Media")=="No card inserted");}
            else assert(property_value(dialog.general,"Media type")==descriptions[i]);
            if(i==12)assert(property_value(dialog.general,"Filesystem capacity")==Paths.size(90000000));
            if(media_evidence!="")yield capture(window,media_evidence,"%s-media-%02d".printf(dark?"dark":"light",i));
            ((Adw.ActionRow)find_title(dialog.general,"Hardware Details")).activated();yield pause_layout();
            assert(property_value(dialog.hardware,"Supported media")==info.supported_media());assert(!property_value(dialog.hardware,"Supported media").contains("_"));
            if(media_evidence!=""&&i==7)yield capture(window,media_evidence,dark?"dark-reader-hardware":"light-reader-hardware");
            dialog.close();yield pause_layout();
        }
    }
    // Reader lifecycle: capability is never substituted for the current medium.
    provider.value=media_info("",{"flash_sd","flash_sdxc"},true,false);provider.value.name="Reader";
    var dialog=new DevicePropertiesDialog(place,provider);dialog.present(window);yield pause_layout();assert(find_bar(dialog.general)==null);
    foreach(string raw in new string[]{"flash_sd","flash_sdxc"}) {
        var info=media_info(raw,{"flash_sd","flash_sdxc"});info.name="CAMERA";info.status="Not mounted";provider.update(info);yield pause_layout();assert(dialog.information.media==raw&&find_bar(dialog.general)==null);
        info=media_info(raw,{"flash_sd","flash_sdxc"});info.name="CAMERA";info.mounted=true;info.status="Mounted";info.capacity=1000;info.used=400;info.available=500;provider.update(info);yield pause_layout();assert(find_bar(dialog.general)!=null);
        provider.update(media_info(raw,{"flash_sd","flash_sdxc"}));yield pause_layout();assert(find_bar(dialog.general)==null);
        provider.update(media_info("",{"flash_sd","flash_sdxc"},true,false));yield pause_layout();assert(find_title(dialog.general,"Media type")==null&&find_bar(dialog.general)==null);
    }
    provider.delay=true;provider.update(media_info("flash_sd",{"flash_sd"}));
    provider.update(media_info("flash_sdxc",{"flash_sdxc"}));yield pause_layout();assert(dialog.information.media=="flash_sdxc");dialog.close();yield pause_layout();yield sidebar_widget_case(window);window.destroy();
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
    media_evidence=Environment.get_variable("MAJORIS_MEDIA_EVIDENCE")??"";
    evidence_output=Environment.get_variable("MAJORIS_DEVICE_EVIDENCE")??"";
    Test.init(ref args);Gtk.init();Adw.init();
    Test.add_func("/devices/media-table",media_table);Test.add_func("/devices/media-presence",media_presence_cases);
    Test.add_func("/devices/snapshot-cache",()=>{var loop=new MainLoop();cache_cases.begin((o,r)=>{try{cache_cases.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    Test.add_func("/devices/reader-lifecycle",()=>{var loop=new MainLoop();reader_cases.begin((o,r)=>{try{reader_cases.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    Test.add_func("/devices/media-dialog",()=>{var loop=new MainLoop();media_scenarios.begin((o,r)=>{try{media_scenarios.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    Test.add_func("/devices/calculations",calculations);Test.add_func("/devices/mapping",mapping);
    Test.add_func("/devices/provider",()=>{var loop=new MainLoop();provider_cases.begin((o,r)=>{try{provider_cases.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    Test.add_func("/devices/tape-discovery",()=>{try{var path=DirUtils.make_tmp("majoris-tapes-XXXXXX");assert(Places.tape_devices(path).size==0);DirUtils.create(path+"/st0",0700);DirUtils.create(path+"/nst0",0700);var tapes=Places.tape_devices(path);assert(tapes.size==1&&tapes[0].file.get_path()=="/dev/nst0");DirUtils.remove(path+"/st0");DirUtils.remove(path+"/nst0");DirUtils.remove(path);}catch(Error e){error("%s",e.message);}});
    Test.add_func("/devices/dialog",()=>{var loop=new MainLoop();scenarios.begin(evidence_output,(o,r)=>{try{scenarios.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    return Test.run();
}
