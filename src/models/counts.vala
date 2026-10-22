namespace MajorisFiles {
    public class FileCounts : Object {
        public uint64 files;
        public uint64 folders;
        public uint64 bytes;
        public uint64 allocated;
        public uint64 unreadable;
        public signal void updated();
        public async void scan(Gee.List<File> roots, Cancellable token) throws Error
        {
            var queue = new Gee.ArrayQueue<File>();
            foreach(var root in roots)
                queue.offer(root);
            var visited = new Gee.HashSet<string>();
            while(!queue.is_empty)
            {
                token.set_error_if_cancelled();
                var file = queue.poll();
                if(!visited.add(file.get_uri()))
                    continue;
                try {
                    var info = yield file.query_info_async("standard::type,standard::is-symlink,standard::size,standard::allocated-size", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                    if(info.get_file_type() == FileType.DIRECTORY && !Paths.is_symlink(info))
                    {
                        folders++;
                        var enumerator = yield file.enumerate_children_async("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                        try {
                            while(true)
                            {
                                var batch = yield enumerator.next_files_async(128, Priority.LOW, token);
                                if(batch == null)
                                    break;
                                foreach(var child in batch)
                                    queue.offer(file.get_child(child.get_name()));
                            }
                        }
                        catch(Error e) {
                            try {
                                yield enumerator.close_async(Priority.LOW, null);
                            }
                            catch(Error ignored) {}
                            throw e;
                        }
                        yield enumerator.close_async(Priority.LOW, null);
                    }
                    else {
                        files++;
                        bytes += info.get_size();
                        allocated += info.has_attribute("standard::allocated-size") ? info.get_attribute_uint64("standard::allocated-size") : info.get_size();
                    }
                }
                catch(IOError.CANCELLED e) {
                    throw e;
                }
                catch(Error e) {
                    unreadable++;
                }
                updated();
            }
        }
    }
}
