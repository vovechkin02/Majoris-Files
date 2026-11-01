namespace MajorisFiles {
    public class DirectoryModel : Object {
        public GLib.ListStore items = new GLib.ListStore(typeof(FileItem));
        public File location {
            get;
            private set;
            default = File.new_for_path(Environment.get_home_dir());
        }
        public bool writable { get; private set; default = false; }
        public bool loading {
            get;
            private set;
        }
        public signal void failed(string message);
        public signal void loaded();
        signal void settled();
        public signal void resetting(File target);
        Cancellable pending = new Cancellable();
        FileMonitor? monitor;
        uint reload_source;
        uint generation;
        public void cancel()
        {
            generation++;
            pending.cancel();
            loading = false;
            settled();
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
        // Query the actual created object, then merge by GFile identity. Enumeration
        // and monitor delivery may have happened on either side of the operation.
        public async void reconcile_created(File file) throws Error {
            while (loading) {
                ulong handler = settled.connect(() => reconcile_created.callback());
                yield;
                disconnect(handler);
            }
            uint epoch = generation;
            var parent = file.get_parent();
            if (parent == null || !parent.equal(location)) return;
            var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            if (!parent.equal(location)) return;
            if (epoch != generation) { yield reconcile_created(file); return; }
            for (uint i = 0; i < items.get_n_items(); i++)
                if (((FileItem)items.get_item(i)).file.equal(file)) return;
            items.append(new FileItem(file, info));
        }
        public async void open(File folder, Gtk.Window? parent = null)
        {
            resetting(folder);
            cancel();
            pending = new Cancellable();
            var token = pending;
            uint epoch = ++generation;
            location = folder;
            loading = true; writable = false;
            items.remove_all();
            FileEnumerator? enumerator = null;
            try {
                try {
                    enumerator = yield folder.enumerate_children_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                }
                catch (IOError.NOT_MOUNTED e) {
                    yield folder.mount_enclosing_volume(MountMountFlags.NONE, new Gtk.MountOperation(parent), token);
                    enumerator = yield folder.enumerate_children_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                }
                try {
                    var folder_info = yield folder.query_info_async("access::can-write", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
                    if (epoch != generation || token.is_cancelled()) return;
                    writable = !folder_info.has_attribute("access::can-write") || folder_info.get_attribute_boolean("access::can-write");
                } catch (IOError.CANCELLED e) { return; } catch (Error e) { writable = false; }
                while (!token.is_cancelled())
                {
                    var batch = yield enumerator.next_files_async(128, Priority.DEFAULT, token);
                    if (epoch != generation || batch == null)
                        break;
                    var additions = new Gee.ArrayList<Object>();
                    foreach (var info in batch)
                    {
                        var item = new FileItem(folder.get_child(info.get_name()), info);
                        if(Paths.is_symlink(info))
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
                        additions.add(item);
                    }
                    if (epoch == generation && !token.is_cancelled() && additions.size > 0)
                        items.splice(items.get_n_items(), 0, additions.to_array());
                }
                yield enumerator.close_async(Priority.DEFAULT, null);
                enumerator = null;
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
                if(enumerator != null)
                {
                    try {
                        yield enumerator.close_async(Priority.DEFAULT, null);
                    }
                    catch(Error ignored) {}
                }
                if (!token.is_cancelled() && epoch == generation)
                    failed(e.message);
            }
            if (epoch == generation)
            {
                loading = false;
                loaded();
                settled();
            }
        }
        ~DirectoryModel()
        {
            cancel();
        }
    }
}
