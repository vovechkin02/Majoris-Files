namespace MajorisFiles {
    public class DiskImages : Object {
        const string SERVICE = "org.freedesktop.UDisks2";
        const string ROOT = "/org/freedesktop/UDisks2";
        const string LOOP = "org.freedesktop.UDisks2.Loop";
        const string FILESYSTEM = "org.freedesktop.UDisks2.Filesystem";
        static Variant options(bool read_only = false)
        {
            var result = new VariantBuilder(VariantType.VARDICT);
            if(read_only)
                result.add("{sv}", "read-only", new Variant.boolean(true));
            return result.end();
        }
        static async Variant inventory(DBusConnection bus) throws Error
        {
            var response = yield bus.call(SERVICE, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", null, new VariantType("(a{oa{sa{sv}}})"), DBusCallFlags.NONE, 30000, null);
            return response.get_child_value(0);
        }
        public static Gee.ArrayList<string> filesystems(Variant objects, string loop)
        {
            var result = new Gee.ArrayList<string>();
            for(size_t i = 0; i < objects.n_children(); i++)
            {
                var entry = objects.get_child_value(i);
                string path = entry.get_child_value(0).get_string();
                var interfaces = entry.get_child_value(1);
                var partition = interfaces.lookup_value("org.freedesktop.UDisks2.Partition", null);
                var table = partition == null ? null : partition.lookup_value("Table", new VariantType("o"));
                if((path == loop || (table != null && table.get_string() == loop)) && interfaces.lookup_value(FILESYSTEM, null) != null)
                    result.add(path);
            }
            result.sort((a, b) => strcmp(a, b));
            return result;
        }
        public static string? find_loop(Variant objects, File image)
        {
            for(size_t i = 0; i < objects.n_children(); i++)
            {
                var entry = objects.get_child_value(i);
                var properties = entry.get_child_value(1).lookup_value(LOOP, null);
                if(properties == null)
                    continue;
                var backing = properties.lookup_value("BackingFile", new VariantType("ay"));
                if(backing == null || backing.n_children() > 65536)
                    continue;
                var bytes = new ByteArray();
                var storage = backing.get_data_as_bytes();
                bytes.append(storage.get_data());
                bytes.append({0});
                string path = (string)bytes.data;
                if(path != "" && Path.is_absolute(path) && File.new_for_path(path).equal(image))
                    return entry.get_child_value(0).get_string();
            }
            return null;
        }
        public async Gee.ArrayList<File> mount(File image) throws Error
        {
            if(!image.is_native())
                throw new FileError.UNSUPPORTED("Disk images must be local files");
            var info = yield image.query_info_async("standard::type,standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
            if(info.get_file_type() != FileType.REGULAR || Paths.is_symlink(info))
                throw new FileError.INVALID("Select a regular disk-image file");
            var bus = yield Bus.get(BusType.SYSTEM);
            var objects = yield inventory(bus);
            string? loop = find_loop(objects, image);
            bool created = loop == null;
            if(!created)
            {
                var block = objects.lookup_value(loop, null).lookup_value("org.freedesktop.UDisks2.Block", null);
                var read_only = block == null ? null : block.lookup_value("ReadOnly", VariantType.BOOLEAN);
                if(read_only == null || !read_only.get_boolean())
                    throw new FileError.CONFLICT("This image is already attached with write access. Unmount it before mounting it read only.");
            }
            if(created)
            {
                var input = yield image.read_async(Priority.DEFAULT, null);
                try {
                    var descriptors = new UnixFDList();
                    int handle = descriptors.append(((FileDescriptorBased)input).get_fd());
                    var response = yield bus.call_with_unix_fd_list(SERVICE, ROOT + "/Manager", "org.freedesktop.UDisks2.Manager", "LoopSetup", new Variant("(h@a{sv})", handle, options(true)), new VariantType("(o)"), DBusCallFlags.NONE, 30000, descriptors, null);
                    loop = response.get_child_value(0).get_string();
                }
                catch(Error e) {
                    try {
                        yield input.close_async(Priority.DEFAULT, null);
                    }
                    catch(Error ignored) {}
                    throw e;
                }
                try {
                    yield input.close_async(Priority.DEFAULT, null);
                }
                catch(Error ignored) {}
            }
            var mounted = new Gee.ArrayList<string>();
            var locations = new Gee.ArrayList<File>();
            try {
                Gee.ArrayList<string> devices = new Gee.ArrayList<string>();
                for(int attempt = 0; attempt < 30; attempt++)
                {
                    objects = yield inventory(bus);
                    devices = filesystems(objects, loop);
                    if(devices.size > 0)
                        break;
                    Timeout.add(100, () => { mount.callback();
                                             return Source.REMOVE;
                        });
                    yield;
                }
                if(devices.size == 0)
                    throw new FileError.UNSUPPORTED("No supported filesystem was found in this image");
                foreach(var device in devices)
                {
                    var interfaces = objects.lookup_value(device, null);
                    var points = interfaces.lookup_value(FILESYSTEM, null).lookup_value("MountPoints", new VariantType("aay"));
                    if(points != null && points.n_children() > 0)
                    {
                        var point = points.get_child_value(0);
                        var bytes = new ByteArray();
                        var storage = point.get_data_as_bytes();
                        bytes.append(storage.get_data());
                        bytes.append({0});
                        locations.add(File.new_for_path((string)bytes.data));
                        continue;
                    }
                    var mount_options = new VariantBuilder(VariantType.VARDICT);
                    mount_options.add("{sv}", "options", new Variant.string("ro"));
                    var response = yield bus.call(SERVICE, device, FILESYSTEM, "Mount", new Variant("(@a{sv})", mount_options.end()), new VariantType("(s)"), DBusCallFlags.NONE, 30000, null);
                    mounted.add(device);
                    locations.add(File.new_for_path(response.get_child_value(0).get_string()));
                }
            }
            catch(Error e) {
                // Roll back only mounts created by this request. Busy failures retain the loop.
                bool clean = true;
                for(int i = mounted.size - 1; i >= 0; i--)
                {
                    try {
                        yield bus.call(SERVICE, mounted[i], FILESYSTEM, "Unmount", new Variant("(@a{sv})", options()), null, DBusCallFlags.NONE, 30000, null);
                    }
                    catch(Error ignored) {
                        clean = false;
                    }
                }
                if(created && clean)
                {
                    try {
                        yield bus.call(SERVICE, loop, LOOP, "Delete", new Variant("(@a{sv})", options()), null, DBusCallFlags.NONE, 30000, null);
                    }
                    catch(Error ignored) {
                        clean = false;
                    }
                }
                if(!clean)
                    throw new FileError.CONFLICT(e.message + "\nThe image remains attached. Use Unmount Disk Image after closing files in it.");
                throw e;
            }
            return locations;
        }
        public async void unmount(File image) throws Error
        {
            var bus = yield Bus.get(BusType.SYSTEM);
            var objects = yield inventory(bus);
            var loop = find_loop(objects, image);
            if(loop == null)
                throw new FileError.INVALID("This disk image is not attached");
            foreach(var device in filesystems(objects, loop))
            {
                var points = objects.lookup_value(device, null).lookup_value(FILESYSTEM, null).lookup_value("MountPoints", new VariantType("aay"));
                if(points != null && points.n_children() > 0)
                    yield bus.call(SERVICE, device, FILESYSTEM, "Unmount", new Variant("(@a{sv})", options()), null, DBusCallFlags.NONE, 30000, null);
            }
            // A busy filesystem throws above; never force unmount or detach it.
            objects = yield inventory(bus);
            if(find_loop(objects, image) == loop)
                yield bus.call(SERVICE, loop, LOOP, "Delete", new Variant("(@a{sv})", options()), null, DBusCallFlags.NONE, 30000, null);
        }
    }
    public class DiskImageActions : Object, QuickActionProvider {
        static Gee.HashSet<string>? active;
        public string provider_id {
            owned get {
                return "disk-images";
            }
        }
        public Gee.List<QuickAction> actions(Gee.List<FileItem> selection)
        {
            var result = new Gee.ArrayList<QuickAction>();
            if(selection.size != 1 || !selection[0].file.is_native() || selection[0].directory || Paths.is_symlink(selection[0].info))
                return result;
            var name = selection[0].name.down();
            if(name.has_suffix(".iso") || name.has_suffix(".img") || name.has_suffix(".raw"))
            {
                result.add(new QuickAction("mount", "Mount Disk Image (Read Only)"));
                result.add(new QuickAction("unmount", "Unmount Disk Image"));
            }
            return result;
        }
        public async void execute(string id, Gee.List<FileItem> selection, Gtk.Window parent) throws Error
        {
            if(selection.size != 1 || (id != "mount" && id != "unmount"))
                throw new FileError.INVALID("Select one disk image");
            if(active == null)
                active = new Gee.HashSet<string>();
            string uri = selection[0].file.get_uri();
            if(!active.add(uri))
                throw new IOError.BUSY("An operation is already running for this disk image");
            var application = parent.application;
            if(application != null)
                application.hold();
            var service = new DiskImages();
            try {
                if(id == "unmount")
                    yield service.unmount(selection[0].file);
                else {
                    var locations = yield service.mount(selection[0].file);
                    var window = parent as FilesWindow;
                    if(window != null && window.visible)
                        foreach(var location in locations)
                            window.new_tab(location);
                }
            }
            finally {
                active.remove(uri);
                if(application != null)
                    application.release();
            }
        }
    }
}
