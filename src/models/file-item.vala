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
        public double relevance;
        public bool navigable {
            get {
                return directory || info.get_file_type() == FileType.SHORTCUT || info.get_file_type() == FileType.MOUNTABLE;
            }
        }
        public uint64 bytes {
            get {
                return info.get_size();
            }
        }
        public string mime {
            owned get {
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
