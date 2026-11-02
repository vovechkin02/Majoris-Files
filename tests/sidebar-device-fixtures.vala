class SidebarDrive : Object, Drive {
    public SidebarVolume? volume;
    public Gee.ArrayList<Volume> additional = new Gee.ArrayList<Volume>();
    public int mutations;
    public bool can_eject(){return true;}
    public bool can_poll_for_media(){return true;}
    public bool can_start(){return false;}
    public bool can_start_degraded(){return false;}
    public bool can_stop(){return false;}
    public async bool eject(MountUnmountFlags flags,Cancellable? token=null) throws Error{mutations++;return true;}
    public async bool eject_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return true;}
    public string[] enumerate_identifiers(){return {VolumeIdentifier.UNIX_DEVICE};}
    public Icon get_icon(){return new ThemedIcon("drive-removable-media-symbolic");}
    public Icon get_symbolic_icon(){return get_icon();}
    public string? get_identifier(string kind){return kind==VolumeIdentifier.UNIX_DEVICE?"/dev/test1":null;}
    public string get_name(){return "Fixture Reader";}
    public DriveStartStopType get_start_stop_type(){return DriveStartStopType.UNKNOWN;}
    public GLib.List<Volume> get_volumes(){var result=new GLib.List<Volume>();if(volume!=null)result.append(volume);foreach(var item in additional)result.append(item);return result;}
    public bool has_media(){return volume!=null;}
    public bool has_volumes(){return volume!=null;}
    public bool is_media_check_automatic(){return true;}
    public bool is_media_removable(){return true;}
    public bool is_removable(){return true;}
    public async bool poll_for_media(Cancellable? token=null) throws Error{mutations++;return true;}
    public async bool start(DriveStartFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return true;}
    public async bool stop(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return true;}
}
class SidebarMount : Object, Mount {
    SidebarVolume volume;
    public bool ejectable;
    public int mutations;
    public SidebarMount(SidebarVolume volume){this.volume=volume;}
    public bool can_eject(){return ejectable;}
    public bool can_unmount(){return true;}
    public async bool eject(MountUnmountFlags flags,Cancellable? token=null) throws Error{mutations++;return true;}
    public async bool eject_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return true;}
    public File get_default_location(){return get_root();}
    public Drive? get_drive(){return volume.drive;}
    public Icon get_icon(){return new ThemedIcon("drive-removable-media-symbolic");}
    public Icon get_symbolic_icon(){return get_icon();}
    public string get_name(){return volume.display_name;}
    public File get_root(){return volume.root;}
    public string? get_uuid(){return volume.get_uuid();}
    public Volume? get_volume(){return volume;}
    public async string[] guess_content_type(bool force,Cancellable? token=null) throws Error{return {};}
    public string[] guess_content_type_sync(bool force,Cancellable? token=null) throws Error{return {};}
    public async bool remount(MountMountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;return true;}
    public async bool unmount(MountUnmountFlags flags,Cancellable? token=null) throws Error{mutations++;return true;}
    public async bool unmount_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error{mutations++;volume.mounted=null;volume.mounted_changed();return true;}
}
class SidebarVolume : Object, Volume {
    public signal void mounted_changed();
    public int mutations;
    public SidebarDrive? drive;
    public SidebarMount? mounted;
    public string display_name="Fixture volume";
    public File root=File.new_for_path("/tmp");
    public bool fail_mount;
    public bool delayed;
    public bool can_eject(){return false;}
    public bool can_mount(){return mounted==null;}
    public async bool eject(MountUnmountFlags flags,Cancellable? token=null) throws Error {mutations++;return true;}
    public async bool eject_with_operation(MountUnmountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error {mutations++;return true;}
    public string[] enumerate_identifiers(){return {VolumeIdentifier.UNIX_DEVICE};}
    public File? get_activation_root(){return null;}
    public Drive? get_drive(){return drive;}
    public Icon get_icon(){return new ThemedIcon("drive-removable-media-symbolic");}
    public Icon get_symbolic_icon(){return get_icon();}
    public string? get_identifier(string kind){return kind==VolumeIdentifier.UNIX_DEVICE?"/dev/test1":null;}
    public Mount? get_mount(){return mounted;}
    public string get_name(){return display_name;}
    public string? get_uuid(){return "fixture-volume";}
    public async bool mount(MountMountFlags flags,MountOperation? operation,Cancellable? token=null) throws Error {mutations++;if(delayed)yield pause_layout();if(token!=null)token.set_error_if_cancelled();if(fail_mount)throw new IOError.PERMISSION_DENIED("Fixture mount denied");mounted=new SidebarMount(this);mounted_changed();return true;}
    public bool should_automount(){return false;}
}
