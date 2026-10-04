namespace MajorisFiles {
    public class DirectoryModel : Object {
        public GLib.ListStore items = new GLib.ListStore(typeof(FileItem));
        public File location {
            get;
            private set;
            default = File.new_for_path(Environment.get_home_dir());
        }
        public bool loading {
            get;
            private set;
        }
        public signal void failed(string message);
        public signal void loaded();
        public signal void resetting(File target);
        Cancellable pending = new Cancellable();
        FileMonitor? monitor;
        uint reload_source;
        uint generation;
        public void cancel()
        {
            pending.cancel();
            if (monitor != null)
                monitor.cancel();
            if (reload_source != 0)
            {
                Source.remove(reload_source);
                reload_source = 0;
            }
        }
        public void virtual_location(File file)
        {
            cancel();
            generation++;
            location = file;
            items.remove_all();
        }
        public async void open(File folder, Gtk.Window? parent = null)
        {
            resetting(folder);
            cancel();
            pending = new Cancellable();
            var token = pending;
            uint epoch = ++generation;
            location = folder;
            loading = true;
            items.remove_all();
            try {
                FileEnumerator enumerator;
                try {
                    enumerator = yield folder.enumerate_children_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                }
                catch (IOError.NOT_MOUNTED e) {
                    yield folder.mount_enclosing_volume(MountMountFlags.NONE, new Gtk.MountOperation(parent), token);
                    enumerator = yield folder.enumerate_children_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                }
                while (!token.is_cancelled())
                {
                    var batch = yield enumerator.next_files_async(128, Priority.DEFAULT, token);
                    if (epoch != generation || batch == null)
                        break;
                    foreach (var info in batch)
                    {
                        var item = new FileItem(folder.get_child(info.get_name()), info);
                        if(info.get_is_symlink())
                        {
                            try {
                                var target = yield item.file.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                                item.resolved_directory = target.get_file_type() == FileType.DIRECTORY;
                            }
                            catch(IOError.CANCELLED e) {
                                throw e;
                            }
                            catch(Error e) {}
                        }
                        if(epoch != generation || token.is_cancelled())
                            break;
                        items.append(item);
                    }
                }
                yield enumerator.close_async(Priority.DEFAULT, null);
                if (epoch != generation)
                    return;
                monitor = folder.monitor_directory(FileMonitorFlags.WATCH_MOVES, token);
                monitor.changed.connect(() => {
                    if (reload_source != 0)
                        Source.remove(reload_source);
                    reload_source = Timeout.add(180, () => { reload_source = 0;
                                                             open.begin(location, parent);
                                                             return Source.REMOVE;
                        });
                });
            }
            catch (Error e) {
                if (!token.is_cancelled() && epoch == generation)
                    failed(e.message);
            }
            if (epoch == generation)
            {
                loading = false;
                loaded();
            }
        }
        ~DirectoryModel()
        {
            cancel();
        }
    }
}
