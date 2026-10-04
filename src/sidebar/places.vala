namespace MajorisFiles {
    public class Place : Object {
        public string label;
        public File file;
        public Mount? mount;
        public Volume? volume;
        public bool bookmark;
        public Place(string label, File file, Mount? mount = null)
        {
            this.label = label;
            this.file = file;
            this.mount = mount;
        }
    }
    public class Places : Object {
        public Gee.ArrayList<Place> entries = new Gee.ArrayList<Place>();
        public signal void changed();
        VolumeMonitor volumes;
        File bookmarks;
        FileMonitor? watcher;
        MetadataStore? metadata;
        public Places(MetadataStore? metadata = null)
        {
            this.metadata = metadata;
            if(metadata != null)
                metadata.changed.connect(reload);
            volumes = VolumeMonitor.get();
            volumes.mount_added.connect(reload);
            volumes.mount_removed.connect(reload);
            volumes.mount_changed.connect(reload);
            volumes.volume_added.connect(reload);
            volumes.volume_removed.connect(reload);
            volumes.volume_changed.connect(reload);
            bookmarks = File.new_for_path(Path.build_filename(Environment.get_user_config_dir(), "gtk-3.0", "bookmarks"));
            try {
                watcher = bookmarks.monitor_file(FileMonitorFlags.NONE);
                watcher.changed.connect(reload);
            }
            catch (Error e) {}
            reload();
        }
        public void reload()
        {
            entries.clear();
            entries.add(new Place("Home", File.new_for_path(Environment.get_home_dir())));
            entries.add(new Place("Recent", File.new_for_uri("recent:///")));
            entries.add(new Place("Favorites", File.new_for_uri("majoris:///favorites")));
            if(metadata != null)
            {
                foreach(var tag in metadata.all_tags())
                    entries.add(new Place("Tag: " + tag, File.new_for_uri("majoris:///tag/" + Uri.escape_string(tag))));
                foreach(var saved in metadata.saved_searches())
                    entries.add(new Place(saved.name, File.new_for_uri("majoris:///search/" + Uri.escape_string(saved.name))));
            }
            UserDirectory[] dirs = {
                UserDirectory.DESKTOP, UserDirectory.DOCUMENTS, UserDirectory.DOWNLOAD, UserDirectory.MUSIC, UserDirectory.PICTURES, UserDirectory.VIDEOS
            };
            foreach (var dir in dirs)
            {
                var path = Environment.get_user_special_dir(dir);
                if (path != null && path != Environment.get_home_dir())
                    entries.add(new Place(Path.get_basename(path), File.new_for_path(path)));
            }
            string content;
            try {
                FileUtils.get_contents(bookmarks.get_path(), out content);
                foreach (var line in content.split("\n"))
                {
                    if (line.strip() == "")
                        continue;
                    var parts = line.split(" ", 2);
                    var file = File.new_for_uri(parts[0]);
                    var place = new Place(parts.length > 1 ? parts[1] : file.get_basename(), file);
                    place.bookmark = true;
                    entries.add(place);
                }
            }
            catch (Error e) {}
            foreach (var mount in volumes.get_mounts())
                entries.add(new Place(mount.get_name(), mount.get_root(), mount));
            foreach(var volume in volumes.get_volumes())
                if(volume.get_mount() == null)
                {
                    var place = new Place(volume.get_name(), volume.get_activation_root() ?? File.new_for_uri("majoris:///device/" + Uri.escape_string(volume.get_uuid() ?? volume.get_name())));
                    place.volume = volume;
                    entries.add(place);
                }
            entries.add(new Place("Network", File.new_for_uri("network:///")));
            entries.add(new Place("Trash", File.new_for_uri("trash:///")));
            changed();
        }
        public async void add_bookmark(File file) throws Error
        {
            string content = "";
            try {
                FileUtils.get_contents(bookmarks.get_path(), out content);
            }
            catch (Error e) {}
            foreach (var line in content.split("\n"))
                if (line.split(" ", 2)[0] == file.get_uri())
                    return;
            DirUtils.create_with_parents(bookmarks.get_parent().get_path(), 0700);
            if(content != "" && !content.has_suffix("\n"))
                content += "\n";
            uint8[] bytes = (content + file.get_uri() + "\n").data;
            yield bookmarks.replace_contents_async(bytes, null, false, FileCreateFlags.PRIVATE, null, null);
            reload();
        }
        public async void edit_bookmark(File file, string? label, bool remove = false, int move = 0) throws Error
        {
            uint8[] content;
            string? etag;
            yield bookmarks.load_contents_async(null, out content, out etag);
            var lines = new Gee.ArrayList<string>();
            foreach(var line in ((string)content).split("\n"))
                if(line.strip() != "")
                    lines.add(line);
            int index = -1;
            for(int i = 0; i < lines.size; i++)
                if(lines[i].split(" ", 2)[0] == file.get_uri())
                {
                    index = i;
                    break;
                }
            if(index < 0)
                return;
            if(remove)
                lines.remove_at(index);
            else if(move != 0)
            {
                int position = int.max(0, int.min(lines.size - 1, index + move));
                var value = lines.remove_at(index);
                lines.insert(position, value);
            }
            else if(label != null)
            {
                if(label.contains("\n") || label.contains("\r"))
                    throw new FileError.INVALID("Invalid bookmark label");
                lines[index] = file.get_uri() + " " + label.strip();
            }
            var output = new StringBuilder();
            foreach(var line in lines)
                output.append(line + "\n");
            yield bookmarks.replace_contents_async(output.str.data, etag, false, FileCreateFlags.PRIVATE, null, null);
            reload();
        }
    }
}
