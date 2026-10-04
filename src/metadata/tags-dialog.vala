namespace MajorisFiles {
    public class TagsDialog : Adw.PreferencesDialog {
        MetadataStore metadata;
        Adw.PreferencesPage page = new Adw.PreferencesPage();
        Adw.PreferencesGroup? group;
        public TagsDialog(MetadataStore metadata)
        {
            this.metadata = metadata;
            title = "Manage Tags";
            add(page);
            refresh();
        }
        void refresh()
        {
            if(group != null)
                page.remove(group);
            group = new Adw.PreferencesGroup();
            page.add(group);
            var add_button = new Gtk.Button.with_label("New Tag");
            add_button.clicked.connect(() => add_tag.begin());
            group.add(add_button);
            var names = metadata.all_tags();
            for(int i = 0; i < names.size; i++)
            {
                string name = names[i];
                var row = new Adw.ActionRow();
                row.title = name;
                row.subtitle = metadata.tag_color(name);
                var swatch = new Gtk.DrawingArea();
                swatch.width_request = 18;
                swatch.height_request = 18;
                var color = Gdk.RGBA();
                color.parse(metadata.tag_color(name));
                swatch.set_draw_func((area, cr, width, height) => { cr.set_source_rgba(color.red, color.green, color.blue, color.alpha);
                                                                    cr.arc(width / 2, height / 2, 7, 0, Math.PI * 2);
                                                                    cr.fill();
                    });
                row.add_prefix(swatch);
                row.add_suffix(Browser.button("document-edit-symbolic", "Rename Tag", () => rename.begin(name)));
                row.add_suffix(Browser.button("applications-graphics-symbolic", "Tag Color", () => recolor.begin(name)));
                row.add_suffix(Browser.button("go-up-symbolic", "Move Tag Up", () => reorder(name, -1)));
                row.add_suffix(Browser.button("go-down-symbolic", "Move Tag Down", () => reorder(name, 1)));
                row.add_suffix(Browser.button("edit-delete-symbolic", "Delete Tag", () => remove_tag.begin(name)));
                group.add(row);
            }
        }
        async void add_tag()
        {
            var name = yield Dialogs.prompt(get_root() as Gtk.Window, "New Tag");
            if(name != null && name.strip() != "")
            {
                metadata.define_tag(name, "#3584e4", metadata.all_tags().size);
                refresh();
            }
        }
        async void rename(string name)
        {
            var replacement = yield Dialogs.prompt(get_root() as Gtk.Window, "Rename Tag", name);
            if(replacement != null)
            {
                metadata.rename_tag(name, replacement);
                refresh();
            }
        }
        async void recolor(string name)
        {
            var replacement = yield Dialogs.prompt(get_root() as Gtk.Window, "Tag Color", metadata.tag_color(name));
            if(replacement == null)
                return;
            var color = Gdk.RGBA();
            if(!color.parse(replacement))
            {
                Dialogs.error(get_root() as Gtk.Window, "Enter a color such as #3584e4");
                return;
            }
            metadata.define_tag(name, color.to_string(), metadata.all_tags().index_of(name));
            refresh();
        }
        async void remove_tag(string name)
        {
            if(yield Dialogs.confirm(get_root() as Gtk.Window, "Delete Tag?", "Remove “" + name + "” from all tagged files?", "Delete Tag"))
            {
                metadata.delete_tag(name);
                refresh();
            }
        }
        void reorder(string name, int direction)
        {
            var names = metadata.all_tags();
            int index = names.index_of(name);
            int other = index + direction;
            if(other < 0 || other >= names.size)
                return;
            names[index] = names[other];
            names[other] = name;
            for(int i = 0; i < names.size; i++)
                metadata.define_tag(names[i], metadata.tag_color(names[i]), i);
            refresh();
        }
    }
}
