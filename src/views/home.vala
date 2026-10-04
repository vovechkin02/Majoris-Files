namespace MajorisFiles {
    public class HomeView : Gtk.Box {
        MetadataStore metadata;
        Gtk.Box sections = new Gtk.Box(Gtk.Orientation.VERTICAL, 18);
        Cancellable token = new Cancellable();
        public signal void activated(FileItem item);
        public HomeView(MetadataStore metadata)
        {
            Object(orientation: Gtk.Orientation.VERTICAL);
            this.metadata = metadata;
            var scroll = new Gtk.ScrolledWindow();
            scroll.vexpand = true;
            scroll.set_child(sections);
            append(scroll);
            sections.margin_start = 24;
            sections.margin_end = 24;
            sections.margin_top = 24;
            sections.margin_bottom = 24;
            scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        }
        public void cancel()
        {
            token.cancel();
        }
        public async void reload()
        {
            token.cancel();
            token = new Cancellable();
            var pending = token;
            while(sections.get_first_child() != null)
                sections.remove(sections.get_first_child());
            var title = new Gtk.Label("Home");
            title.add_css_class("title-1");
            title.halign = Gtk.Align.START;
            sections.append(title);
            if(metadata.state("home-favorites", "true") == "true")
                yield populate("Favorites", metadata.favorites(), pending);
            var recent = new Gee.ArrayList<File>();
            var recommendations = new Gee.ArrayList<File>();
            var items = new Gee.ArrayList<Gtk.RecentInfo>();
            foreach(var info in Gtk.RecentManager.get_default().get_items())
                if(info.is_local())
                    items.add(info);
            items.sort((a, b) => b.get_modified().compare(a.get_modified()));
            foreach(var info in items)
            {
                if(recent.size < 12)
                    recent.add(File.new_for_uri(info.get_uri()));
            }
            if(metadata.state("home-recent", "true") == "true")
                yield populate("Recent", recent, pending);
            items.sort((a, b) => score(a) > score(b) ? -1 : score(a) < score(b) ? 1 : 0);
            foreach(var info in items)
                if(recommendations.size < 8)
                    recommendations.add(File.new_for_uri(info.get_uri()));
            if(metadata.state("home-recommended", "true") == "true")
                yield populate("Recommended · local usage", recommendations, pending);
            var downloads = Environment.get_user_special_dir(UserDirectory.DOWNLOAD);
            if(downloads != null && metadata.state("home-downloads", "true") == "true")
            {
                try {
                    var folder = File.new_for_path(downloads);
                    var en = yield folder.enumerate_children_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, pending);
                    var entries = new Gee.ArrayList<FileItem>();
                    try {
                        while(true)
                        {
                            var batch = yield en.next_files_async(128, Priority.LOW, pending);
                            if(batch == null)
                                break;
                            foreach(var info in batch)
                                if(!info.get_is_hidden())
                                    entries.add(new FileItem(folder.get_child(info.get_name()), info));
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
                    entries.sort((a, b) => { var x = a.info.get_attribute_uint64("time::modified"), y = b.info.get_attribute_uint64("time::modified");
                                             return x > y ? -1 : x < y ? 1 : 0;
                        });
                    var files = new Gee.ArrayList<File>();
                    for(int i = 0; i < int.min(12, entries.size); i++)
                        files.add(entries[i].file);
                    yield populate("Recent Downloads · last modified", files, pending);
                }
                catch(Error e) {}
            }
        }
        double score(Gtk.RecentInfo info)
        {
            return info.get_modified().to_unix() + metadata.usage(File.new_for_uri(info.get_uri())) * 86400.0;
        }
        async void populate(string title, Gee.List<File> files, Cancellable pending)
        {
            if(pending.is_cancelled())
                return;
            var heading = new Gtk.Label(title);
            heading.add_css_class("title-3");
            heading.halign = Gtk.Align.START;
            sections.append(heading);
            var list = new Gtk.ListBox();
            list.add_css_class("boxed-list");
            list.selection_mode = Gtk.SelectionMode.NONE;
            sections.append(list);
            uint count = 0;
            foreach(var file in files)
            {
                if(pending.is_cancelled() || count >= 12)
                    return;
                if(!file.is_native())
                    continue;
                try {
                    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NONE, Priority.LOW, pending);
                    if(pending.is_cancelled())
                        return;
                    var item = new FileItem(file, info);
                    var row = new Adw.ActionRow();
                    row.title = item.name;
                    row.subtitle = file.get_parent() == null ? file.get_parse_name() : file.get_parent().get_parse_name();
                    row.add_prefix(new Gtk.Image.from_gicon(info.get_icon()));
                    row.activatable = true;
                    row.activated.connect(() => activated(item));
                    list.append(row);
                    count++;
                }
                catch(Error e) {}
            }
            if(count == 0)
                list.append(new Gtk.Label("No items yet"));
        }
    }
}
