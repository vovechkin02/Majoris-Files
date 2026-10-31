namespace MajorisFiles {
    // Preserve action targets and submenu semantics while dropping decoration.
    public class MenuPresentation : Object {
        public static Menu text_only(MenuModel source, string? alias = null) {
            var result = new Menu();
            for (int i = 0; i < source.get_n_items(); i++) {
                var item = new MenuItem.from_model(source, i);
                item.set_attribute_value("icon", null);
                item.set_attribute_value("verb-icon", null);
                if (alias != null) {
                    var action = source.get_item_attribute_value(i, "action", VariantType.STRING);
                    if (action != null && action.get_string().has_prefix("cloudprovider.")) item.set_attribute_value("action", new Variant.string(alias + action.get_string().substring("cloudprovider".length)));
                }
                var links = source.iterate_item_links(i); string name; MenuModel model; bool empty = false;
                while (links.get_next(out name, out model)) {
                    var nested = text_only(model, alias);
                    if ((name == Menu.LINK_SECTION || name == Menu.LINK_SUBMENU) && nested.get_n_items() == 0) empty = true;
                    item.set_link(name, nested);
                }
                if (!empty) result.append_item(item);
            }
            return result;
        }
        public static bool equal(MenuModel first, MenuModel second) {
            if (first.get_n_items() != second.get_n_items()) return false;
            for (int i = 0; i < first.get_n_items(); i++) {
                string name; Variant value; int count = 0, other_count = 0;
                var attributes = first.iterate_item_attributes(i);
                while (attributes.get_next(out name, out value)) { count++; var other = second.get_item_attribute_value(i, name, null); if (other == null || !other.equal(value)) return false; }
                attributes = second.iterate_item_attributes(i); while (attributes.get_next(out name, out value)) other_count++;
                if (count != other_count) return false;
                MenuModel model; count = 0; other_count = 0;
                var links = first.iterate_item_links(i);
                while (links.get_next(out name, out model)) { count++; var other = second.get_item_link(i, name); if (other == null || !equal(model, other)) return false; }
                links = second.iterate_item_links(i); while (links.get_next(out name, out model)) other_count++;
                if (count != other_count) return false;
            }
            return true;
        }
        public static void section(Menu menu, Menu section) {
            if (section.get_n_items() > 0) menu.append_section(null, section);
        }
        public static void button(Gtk.MenuButton button) {
            button.always_show_arrow = false;
            button.direction = Gtk.ArrowType.NONE;
            weak Gtk.MenuButton owner = button;
            button.notify["popover"].connect(() => { if (owner != null && owner.popover != null) owner.popover.has_arrow = false; });
            if (button.popover != null) button.popover.has_arrow = false;
        }
    }

    public class QuickAction : Object {
        public string id;
        public string label;
        public QuickAction(string id, string label)
        {
            this.id = id;
            this.label = label;
        }
    }
    public interface QuickActionProvider : Object {
        public abstract string provider_id {
            owned get;
        }
        public abstract Gee.List<QuickAction> actions(Gee.List<FileItem> selection);
        public abstract async void execute(string id, Gee.List<FileItem> selection, Gtk.Window parent) throws Error;
    }
    public class QuickActionRegistry : Object {
        Gee.HashMap<string, QuickActionProvider> providers = new Gee.HashMap<string, QuickActionProvider>();
        public void register_provider(QuickActionProvider provider)
        {
            providers[provider.provider_id] = provider;
        }
        public void register_nearby(NearbyShareProvider provider)
        {
            register_provider(new NearbyActions(provider));
        }
        public Menu menu(Gee.List<FileItem> selected, bool sharing = false)
        {
            var menu = new Menu();
            foreach(var provider in providers.values)
                if (!sharing || provider is NearbyActions)
                foreach(var action in provider.actions(selected))
                {
                    var item = new MenuItem(action.label, null);
                    item.set_action_and_target_value("win.provider-action", new Variant.string(provider.provider_id + ":" + action.id));
                    menu.append_item(item);
                }
            return menu;
        }
        public async void execute(string target, Gee.List<FileItem> selected, Gtk.Window parent) throws Error
        {
            var parts = target.split(":", 2);
            if(parts.length != 2 || !providers.has_key(parts[0]))
                throw new FileError.INVALID("Unknown action provider");
            yield providers[parts[0]].execute(parts[1], selected, parent);
        }
    }
    public class ScriptActions : Object, QuickActionProvider {
        MetadataStore metadata;
        File folder;
        public string provider_id {
            owned get {
                return "user-scripts";
            }
        }
        public ScriptActions(MetadataStore metadata)
        {
            this.metadata = metadata;
            folder = File.new_for_path(Path.build_filename(Environment.get_user_data_dir(), "majoris-files", "scripts"));
        }
        public Gee.List<QuickAction> actions(Gee.List<FileItem> selection)
        {
            var result = new Gee.ArrayList<QuickAction>();
            if(metadata.state("scripts-enabled", "false") != "true" || selection.size == 0)
                return result;
            foreach(var item in selection)
                if(!item.file.is_native())
                    return result;
            try {
                var en = folder.enumerate_children("standard::name,standard::display-name,standard::type,access::can-execute", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                FileInfo? info;
                while((info = en.next_file()) != null && result.size < 100)
                {
                    if(info.get_file_type() == FileType.REGULAR && info.get_attribute_boolean("access::can-execute"))
                        result.add(new QuickAction(info.get_name(), info.get_display_name()));
                }
                en.close();
            }
            catch(Error e) {}
            return result;
        }
        public async void execute(string id, Gee.List<FileItem> selection, Gtk.Window parent) throws Error
        {
            if(metadata.state("scripts-enabled", "false") != "true" || !Paths.valid_name(id))
                throw new FileError.INVALID("Scripts are disabled");
            var script = folder.get_child(id);
            var info = yield script.query_info_async("standard::type,access::can-execute", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
            if(info.get_file_type() != FileType.REGULAR || !info.get_attribute_boolean("access::can-execute"))
                throw new FileError.INVALID("The script is not an executable regular file");
            if(!(yield Dialogs.confirm(parent, "Run User Script?", script.get_parse_name() + "\nScripts run with your account’s permissions and receive the selected local paths. Only run scripts you trust.", "Run Script")))
                return;
            string[] arguments = {
                script.get_path()
            };
            foreach(var item in selection)
            {
                if(!item.file.is_native())
                    throw new FileError.UNSUPPORTED("This script accepts local files only");
                arguments += item.file.get_path();
            }
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
            if(selection.size > 0 && selection[0].file.get_parent() != null)
                launcher.set_cwd(selection[0].file.get_parent().get_path());
            var process = launcher.spawnv(arguments);
            yield process.wait_check_async(null);
        }
    }
}
