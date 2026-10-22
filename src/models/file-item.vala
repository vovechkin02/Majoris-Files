namespace MajorisFiles {
    public class FileItem : Object {
        public File file {
            get;
            construct;
        }
        public FileInfo info {
            get;
            construct;
        }
        public string name {
            owned get {
                return info.get_display_name();
            }
        }
        public bool directory {
            get {
                return info.get_file_type() == FileType.DIRECTORY || resolved_directory;
            }
        }
        public bool resolved_directory;
        public bool hidden {get{return Paths.is_hidden(info);}}
        public double relevance;
        public bool navigable {
            get {
                return directory || info.get_file_type() == FileType.SHORTCUT || info.get_file_type() == FileType.MOUNTABLE;
            }
        }
        public uint64 bytes {
            get {
                var cloud = CloudFiles.get_default().cached(file);
                if (cloud != null && cloud.online_only && cloud.size_known) return cloud.size;
                return info.has_attribute("standard::size")?info.get_size():0;
            }
        }
        public string mime {
            owned get {
                var cloud = CloudFiles.get_default().cached(file);
                if (cloud != null && cloud.online_only && cloud.mime != "") return cloud.mime;
                return info.get_content_type() ?? "application/octet-stream";
            }
        }
        public FileItem(File file, FileInfo info)
        {
            Object(file: file, info: info);
        }
        public const string ATTRIBUTES = "standard::*,time::*,access::*,unix::*,owner::*,id::*,trash::*,thumbnail::*,selinux::context";
    }
}
