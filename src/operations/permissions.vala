namespace MajorisFiles {
    public class PermissionService : Object {
        public static uint mode(string text) throws Error
        {
            uint64 value = 0;
            if(!Regex.match_simple("^[0-7]{3,4}$", text) || !uint64.try_parse(text, out value, null, 8) || value > 07777)
                throw new FileError.INVALID("Permissions must be between 0000 and 7777");
            return (uint)value;
        }
        public static async void apply(Gee.List<File> roots, uint file_mode, uint folder_mode, bool recursive, uint? uid, uint? gid, Cancellable token, uint file_mask = 0777, uint folder_mask = 0777) throws Error
        {
            if(file_mode > 07777 || folder_mode > 07777 || file_mask > 07777 || folder_mask > 07777)
                throw new FileError.INVALID("Unsupported permission bits");
            var queue = new Gee.ArrayQueue<File>();
            var directories = new Gee.ArrayList<File>();
            var visited = new Gee.HashSet<string>();
            foreach(var root in roots)
                queue.offer(root);
            while(!queue.is_empty)
            {
                token.set_error_if_cancelled();
                var file = queue.poll();
                if(!visited.add(file.get_uri()))
                    continue;
                if(!file.is_native())
                    throw new FileError.UNSUPPORTED("POSIX permissions require local storage");
                var info = yield file.query_info_async("standard::type,standard::is-symlink,unix::mode", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                if(Paths.is_symlink(info))
                    continue;
                if(!info.has_attribute("unix::mode"))
                    throw new FileError.UNSUPPORTED("This filesystem does not expose POSIX permissions");
                if(info.get_file_type() == FileType.DIRECTORY)
                {
                    directories.add(file);
                    if(recursive)
                    {
                        var en = yield file.enumerate_children_async("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                        try {
                            while(true)
                            {
                                var batch = yield en.next_files_async(128, Priority.LOW, token);
                                if(batch == null)
                                    break;
                                foreach(var child in batch)
                                    queue.offer(file.get_child(child.get_name()));
                            }
                        }
                        catch(Error e) {
                            try {
                                yield en.close_async(Priority.LOW, null);
                            }
                            catch(Error ignored) {}
                            throw e;
                        }
                        yield en.close_async(Priority.LOW, null);
                    }
                }
                else yield set_permissions(file, file_mode, file_mask, uid, gid, token);
            }
            // Apply directory modes after descendants so removing traversal access
            // does not prevent completing the requested recursive operation.
            for(int i = directories.size - 1; i >= 0; i--)
                yield set_permissions(directories[i], folder_mode, folder_mask, uid, gid, token);
        }
        static async void set_permissions(File file, uint mode, uint mask, uint? uid, uint? gid, Cancellable token) throws Error
        {
            var info = new FileInfo();
            if (mask != 0) {
                var original = yield file.query_info_async("unix::mode", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                info.set_attribute_uint32("unix::mode", (original.get_attribute_uint32("unix::mode") & 07777 & ~mask) | (mode & mask));
            }
            if(uid != null)
                info.set_attribute_uint32("unix::uid", uid);
            if(gid != null)
                info.set_attribute_uint32("unix::gid", gid);
            yield file.set_attributes_async(info, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token, null);
        }
        public static async string read_acl(File file) throws Error
        {
            if(!file.is_native() || Environment.find_program_in_path("getfacl") == null)
                throw new FileError.UNSUPPORTED("ACL editing requires local storage and the acl utilities");
            var info = yield file.query_info_async("standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
            if(Paths.is_symlink(info))
                throw new FileError.UNSUPPORTED("ACL editing does not follow symbolic links");
            var process = new Subprocess.newv({"getfacl", "--omit-header", "--absolute-names", "--", file.get_path()}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string output, errors;
            yield process.communicate_utf8_async(null, null, out output, out errors);
            if(!process.get_successful())
                throw new FileError.INVALID(errors);
            if(output.length > 128 * 1024)
                throw new FileError.INVALID("The ACL is too large to edit");
            return output;
        }
        public static async void write_acl(File file, string acl) throws Error
        {
            if(!file.is_native() || Environment.find_program_in_path("setfacl") == null)
                throw new FileError.UNSUPPORTED("ACL editing requires local storage and the acl utilities");
            if(acl.length > 128 * 1024)
                throw new FileError.INVALID("The ACL is too large");
            var info = yield file.query_info_async("standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
            if(Paths.is_symlink(info))
                throw new FileError.UNSUPPORTED("ACL editing does not follow symbolic links");
            foreach(var line in acl.split("\n"))
                if(line.strip() != "" && !line.has_prefix("#") && !Regex.match_simple("^(default:)?(user|group|mask|other):[a-zA-Z0-9_.-]*:[r-][w-][x-]([ \\t]+#effective:[r-][w-][x-])?$", line))
                    throw new FileError.INVALID("Invalid ACL entry");
            var process = new Subprocess.newv({"setfacl", "--set-file=-", "--", file.get_path()}, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string output, errors;
            yield process.communicate_utf8_async(acl, null, out output, out errors);
            if(!process.get_successful())
                throw new FileError.INVALID(errors);
        }
    }
}
