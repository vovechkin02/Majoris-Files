namespace MajorisFiles {
    public enum MediaFamily { UNKNOWN, THUMB, CARD, FLOPPY, CARTRIDGE, OPTICAL }
    public delegate bool MediaIconAvailable(string name);

    public class MediaDescriptor : Object {
        public string identifier;
        public MediaFamily family;
        public string description;
        public string reader;
        public bool capability;
        public bool recognised;
        public MediaDescriptor(string identifier, MediaFamily family, string description, string reader = "", bool capability = false, bool recognised = true) {
            this.identifier=identifier;this.family=family;this.description=description;this.reader=reader;this.capability=capability;this.recognised=recognised;
        }
    }
    // The only UDisks media vocabulary. Raw identifiers remain in DeviceInfo;
    // descriptions, family policy and icon preferences are separate operations.
    public class MediaIdentity : Object {
        public MediaDescriptor current;
        public MediaDescriptor[] compatible = {};
        public MediaPresence presence;
        public bool? removable;
        public MediaFamily family;
        public MediaIdentity(string media, string[] compatibility, MediaPresence presence, bool? removable) {
            current=describe(media);this.presence=presence;this.removable=removable;
            MediaDescriptor[] descriptors={};foreach(var raw in compatibility)descriptors+=describe(raw);compatible=descriptors;
            family=current.identifier==""?MediaFamily.UNKNOWN:current.family;
            if(family==MediaFamily.UNKNOWN)foreach(var item in compatible)if(priority(item.family)>priority(family))family=item.family;
        }
        static int priority(MediaFamily family) {
            switch(family){case MediaFamily.OPTICAL:return 5;case MediaFamily.CARTRIDGE:return 4;case MediaFamily.FLOPPY:return 3;case MediaFamily.CARD:return 2;case MediaFamily.THUMB:return 1;default:return 0;}
        }
        public static string[] identifiers() { return {"thumb","flash","flash_cf","flash_ms","flash_sm","flash_sd","flash_sdhc","flash_sdxc","flash_sdio","flash_sd_combo","flash_mmc","floppy","floppy_zip","floppy_jaz","optical","optical_cd","optical_cd_r","optical_cd_rw","optical_dvd","optical_dvd_r","optical_dvd_rw","optical_dvd_ram","optical_dvd_plus_r","optical_dvd_plus_rw","optical_dvd_plus_r_dl","optical_dvd_plus_rw_dl","optical_bd","optical_bd_r","optical_bd_re","optical_hddvd","optical_hddvd_r","optical_hddvd_rw","optical_mo","optical_mrw","optical_mrw_w"}; }
        public static MediaDescriptor describe(string identifier) {
            switch(identifier) {
            case "thumb": return new MediaDescriptor(identifier,MediaFamily.THUMB,_("USB flash drive"),"");
            case "flash": return new MediaDescriptor(identifier,MediaFamily.CARD,_("Flash memory card"),_("Memory card reader"));
            case "flash_cf": return new MediaDescriptor(identifier,MediaFamily.CARD,_("CompactFlash"),_("CompactFlash card reader"));
            case "flash_ms": return new MediaDescriptor(identifier,MediaFamily.CARD,_("Memory Stick"),_("Memory Stick reader"));
            case "flash_sm": return new MediaDescriptor(identifier,MediaFamily.CARD,_("SmartMedia"),_("SmartMedia reader"));
            case "flash_sd": return new MediaDescriptor(identifier,MediaFamily.CARD,_("SD card"),_("SD card reader"));
            case "flash_sdhc": return new MediaDescriptor(identifier,MediaFamily.CARD,_("SDHC card"),_("SDHC card reader"));
            case "flash_sdxc": return new MediaDescriptor(identifier,MediaFamily.CARD,_("SDXC card"),_("SDXC card reader"));
            case "flash_sdio": return new MediaDescriptor(identifier,MediaFamily.CARD,_("SDIO"),_("SDIO reader"));
            case "flash_sd_combo": return new MediaDescriptor(identifier,MediaFamily.CARD,_("SDIO combination card"),_("SDIO combination card reader"));
            case "flash_mmc": return new MediaDescriptor(identifier,MediaFamily.CARD,_("MultiMediaCard"),_("MMC card reader"));
            case "floppy": return new MediaDescriptor(identifier,MediaFamily.FLOPPY,_("Floppy disk"),_("Floppy disk drive"));
            case "floppy_zip": return new MediaDescriptor(identifier,MediaFamily.CARTRIDGE,_("Zip disk"),_("Zip drive"));
            case "floppy_jaz": return new MediaDescriptor(identifier,MediaFamily.CARTRIDGE,_("Jaz disk"),_("Jaz drive"));
            case "optical": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("Optical disc"),_("Optical disc drive"));
            case "optical_cd": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("CD"),_("Optical disc drive"));
            case "optical_cd_r": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("CD-R"),_("Optical disc drive"));
            case "optical_cd_rw": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("CD-RW"),_("Optical disc drive"));
            case "optical_dvd": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD"),_("Optical disc drive"));
            case "optical_dvd_r": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD-R"),_("Optical disc drive"));
            case "optical_dvd_rw": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD-RW"),_("Optical disc drive"));
            case "optical_dvd_ram": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD-RAM"),_("Optical disc drive"));
            case "optical_dvd_plus_r": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD+R"),_("Optical disc drive"));
            case "optical_dvd_plus_rw": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD+RW"),_("Optical disc drive"));
            case "optical_dvd_plus_r_dl": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD+R DL"),_("Optical disc drive"));
            case "optical_dvd_plus_rw_dl": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("DVD+RW DL"),_("Optical disc drive"));
            case "optical_bd": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("Blu-ray Disc"),_("Optical disc drive"));
            case "optical_bd_r": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("BD-R"),_("Optical disc drive"));
            case "optical_bd_re": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("BD-RE"),_("Optical disc drive"));
            case "optical_hddvd": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("HD DVD"),_("Optical disc drive"));
            case "optical_hddvd_r": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("HD DVD-R"),_("Optical disc drive"));
            case "optical_hddvd_rw": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("HD DVD-RW"),_("Optical disc drive"));
            case "optical_mo": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("Magneto-optical disc"),_("Optical disc drive"));
            case "optical_mrw": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("Mount Rainier compatibility"),_("Optical disc drive"),true);
            case "optical_mrw_w": return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("Mount Rainier writing capability"),_("Optical disc drive"),true);
            default:
                if(identifier=="")return new MediaDescriptor(identifier,MediaFamily.UNKNOWN,"","",false,false);
                if(identifier.has_prefix("flash_"))return new MediaDescriptor(identifier,MediaFamily.CARD,_("Flash memory card"),_("Memory card reader"),false,false);
                if(identifier.has_prefix("optical_"))return new MediaDescriptor(identifier,MediaFamily.OPTICAL,_("Optical disc"),_("Optical disc drive"),false,false);
                return new MediaDescriptor(identifier,MediaFamily.UNKNOWN,_("Unknown media"),"",false,false);
            }
        }
        public DeviceCategory classify(DeviceCategory fallback, bool optical = false) {
            switch(fallback){case DeviceCategory.SYSTEM_FILESYSTEM:case DeviceCategory.TAPE_DRIVE:case DeviceCategory.DISK_IMAGE:case DeviceCategory.PORTABLE_DEVICE:return fallback;default:break;}
            if(optical||fallback==DeviceCategory.OPTICAL_DRIVE||family==MediaFamily.OPTICAL)return DeviceCategory.OPTICAL_DRIVE;
            switch(family){
            case MediaFamily.CARTRIDGE:return DeviceCategory.REMOVABLE_CARTRIDGE;
            case MediaFamily.FLOPPY:return DeviceCategory.FLOPPY_DRIVE;
            case MediaFamily.CARD:if(removable==true)return DeviceCategory.MEMORY_CARD;break;
            case MediaFamily.THUMB:return DeviceCategory.REMOVABLE_VOLUME;
            default:break;
            }
            return fallback;
        }
        public string inserted_description() { return presence==MediaPresence.ABSENT||current.capability?"":current.description; }
        public string supported_description() {
            var names=new Gee.ArrayList<string>();foreach(var item in compatible)if(!names.contains(item.description)&&item.description!="")names.add(item.description);
            if(current.capability&&!names.contains(current.description))names.add(current.description);
            return string.joinv(", ",names.to_array());
        }
        public string reader_description(string fallback) {
            // Several compatible formats describe a reader, never its contents.
            if(current.identifier!=""&&!current.capability&&presence!=MediaPresence.ABSENT)return fallback;
            string name="";int count=0;var seen=new Gee.HashSet<string>();
            foreach(var item in compatible)if(item.family==family&&!item.capability&&seen.add(item.identifier)){name=item.reader;count++;}
            if(count==1&&name!="")return name;
            if(family==MediaFamily.CARD)return _("Memory card reader");
            if(family==MediaFamily.CARTRIDGE)return _("Removable cartridge drive");
            return fallback;
        }
        public string presence_description(DeviceCategory category) {
            switch(presence){
            case MediaPresence.PRESENT:return _("Media inserted");
            case MediaPresence.ABSENT:return category==DeviceCategory.MEMORY_CARD?_("No card inserted"):_("No media inserted");
            default:return _("Unknown");
            }
        }
        public string[] icon_names(DeviceCategory category) {
            switch(category){
            case DeviceCategory.MEMORY_CARD:return {"media-flash-symbolic","drive-removable-media-symbolic","drive-harddisk-symbolic"};
            case DeviceCategory.REMOVABLE_CARTRIDGE:return {"drive-removable-media-symbolic","media-removable-symbolic","drive-harddisk-symbolic"};
            case DeviceCategory.FLOPPY_DRIVE:return {"media-floppy-symbolic","drive-removable-media-symbolic","drive-harddisk-symbolic"};
            case DeviceCategory.OPTICAL_DRIVE:return {"drive-optical-symbolic","media-optical-symbolic","drive-harddisk-symbolic"};
            case DeviceCategory.REMOVABLE_VOLUME:return {"drive-removable-media-symbolic","drive-harddisk-symbolic"};
            case DeviceCategory.GENERIC_STORAGE:return {"drive-harddisk-symbolic"};
            default:return {};
            }
        }
        public Icon select_icon(DeviceCategory category, Icon? supplied, MediaIconAvailable available) {
            if(category==DeviceCategory.REMOVABLE_VOLUME&&family!=MediaFamily.THUMB&&supplied!=null){
                var existing=supplied as ThemedIcon;if(existing==null)return supplied;
                foreach(var name in existing.get_names())if(available(name)&&!name.has_prefix("folder"))return supplied;
            }
            var choices=icon_names(category);if(choices.length==0)return supplied??new ThemedIcon("drive-harddisk-symbolic");
            var themed=supplied as ThemedIcon;
            if(supplied!=null&&themed==null)return supplied;
            if(themed!=null)foreach(var name in themed.get_names()) {
                if(!available(name))continue;
                string base_name=name.has_suffix("-symbolic")?name.substring(0,name.length-9):name;
                bool generic=base_name=="folder"||base_name=="drive"||base_name=="media-removable"||base_name.has_prefix("drive-harddisk")||base_name.has_prefix("drive-removable-media");
                bool wrong_family=(name.has_prefix("media-floppy")&&category!=DeviceCategory.FLOPPY_DRIVE)||(name.has_prefix("media-flash")&&category!=DeviceCategory.MEMORY_CARD)||((name.has_prefix("media-optical")||name.has_prefix("drive-optical"))&&category!=DeviceCategory.OPTICAL_DRIVE);
                if(!generic&&!wrong_family)return supplied;
            }
            foreach(var name in choices)if(available(name))return new ThemedIcon(name);
            return supplied??new ThemedIcon("drive-harddisk-symbolic");
        }
    }
}
