namespace MajorisFiles {
    // Only ObjectManager metadata and GIO filesystem queries; never opens devices.
    public class DeviceInfoProvider : Object, DeviceInformationProvider {
        const string SERVICE = "org.freedesktop.UDisks2";
        const string ROOT = "/org/freedesktop/UDisks2";
        const string BLOCK = "org.freedesktop.UDisks2.Block";
        const string DRIVE = "org.freedesktop.UDisks2.Drive";
        const string FS = "org.freedesktop.UDisks2.Filesystem";
        static DeviceInfoProvider? instance;
        VolumeMonitor volume_monitor;
        public DeviceInfoProvider(VolumeMonitor? inventory = null) { this.volume_monitor=inventory??VolumeMonitor.get(); }
        DBusConnection? bus;
        uint subscription;
        uint owner_subscription;
        public static DeviceInfoProvider get_default() {
            if (instance == null) instance = new DeviceInfoProvider();
            return instance;
        }
        public static Place? for_root(File file) {
            if (file.equal(File.new_for_path("/"))) { var root = new Place(_("System Drive"), file); root.system = true; root.section = "Devices"; root.icon_name = "drive-harddisk-system-symbolic"; return root; }
            foreach (var mount in VolumeMonitor.get().get_mounts()) if (mount.get_root().equal(file)) { var place = new Place(mount.get_name(), file, mount); place.icon = mount.get_symbolic_icon(); place.section = "Devices"; return place; }
            return null;
        }
        public async DeviceInfo query(Place place, Cancellable token) throws Error {
            token.set_error_if_cancelled();
            var info = new DeviceInfo(); info.name = place.label;
            var monitor = volume_monitor;
            Volume? volume = place.volume ?? (place.mount == null ? null : place.mount.get_volume());
            Drive? drive = place.drive ?? (volume == null ? (place.mount == null ? null : place.mount.get_drive()) : volume.get_drive());
            Mount? mount = volume == null ? place.mount : volume.get_mount();
            bool present = place.system || place.tape_sysfs != "";
            if (volume != null) { foreach (var current in monitor.get_volumes()) if (current == volume) present = true; }
            else if (drive != null) { foreach (var current in monitor.get_connected_drives()) if (current == drive) present = true; }
            else if (mount != null) { foreach (var current in monitor.get_mounts()) if (current == mount) present = true; }
            // A removable drive outlives its medium. Reconcile only within the
            // original GDrive; never attach a new drive reusing a /dev name.
            if (!present && drive != null && drive.is_media_removable()) {
                foreach (var current in monitor.get_connected_drives()) if (current == drive) {
                    present = true; volume = null; mount = null;
                    var media = drive.get_volumes();
                    if (media.length() == 1) { volume = media.data; mount = volume.get_mount(); }
                }
            }
            if(!place.system) { if(volume!=null)info.name=volume.get_name();else if(drive!=null)info.name=drive.get_name();else if(mount!=null)info.name=mount.get_name(); }
            info.connected = present;
            if (!present) { info.status = _("Disconnected"); return info; }
            if (place.tape_sysfs != "") { yield tape_info(info, place, token); return info; }
            File? root = place.system ? File.new_for_path("/") : mount == null ? null : mount.get_root();
            info.category = place.system ? DeviceCategory.SYSTEM_FILESYSTEM : DeviceCategory.GENERIC_STORAGE;
            info.mounted = root != null;
            info.status = info.mounted ? _("Mounted") : _("Not mounted");
            if (root != null) {
                info.mount_point = root.get_path() ?? root.get_uri();
                string scheme = root.get_uri_scheme();
                if (scheme == "mtp" || scheme == "gphoto2" || scheme == "afc") info.category = DeviceCategory.PORTABLE_DEVICE;
                if (scheme == "cdda") { info.category = DeviceCategory.OPTICAL_DRIVE; info.media = _("Audio CD"); }
            }
            if (volume != null) { info.device = volume.get_identifier(VolumeIdentifier.UNIX_DEVICE) ?? ""; info.uuid = volume.get_uuid() ?? ""; }
            if (info.device == "" && drive != null) info.device = drive.get_identifier(VolumeIdentifier.UNIX_DEVICE) ?? "";
            if (root != null && root.is_native()) {
                var entry = new UnixMountEntry.for(root.get_path());
                if (entry != null) { info.filesystem = entry.get_fs_type(); if (info.device == "" && entry.get_fs_type() != "btrfs") info.device = entry.get_device_path(); }
            }
            info.identity = info.device != "" ? info.device : (root == null ? "" : root.get_uri());
            if (drive != null) {
                if (drive.is_removable() || drive.is_media_removable()) { if (!place.system && info.category == DeviceCategory.GENERIC_STORAGE) info.category = DeviceCategory.REMOVABLE_VOLUME; }
                if (drive.is_media_check_automatic()) info.media_presence = drive.has_media() ? MediaPresence.PRESENT : MediaPresence.ABSENT;
            }
            try {
                var objects=yield read_objects(token);
                enrich(info, objects, info.device, info.filesystem == "btrfs" ? null : root);
            } catch (Error e) { token.set_error_if_cancelled(); }
            if (info.media_presence == MediaPresence.ABSENT) { info.volume_size=null;info.filesystem="";info.label="";info.uuid="";info.read_only=null;info.blank=null;info.audio_tracks=null;info.data_tracks=null; }
            if (root != null && !root.has_uri_scheme("cdda") && info.media_presence != MediaPresence.ABSENT && !(info.optical && info.audio_tracks != null && info.audio_tracks > 0 && info.data_tracks == 0) && info.category != DeviceCategory.TAPE_DRIVE) {
                try { var fs = yield read_filesystem(root, token); info.filesystem_info(fs); }
                catch (Error e) { token.set_error_if_cancelled(); }
            }
            token.set_error_if_cancelled();
            return info;
        }
        // Injectable read-only I/O seams keep CI independent of host storage.
        protected virtual async FileInfo read_filesystem(File root, Cancellable token) throws Error {
            return yield root.query_filesystem_info_async("filesystem::*",Priority.DEFAULT,token);
        }
        protected virtual async Variant read_objects(Cancellable token) throws Error {
                var connection = yield Bus.get(BusType.SYSTEM, token);
                if (bus == null) {
                    bus = connection;
                    subscription = bus.signal_subscribe(SERVICE, null, null, null, null, DBusSignalFlags.NONE, (c,s,p,i,n,v) => {
                        if(i=="org.freedesktop.DBus.ObjectManager")changed();
                        else if(i=="org.freedesktop.DBus.Properties"&&v.n_children()>0){string source=v.get_child_value(0).get_string();if(source==BLOCK||source==DRIVE||source==FS||source=="org.freedesktop.UDisks2.Loop")changed();}
                    });
                    owner_subscription = bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged", "/org/freedesktop/DBus", SERVICE, DBusSignalFlags.NONE, (c,s,p,i,n,v) => changed());
                }
                var reply = yield connection.call(SERVICE, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", null, new VariantType("(a{oa{sa{sv}}})"), DBusCallFlags.NO_AUTO_START, 5000, token);
            return reply.get_child_value(0);
        }
        internal static string text(Variant? properties, string key, string signature = "s") {
            var value = properties == null ? null : properties.lookup_value(key, new VariantType(signature));
            return value == null ? "" : value.get_string();
        }
        internal static string bytes(Variant? properties, string key) {
            var value = properties == null ? null : properties.lookup_value(key, new VariantType("ay"));
            if (value == null || value.n_children() > 65536) return "";
            var data = new ByteArray(); data.append(value.get_data_as_bytes().get_data()); data.append({0});
            string result = (string)data.data; return result.make_valid();
        }
        static Variant? field(Variant? properties, string key, string signature) { return properties == null ? null : properties.lookup_value(key, new VariantType(signature)); }
        // Public fixture seam: real and fake ObjectManager snapshots use the same resolver.
        public static void enrich(DeviceInfo info, Variant objects, string device, File? root = null) {
            if(info.filesystem=="btrfs")return; // A mounted subvolume can span multiple physical devices.
            Variant? selected = null; string selected_path = "";
            for (size_t i = 0; i < objects.n_children(); i++) {
                var item = objects.get_child_value(i); var interfaces = item.get_child_value(1);
                var block = interfaces.lookup_value(BLOCK, null); if (block == null) continue;
                bool match = device != "" && (bytes(block,"Device") == device || bytes(block,"PreferredDevice") == device);
                var symlinks = field(block,"Symlinks","aay");
                if (!match && device != "" && symlinks != null) for (size_t s=0;s<symlinks.n_children();s++) {
                    var data = new ByteArray(); data.append(symlinks.get_child_value(s).get_data_as_bytes().get_data()); data.append({0}); if ((string)data.data == device) match = true;
                }
                // Exact mount roots only. Never guess from a label, UUID or path prefix.
                if (!match && root != null && device == "") {
                    var fs = interfaces.lookup_value(FS,null); var points = field(fs,"MountPoints","aay");
                    if (points != null) for(size_t m=0;m<points.n_children();m++) { var data=new ByteArray();data.append(points.get_child_value(m).get_data_as_bytes().get_data());data.append({0});if(root.equal(File.new_for_path((string)data.data)))match=true; }
                }
                if (match) { if(selected != null) return; selected = interfaces; selected_path = item.get_child_value(0).get_string(); }
            }
            if (selected == null) return;
            info.block_object = selected_path;
            var block = selected.lookup_value(BLOCK,null);
            info.backing_object=text(block,"CryptoBackingDevice","o");if(info.backing_object=="/")info.backing_object="";
            if(text(block,"IdUsage")=="crypto"&&!info.mounted)info.status=_("Locked");
            info.device = bytes(block,"PreferredDevice"); info.label = text(block,"IdLabel"); info.uuid = text(block,"IdUUID");
            string fs_type = text(block,"IdType"); if(fs_type!="")info.filesystem=fs_type;
            var size = field(block,"Size","t"); if(size!=null&&size.get_uint64()>0)info.volume_size=size.get_uint64();
            var ro = field(block,"ReadOnly","b"); if(ro!=null)info.read_only=ro.get_boolean();
            var loop = selected.lookup_value("org.freedesktop.UDisks2.Loop",null);
            var partition = selected.lookup_value("org.freedesktop.UDisks2.Partition",null);
            var table_properties=selected.lookup_value("org.freedesktop.UDisks2.PartitionTable",null);
            if(partition!=null){info.partition_uuid=text(partition,"UUID");var table_object=objects.lookup_value(text(partition,"Table","o"),null);if(table_object!=null)table_properties=table_object.lookup_value("org.freedesktop.UDisks2.PartitionTable",null);}
            info.partition_scheme=text(table_properties,"Type");
            if(loop==null && partition!=null) { var table=objects.lookup_value(text(partition,"Table","o"),null); if(table!=null)loop=table.lookup_value("org.freedesktop.UDisks2.Loop",null); }
            if(loop!=null) { if(info.category!=DeviceCategory.SYSTEM_FILESYSTEM)info.category=DeviceCategory.DISK_IMAGE;info.backing_file=bytes(loop,"BackingFile");return; }
            string path=text(block,"Drive","o"); info.drive_object=path=="/"?"":path;
            var drive_interfaces = path == "" || path == "/" ? null : objects.lookup_value(path,null);
            if(drive_interfaces!=null)hardware(info,drive_interfaces.lookup_value(DRIVE,null));
        }
        static void hardware(DeviceInfo info, Variant? drive) {
            if(drive==null)return;
            info.connection=text(drive,"ConnectionBus");
            switch(info.connection){case "usb":info.connection="USB";break;case "ata":info.connection="ATA";break;case "sata":info.connection="SATA";break;case "nvme":info.connection="NVMe";break;case "scsi":info.connection="SCSI";break;}
            info.vendor=text(drive,"Vendor");info.model=text(drive,"Model");info.serial=text(drive,"Serial");info.revision=text(drive,"Revision");
            var size=field(drive,"Size","t");if(size!=null&&size.get_uint64()>0)info.physical_size=size.get_uint64();
            var detected=field(drive,"MediaChangeDetected","b");var available=field(drive,"MediaAvailable","b");if(available!=null&&detected!=null&&detected.get_boolean())info.media_presence=available.get_boolean()?MediaPresence.PRESENT:MediaPresence.ABSENT;
            info.media=text(drive,"Media");
            var optical=field(drive,"Optical","b"); bool is_optical=optical!=null&&optical.get_boolean();
            var compatibility=field(drive,"MediaCompatibility","as");bool floppy=false;
            if(compatibility!=null)info.media_compatibility=compatibility.dup_strv();
            if(compatibility!=null)foreach(string medium in compatibility.dup_strv()) { if(medium.has_prefix("optical_"))is_optical=true;if(medium.has_prefix("floppy"))floppy=true; }
            if(info.category!=DeviceCategory.SYSTEM_FILESYSTEM) {
                if(is_optical) info.category=DeviceCategory.OPTICAL_DRIVE;
                else if(floppy) info.category=DeviceCategory.FLOPPY_DRIVE;
                else { var removable=field(drive,"Removable","b");info.category=(removable!=null&&removable.get_boolean())||info.connection=="USB"?DeviceCategory.REMOVABLE_VOLUME:DeviceCategory.INTERNAL_VOLUME; }
            }
            var rotation=field(drive,"RotationRate","i");if(rotation!=null&&!is_optical&&!floppy) { int rate=rotation.get_int32();if(rate==0)info.hardware_type=_("Solid state storage");else if(rate!=0)info.hardware_type=_("Hard disk drive"); }
            var media_removable=field(drive,"MediaRemovable","b");
            if(!is_optical&&!floppy&&(media_removable==null||!media_removable.get_boolean()))info.media_presence=MediaPresence.UNKNOWN;
            if(is_optical||floppy||(media_removable!=null&&media_removable.get_boolean())) {if(info.media_presence==MediaPresence.PRESENT)info.media_size=info.physical_size;info.physical_size=null;}
            var blank=field(drive,"OpticalBlank","b");if(optical!=null&&optical.get_boolean()&&blank!=null)info.blank=blank.get_boolean();
            var audio=field(drive,"OpticalNumAudioTracks","u");if(optical!=null&&optical.get_boolean()&&audio!=null)info.audio_tracks=audio.get_uint32();
            var data=field(drive,"OpticalNumDataTracks","u");if(optical!=null&&optical.get_boolean()&&data!=null)info.data_tracks=data.get_uint32();
        }
        async void tape_info(DeviceInfo info, Place place, Cancellable token) throws Error {
            info.category=DeviceCategory.TAPE_DRIVE;info.device=place.file.get_path()??"";info.identity=place.tape_sysfs;info.status=_("Unavailable");
            try {
                var directory=File.new_for_path(place.tape_sysfs);
                var node=yield directory.query_info_async("standard::type,unix::inode",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.DEFAULT,token);
                if(place.tape_inode!=null&&(node.get_attribute_type("unix::inode")!=FileAttributeType.UINT64||node.get_attribute_uint64("unix::inode")!=place.tape_inode)){info.connected=false;info.status=_("Disconnected");return;}
                if(place.tape_inode!=null)info.identity+="/"+place.tape_inode.to_string();
                info.connection="SCSI";
                uint8[] contents;string? etag;
                yield directory.get_child("device/vendor").load_contents_async(token,out contents,out etag);info.vendor=((string)contents).strip();
                yield directory.get_child("device/model").load_contents_async(token,out contents,out etag);info.model=((string)contents).strip();
            } catch(Error e) { token.set_error_if_cancelled();if(!FileUtils.test(place.tape_sysfs,FileTest.EXISTS)){info.connected=false;info.status=_("Disconnected");} }
        }
        protected override void dispose() { if(bus!=null) {if(subscription!=0)bus.signal_unsubscribe(subscription);if(owner_subscription!=0)bus.signal_unsubscribe(owner_subscription);}subscription=0;owner_subscription=0;base.dispose(); }
    }
}
