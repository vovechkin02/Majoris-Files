namespace MajorisFiles {
    public enum DeviceCategory { SYSTEM_FILESYSTEM, INTERNAL_VOLUME, REMOVABLE_VOLUME, OPTICAL_DRIVE, FLOPPY_DRIVE, TAPE_DRIVE, DISK_IMAGE, PORTABLE_DEVICE, GENERIC_STORAGE }
    public enum MediaPresence { UNKNOWN, ABSENT, PRESENT }

    // Nullable measurements preserve real zeroes. Filesystem and hardware sizes
    // deliberately live in separate fields, including for unmounted partitions.
    public class DeviceInfo : Object {
        public DeviceCategory category = DeviceCategory.GENERIC_STORAGE;
        public string identity = "";
        public string name = "";
        public string status = "";
        public bool connected = true;
        public bool mounted;
        public MediaPresence media_presence = MediaPresence.UNKNOWN;
        public string filesystem = "";
        public string mount_point = "";
        public string label = "";
        public string uuid = "";
        public string device = "";
        public string connection = "";
        public string vendor = "";
        public string model = "";
        public string serial = "";
        public string revision = "";
        public string partition_uuid = "";
        public string partition_scheme = "";
        public string[] media_compatibility = {};
        public string media = "";
        public string backing_object = "";
        public string backing_file = "";
        public string hardware_type = "";
        public string block_object = "";
        public string drive_object = "";
        public bool? read_only;
        public bool? blank;
        public uint? audio_tracks;
        public uint? data_tracks;
        public uint64? capacity;
        public uint64? used;
        public uint64? available;
        public uint64? volume_size;
        public uint64? physical_size;
        public uint64? media_size;
        public bool used_estimated;

        public bool optical { get { return category == DeviceCategory.OPTICAL_DRIVE; } }
        public bool usage_allowed { get { return mounted && !optical && category != DeviceCategory.TAPE_DRIVE && category != DeviceCategory.PORTABLE_DEVICE; } }
        public bool show_usage { get { return usage_allowed && capacity != null && capacity > 0 && used != null && used <= capacity && (available == null || available <= capacity - used); } }
        public void filesystem_info(FileInfo info) {
            used_estimated = false;
            capacity = number(info, "filesystem::size"); used = number(info, "filesystem::used"); available = number(info, "filesystem::free");
            if (used == null && capacity != null && available != null && available <= capacity) { used = capacity - available; used_estimated = true; }
            if (info.get_attribute_type("filesystem::type") == FileAttributeType.STRING) filesystem = info.get_attribute_string("filesystem::type");
            if (info.get_attribute_type("filesystem::readonly") == FileAttributeType.BOOLEAN) read_only = info.get_attribute_boolean("filesystem::readonly");
        }
        static uint64? number(FileInfo info, string key) { if (info.get_attribute_type(key) == FileAttributeType.UINT64) return info.get_attribute_uint64(key); return null; }
        public string type_name() {
            switch(category) {
            case DeviceCategory.SYSTEM_FILESYSTEM: return _("System filesystem");
            case DeviceCategory.INTERNAL_VOLUME: return _("Internal storage");
            case DeviceCategory.REMOVABLE_VOLUME: return _("Removable storage");
            case DeviceCategory.OPTICAL_DRIVE: return _("Optical disc drive");
            case DeviceCategory.FLOPPY_DRIVE: return _("Floppy disk drive");
            case DeviceCategory.TAPE_DRIVE: return _("Magnetic tape drive");
            case DeviceCategory.DISK_IMAGE: return _("Mounted disk image");
            case DeviceCategory.PORTABLE_DEVICE: return _("Portable device");
            default: return _("Storage device");
            }
        }
        public bool has_hardware { get { return device != "" || model != "" || connection != "" || backing_file != "" || uuid != "" || block_object != ""; } }
    }
    public interface DeviceInformationProvider : Object {
        public abstract async DeviceInfo query(Place place, Cancellable token) throws Error;
        public signal void changed();
    }
}
