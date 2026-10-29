namespace MajorisFiles {
    public class Place : Object {
        public string label;
        public string section = "";
        public string icon_name = "folder-symbolic";
        public Icon? icon;
        public File file;
        public Mount? mount;
        public Volume? volume;
        public Drive? drive;
        public bool system;
        public CloudProviders.Account? cloud;
        public Place(string label, File file, Mount? mount = null) {
            this.label=label; this.file=file; this.mount=mount;
        }
    }
    // GIO inventory projected into testable filesystem identities. Different
    // volumes of one drive remain separate; display labels are never identities.
    public class SidebarDevice : Object {
        public Place place;
        public string identity;
        public int order;
        public bool visible = true;
        public SidebarDevice(Place place, string identity, int order) {
            this.place=place;this.identity=identity;this.order=order;
        }
    }
    public class Places : Object {
        public Gee.ArrayList<Place> entries = new Gee.ArrayList<Place>();
        public signal void changed();
        VolumeMonitor volumes;
        FileMonitor? watcher;
        ulong[] volume_handlers;
        uint config_refresh;
        CloudAccounts cloud = new CloudAccounts();
        string last_signature = "";
        public string root_filesystem { get; private set; default = ""; }
        [CCode (cname = "g_reload_user_special_dirs_cache", cheader_filename = "glib.h")]
        static extern void reload_special_dirs();
        public Places(MetadataStore? metadata = null) {
            volumes=VolumeMonitor.get();
            weak Places self=this;
            volume_handlers={
                volumes.mount_added.connect(()=>{if(self!=null)self.reload();}),
                volumes.mount_removed.connect(()=>{if(self!=null)self.reload();}),
                volumes.mount_changed.connect(()=>{if(self!=null)self.reload();}),
                volumes.volume_added.connect(()=>{if(self!=null)self.reload();}),
                volumes.volume_removed.connect(()=>{if(self!=null)self.reload();}),
                volumes.volume_changed.connect(()=>{if(self!=null)self.reload();}),
                volumes.drive_connected.connect(()=>{if(self!=null)self.reload();}),
                volumes.drive_disconnected.connect(()=>{if(self!=null)self.reload();}),
                volumes.drive_changed.connect(()=>{if(self!=null)self.reload();})
            };
            // GTK bookmarks are never read into the navigation model or Favorites.
            var configuration=File.new_for_path(Path.build_filename(Environment.get_user_config_dir(),"user-dirs.dirs"));
            try {
                watcher=configuration.monitor_file(FileMonitorFlags.NONE);
                watcher.changed.connect(()=>{
                    if(self==null)return;
                    if(self.config_refresh!=0)Source.remove(self.config_refresh);
                    self.config_refresh=Timeout.add(100,()=>{if(self!=null){self.config_refresh=0;reload_special_dirs();self.reload();}return Source.REMOVE;});
                });
            } catch(Error e) {}
            reload();
        }
        protected override void dispose() {
            if(config_refresh!=0){Source.remove(config_refresh);config_refresh=0;}
            if(watcher!=null){watcher.cancel();watcher=null;}
            foreach(var handler in volume_handlers)volumes.disconnect(handler);
            volume_handlers={};base.dispose();
        }
        public Gee.ArrayList<Place> cloud_locations() { return cloud.entries; }
        public Gee.ArrayList<File> search_roots() {
            var roots=new Gee.ArrayList<File>();roots.add(File.new_for_path(Environment.get_home_dir()));
            foreach(var mount in volumes.get_mounts()) {
                var root=mount.get_root();bool covered=false;
                foreach(var existing in roots)if(root.equal(existing)||root.has_prefix(existing))covered=true;
                if(!covered)roots.add(root);
            }
            return roots;
        }
        public static Gee.ArrayList<Place> standard_folders(string?[] paths) {
            string[] names={_("Desktop"),_("Documents"),_("Downloads"),_("Pictures"),_("Music"),_("Videos")};
            string[] icons={"user-desktop-symbolic","folder-documents-symbolic","folder-download-symbolic","folder-pictures-symbolic","folder-music-symbolic","folder-videos-symbolic"};
            var result=new Gee.ArrayList<Place>();var home=File.new_for_path(Environment.get_home_dir());
            for(int i=0;i<int.min(paths.length,names.length);i++) {
                if(paths[i]==null||!Path.is_absolute(paths[i]))continue;
                var file=File.new_for_path(paths[i]);if(file.equal(home))continue;
                bool duplicate=false;foreach(var existing in result)if(file.equal(existing.file))duplicate=true;
                if(duplicate)continue;
                var folder=new Place(names[i],file);folder.section="Folders";folder.icon_name=icons[i];result.add(folder);
            }
            return result;
        }
        public static Gee.ArrayList<Place> compose(Gee.List<Place> folders, Gee.List<SidebarDevice> devices, string root_identity="") {
            var result=new Gee.ArrayList<Place>();
            var recent=new Place(_("Recent"),File.new_for_uri("recent:///"));recent.icon_name="document-open-recent-symbolic";result.add(recent);
            var favorites=new Place(_("Favorites"),File.new_for_uri("majoris:///favorites"));favorites.icon_name="starred-symbolic";result.add(favorites);
            result.add_all(folders);
            var system=new Place(_("System Drive"),File.new_for_path("/"));system.section="Devices";system.system=true;system.icon_name="drive-harddisk-system-symbolic";result.add(system);
            var ordered=new Gee.ArrayList<SidebarDevice>();ordered.add_all(devices);
            ordered.sort((a,b)=>{int order=a.order-b.order;if(order!=0)return order;order=a.place.label.collate(b.place.label);return order!=0?order:strcmp(a.identity,b.identity);});
            var identities=new Gee.HashSet<string>();if(root_identity!="")identities.add(root_identity);
            foreach(var device in ordered) {
                if(!device.visible)continue;
                if(device.identity!=""&&identities.contains(device.identity))continue;
                bool duplicate=false;foreach(var existing in result)if(existing.section=="Devices"&&existing.file.equal(device.place.file))duplicate=true;
                if(duplicate)continue;
                if(device.identity!="")identities.add(device.identity);
                device.place.section="Devices";result.add(device.place);
            }
            var network=new Place(_("Network"),File.new_for_uri("network:///"));network.icon_name="network-workgroup-symbolic";result.add(network);
            var trash=new Place(_("Trash"),File.new_for_uri("trash:///"));trash.icon_name="user-trash-symbolic";result.add(trash);
            return result;
        }
        static Gee.HashMap<string,string> mount_identities() {
            // GUnixMountEntry identifies the enclosing mount. Kernel filesystem
            // numbers distinguish anonymous tmpfs/overlay instances whose source
            // labels can be identical. This is a snapshot on GIO events, no poll.
            try {
                string contents;FileUtils.get_contents("/proc/self/mountinfo",out contents);
                return parse_mount_identities(contents);
            }catch(Error e){}
            return new Gee.HashMap<string,string>();
        }
        internal static Gee.HashMap<string,string> parse_mount_identities(string contents) {
            var result=new Gee.HashMap<string,string>();
            if(contents.length>8*1024*1024)return result;
            foreach(var line in contents.split("\n")) {
                var fields=line.split(" ");if(fields.length<7)continue;
                result[fields[4].compress()]=fields[2]+"\n"+fields[3];
            }
            return result;
        }
        static string filesystem_identity(UnixMountEntry entry, Gee.Map<string,string> identities) {
            // Include the filesystem root so independent Btrfs subvolumes are
            // not mistaken for aliases of /. No physical-device assumptions.
            if(identities.has_key(entry.get_mount_path()))return identities[entry.get_mount_path()];
            string source=entry.get_device_path();
            // Fail conservatively if mountinfo is unavailable: never merge
            // different anonymous filesystems just because both say "tmpfs".
            if(!Path.is_absolute(source)&&!source.contains(":"))return "mount:"+entry.get_mount_path();
            return source+"\n"+entry.get_fs_type()+"\n"+entry.get_root_path();
        }
        static string volume_identity(Volume volume) {
            var uuid=volume.get_uuid();if(uuid!=null&&uuid!="")return "uuid:"+uuid;
            var device=volume.get_identifier(VolumeIdentifier.UNIX_DEVICE);if(device!=null&&device!="")return "device:"+device;
            return "volume:%u".printf(direct_hash(volume));
        }
        static int device_order(File? file, Drive? drive, Icon icon) {
            string scheme=file==null?"":file.get_uri_scheme();string description=icon.to_string()??"";
            if(scheme=="mtp"||scheme=="gphoto2"||description.contains("phone")||description.contains("camera"))return 4;
            if(scheme=="cdda"||description.contains("optical"))return 3;
            if(drive!=null&&(drive.is_removable()||drive.is_media_removable()))return 2;
            return file==null||file.is_native()?1:5;
        }
        public void reload() {
            string?[] paths={Environment.get_user_special_dir(UserDirectory.DESKTOP),Environment.get_user_special_dir(UserDirectory.DOCUMENTS),Environment.get_user_special_dir(UserDirectory.DOWNLOAD),Environment.get_user_special_dir(UserDirectory.PICTURES),Environment.get_user_special_dir(UserDirectory.MUSIC),Environment.get_user_special_dir(UserDirectory.VIDEOS)};
            var candidates=new Gee.ArrayList<SidebarDevice>();
            var identities=mount_identities();
            var root_entry=new UnixMountEntry.for("/");root_filesystem=root_entry==null?"":filesystem_identity(root_entry,identities);
            var root_volumes=new Gee.HashSet<string>();
            foreach(var mount in volumes.get_mounts()) {
                var file=mount.get_root();var volume=mount.get_volume();
                UnixMountEntry? entry=null;if(file.is_native())entry=new UnixMountEntry.for(file.get_path());
                bool root=file.equal(File.new_for_path("/"))||(entry!=null&&root_filesystem!=""&&filesystem_identity(entry,identities)==root_filesystem);
                if(root){if(volume!=null)root_volumes.add(volume_identity(volume));continue;}
                if(mount.is_shadowed())continue;
                // GVolumeMonitor already applies UDisks visibility hints. Also
                // reject incidental native system mounts, never scan raw blocks.
                if(entry!=null&&entry.is_system_internal()&&!entry.guess_should_display())continue;
                var place=new Place(mount.get_name(),file,mount);place.icon=mount.get_symbolic_icon();
                var drive=mount.get_drive();
                string identity="mount:"+file.get_uri();
                if(entry!=null)identity="filesystem:"+filesystem_identity(entry,identities);
                else if(volume!=null)identity=volume_identity(volume);
                candidates.add(new SidebarDevice(place,identity,device_order(file,drive,place.icon)));
            }
            foreach(var volume in volumes.get_volumes()) {
                if(volume.get_mount()!=null||!volume.can_mount()||root_volumes.contains(volume_identity(volume)))continue;
                if(root_entry!=null&&volume.get_identifier(VolumeIdentifier.UNIX_DEVICE)==root_entry.get_device_path())continue;
                var place=new Place(volume.get_name(),volume.get_activation_root()??File.new_for_uri("majoris:///device/"+Uri.escape_string(volume_identity(volume))));
                place.volume=volume;place.icon=volume.get_symbolic_icon();
                candidates.add(new SidebarDevice(place,volume_identity(volume),device_order(volume.get_activation_root(),volume.get_drive(),place.icon)));
            }
            foreach(var drive in volumes.get_connected_drives()) {
                var icon=drive.get_symbolic_icon();
                if(drive.has_volumes()||!drive.is_media_removable()||!(icon.to_string()??"").contains("optical"))continue;
                var identity=drive.get_identifier(VolumeIdentifier.UNIX_DEVICE)??"drive:%u".printf(direct_hash(drive));
                var place=new Place(drive.get_name(),File.new_for_uri("majoris:///device/"+Uri.escape_string(identity)));place.drive=drive;place.icon=icon;
                candidates.add(new SidebarDevice(place,identity,3));
            }
            var next=compose(standard_folders(paths),candidates,root_filesystem);
            var signature=new StringBuilder();
            foreach(var place in next){
                string icon=place.icon_name;if(place.icon!=null)icon=place.icon.to_string();
                signature.append_printf("%s\n%s\n%s\n%s\n%u:%u:%u\n",place.label,place.file.get_uri(),place.section,icon,place.mount==null?0:direct_hash(place.mount),place.volume==null?0:direct_hash(place.volume),place.drive==null?0:direct_hash(place.drive));
            }
            if(signature.str!=last_signature){entries=next;last_signature=signature.str;changed();}
        }
    }
}
