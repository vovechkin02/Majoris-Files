namespace MajorisFiles {
    public class DropPolicy : Object {
        public static async bool same_filesystem(Gee.List<File> sources, File destination)
        {
            if(sources.size == 0 || !destination.is_native())
                return false;
            var token = new Cancellable();
            uint timeout = Timeout.add_seconds(3, () => { token.cancel();
                                                          return Source.REMOVE;
                });
            try {
                var target = yield destination.query_info_async("id::filesystem", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                var identity = target.get_attribute_string("id::filesystem");
                if(identity == null || identity == "")
                    return false;
                foreach(var source in sources)
                {
                    if(!source.is_native())
                        return false;
                    // Moving a symlink moves the link, not its target filesystem.
                    var info = yield source.query_info_async("id::filesystem", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                    if(info.get_attribute_string("id::filesystem") != identity)
                        return false;
                }
                return true;
            }
            catch(Error e) {
                return false;
            }
            finally {
                if(!token.is_cancelled())
                    Source.remove(timeout);
            }
        }
    }
}
