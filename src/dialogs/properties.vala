namespace MajorisFiles {
    // A selection snapshot and one native navigation stack own the entire lifetime.
    public class PropertiesDialog : Adw.PreferencesDialog {
        public static void present_selection(Gtk.Window parent, Gee.List<FileItem> items, MetadataStore metadata) { if (items.size > 0) new PropertiesDialog(parent, items, metadata).present(parent); }
        public Gee.ArrayList<FileItem> items = new Gee.ArrayList<FileItem>();
        public Adw.PreferencesPage general = new Adw.PreferencesPage();
        public Cancellable token = new Cancellable();
        MetadataStore metadata;
        Gtk.Window owner_window;
        Gee.HashMap<string, Adw.NavigationPage> subpages = new Gee.HashMap<string, Adw.NavigationPage>();
        PermissionsPage? permissions;
        SharingPage? sharing;
        MetadataPage? details;
        FileCounts counts = new FileCounts();
        Adw.ActionRow identity;
        Adw.ActionRow? contents;
        Adw.ActionRow? total;
        Adw.ActionRow? exact_size;
        Adw.ActionRow? allocated;
        Adw.SwitchRow favorites;
        Adw.ActionRow tags;
        Adw.ActionRow? association;
        bool updating;
        bool counting;
        bool single_size_known;
        ulong metadata_handler;
        public PropertiesDialog(Gtk.Window parent, Gee.List<FileItem> selected, MetadataStore metadata) {
            title = _("Properties"); content_width = 560; content_height = 620; search_enabled = false;
            owner_window = parent; this.metadata = metadata;
            foreach (var item in selected) items.add(item);
            var cloud = CloudFiles.get_default().cached(items[0].file);
            single_size_known = items[0].info.has_attribute("standard::size") || (cloud != null && cloud.size_known);
            general.title = _("General"); general.name = "general"; general.icon_name = "document-properties-symbolic";
            add(general);
            var heading = new Adw.PreferencesGroup(); general.add(heading);
            identity = value_row(items.size == 1 ? items[0].name : _("%d selected items").printf(items.size), identity_description());
            identity.title_lines = 2; identity.subtitle_lines = 2;
            var image = new Gtk.Image.from_icon_name("edit-copy-symbolic"); image.pixel_size = 48;
            if (items.size == 1) image.set_from_gicon((items[0].info.has_attribute("standard::icon") ? items[0].info.get_icon() : null) ?? new ThemedIcon("text-x-generic"));
            identity.add_prefix(image); heading.add(identity);
            if (items.size == 1 && !items[0].directory) {
                var thumbnails = new ThumbnailService(metadata);
                thumbnails.texture.begin(items[0], token, (obj, res) => {
                    try { var texture = thumbnails.texture.end(res); if (!token.is_cancelled() && texture != null) image.set_from_paintable(texture); } catch (Error e) {}
                });
            }
            var information = new Adw.PreferencesGroup(); information.title = _("Information"); general.add(information);
            File? common = items[0].file.get_parent();
            foreach (var item in items) if (common != null && (item.file.get_parent() == null || !common.equal(item.file.get_parent()))) common = null;
            var location = value_row(_("Location"), common == null ? _("Multiple locations") : readable_location(common));
            string? copied_location = items.size == 1 ? (items[0].file.get_path() ?? items[0].file.get_uri()) : common == null ? null : (common.get_path() ?? common.get_uri());
            if (copied_location != null) location.add_suffix(Browser.button("edit-copy-symbolic", _("Copy Location"), () => get_clipboard().set_text(copied_location)));
            information.add(location);
            if (items.size == 1) {
                var date = items[0].info.has_attribute("time::modified") ? items[0].info.get_modification_date_time() : null;
                if (date != null) information.add(value_row(_("Modified"), date.to_local().format("%x")));
            } else {
                total = value_row(_("Total Size"), _("Calculating…")); information.add(total);
                var types = new Gee.HashSet<string>(); foreach (var item in items) types.add(item.mime);
                information.add(value_row(_("Types"), types.size == 1 ? ContentType.get_description(items[0].mime) : _("Multiple file types")));
            }
            if (items.size == 1 && counted_folder(items[0])) { contents = value_row(_("Contents"), _("Calculating…")); information.add(contents); }
            if (items.size == 1 && !items[0].directory && items[0].info.get_file_type() != FileType.MOUNTABLE) {
                var applications = new Adw.PreferencesGroup(); applications.title = _("Open With"); general.add(applications);
                association = value_row("", "");
                var change = new Gtk.Button.with_label(_("Change…")); change.valign = Gtk.Align.CENTER;
                association.add_suffix(change); association.activatable_widget = change;
                applications.add(association); refresh_association();
                change.clicked.connect(() => {
                    var chooser = new AssociationChooser(this, items[0]);
                    chooser.changed.connect(refresh_association); chooser.present(this);
                });
            }
            var organisation = new Adw.PreferencesGroup(); organisation.title = _("Organisation"); general.add(organisation);
            favorites = new Adw.SwitchRow(); favorites.title = items.size == 1 ? _("Favorite") : _("Favorite All Selected Items"); organisation.add(favorites);
            tags = value_row(_("Tags"), ""); tags.activatable = true; tags.add_suffix(new Gtk.Image.from_icon_name("go-next-symbolic")); organisation.add(tags);
            refresh_organisation();
            favorites.notify["active"].connect(() => {
                if (updating) return;
                bool active = favorites.active; updating = true;
                foreach (var item in items) metadata.set_favorite(item.file, active);
                updating = false; refresh_organisation();
            });
            tags.activated.connect(() => edit_tags.begin());
            metadata_handler = metadata.changed.connect(() => { if (!token.is_cancelled()) refresh_organisation(); });
            var additional = new Adw.PreferencesGroup(); additional.title = _("Additional Information"); general.add(additional);
            if (items.size == 1 && shareable(items[0])) destination(additional, _("Sharing"), () => {
                if (sharing == null) sharing = new SharingPage(owner_window, items[0].file, null, true);
                show_subpage("sharing", _("Sharing"), sharing);
            });
            destination(additional, _("Permissions"), () => {
                if (permissions == null) {
                    permissions = new PermissionsPage(owner_window, items, true);
                    permissions.applied.connect(() => { if (details != null) details.refresh_file_info.begin(); add_toast(new Adw.Toast(_("Permissions updated"))); });
                }
                show_subpage("permissions", _("Permissions"), permissions);
            });
            destination(additional, _("Details"), () => {
                if (!subpages.has_key("details")) {
                    Adw.PreferencesPage page;
                    if (items.size == 1) { details = new MetadataPage(items[0], metadata, true); details.refresh_file_info.begin(); page = details; }
                    else { page = new Adw.PreferencesPage(); var group = new Adw.PreferencesGroup(); group.title = _("File Information"); page.add(group); group.add(value_row(_("Selected Items"), items.size.to_string())); }
                    if (details != null) { exact_size = details.exact_size; allocated = details.allocated; }
                    else { var statistics = new Adw.PreferencesGroup(); statistics.title = _("Storage"); page.add(statistics); exact_size = value_row(_("Exact Size"), ""); allocated = value_row(_("Size on Disk"), ""); statistics.add(exact_size); statistics.add(allocated); }
                    update_counts();
                    show_subpage("details", _("Details"), page);
                } else push_subpage(subpages["details"]);
            });
            counting = items.size > 1 || counted_folder(items[0]);
            if (counting) {
                counts.updated.connect(() => { if (!token.is_cancelled()) update_counts(); });
                var roots = new Gee.ArrayList<File>(); foreach (var item in items) roots.add(item.file);
                counts.scan.begin(roots, token, (obj, res) => {
                    try { counts.scan.end(res); if (!token.is_cancelled()) { counting = false; update_counts(); announce(_("Contents calculation complete"), Gtk.AccessibleAnnouncementPriority.MEDIUM); } }
                    catch (Error e) { if (!token.is_cancelled() && contents != null) contents.subtitle = e.message; }
                });
            } else { counts.bytes = items[0].bytes; counts.allocated_known = items[0].info.has_attribute("standard::allocated-size"); counts.allocated = counts.allocated_known ? items[0].info.get_attribute_uint64("standard::allocated-size") : 0; }
            closed.connect(() => {
                token.cancel(); if (permissions != null) permissions.cancel(); if (sharing != null) sharing.cancel(); if (details != null) details.cancel();
                if (metadata_handler != 0) { metadata.disconnect(metadata_handler); metadata_handler = 0; }
            });
        }
        public static Adw.ActionRow value_row(string title, string value) {
            var row = new Adw.ActionRow(); row.use_markup = false; row.title = title; row.subtitle = value; row.subtitle_selectable = true; row.subtitle_lines = 2; return row;
        }
        static string readable_location(File location) {
            var home = File.new_for_path(Environment.get_home_dir());
            if (location.equal(home)) return _("Home");
            string? relative = home.get_relative_path(location);
            return relative == null ? location.get_parse_name() : _("Home") + " / " + relative.replace("/", " / ");
        }
        public static bool shareable(FileItem item) {
            if (!item.file.is_native() || !item.directory || Paths.is_symlink(item.info) || item.file.get_parent() == null || (item.info.has_attribute("unix::is-mountpoint") && item.info.get_attribute_boolean("unix::is-mountpoint"))) return false;
            string path = item.file.get_path();
            if (path == "/") return false;
            foreach (var system in new string[] {"/etc", "/proc", "/sys", "/dev", "/boot", "/root"}) if (path.has_prefix(system)) return false;
            return item.info.get_file_type() != FileType.MOUNTABLE;
        }
        void destination(Adw.PreferencesGroup group, string title, owned Callback action) {
            var row = value_row(title, ""); row.activatable = true; row.add_suffix(new Gtk.Image.from_icon_name("go-next-symbolic")); row.activated.connect(() => action()); group.add(row);
        }
        void show_subpage(string key, string title, Adw.PreferencesPage page) {
            if (!subpages.has_key(key)) {
                var view = new Adw.ToolbarView(); view.add_top_bar(new Adw.HeaderBar()); view.content = page;
                subpages[key] = new Adw.NavigationPage(view, title);
            }
            push_subpage(subpages[key]);
        }
        static bool counted_folder(FileItem item) { return item.directory && !Paths.is_symlink(item.info); }
        string identity_description() {
            if (items.size == 1) { string description = ContentType.get_description(items[0].mime); return counted_folder(items[0]) ? _("Folder") : (Paths.is_symlink(items[0].info) ? _("Symbolic Link") : description.contains(items[0].mime) ? _("File") : description) + (single_size_known ? " · " + Paths.size(items[0].bytes) : ""); }
            int folders = 0; foreach (var item in items) if (counted_folder(item)) folders++;
            return (items.size - folders == 1 ? _("1 file") : _("%d files").printf(items.size - folders)) + " · " + (folders == 1 ? _("1 folder") : _("%d folders").printf(folders));
        }
        void update_counts() {
            string partial = counts.unreadable > 0 ? _(" · Partial total; some items are unreadable") : "";
            uint64 children = counts.files + counts.folders;
            if (items.size == 1 && counted_folder(items[0]) && counts.folders > 0) children--;
            string summary = (children == 1 ? _("1 item") : _("%s items").printf(children.to_string())) + (counting ? _(" · Calculating…") : "") + partial;
            if (contents != null) contents.subtitle = summary;
            if (total != null) total.subtitle = Paths.size(counts.bytes) + (counting ? _(" · Calculating…") : "") + partial;
            if (items.size == 1 && counted_folder(items[0])) identity.subtitle = _("Folder") + " · " + summary;
            if (exact_size != null) exact_size.subtitle = items.size == 1 && !counted_folder(items[0]) && !single_size_known ? _("Unavailable") : counts.bytes.to_string() + _(" bytes") + partial;
            if (allocated != null) allocated.subtitle = counts.allocated_known ? Paths.size(counts.allocated) + (counting ? _(" · Calculating…") : "") + partial : _("Unavailable for this selection");
        }
        void refresh_association() {
            if (association == null || token.is_cancelled()) return;
            var app = AppInfo.get_default_for_type(items[0].mime, !items[0].file.is_native());
            association.title = app == null ? _("No default application") : app.get_display_name(); association.subtitle = app == null ? _("Choose an application for this file type") : _("Default application");
            var prefix = association.get_data<Gtk.Image>("application-icon");
            if (prefix == null) { prefix = new Gtk.Image(); prefix.pixel_size = 32; association.add_prefix(prefix); association.set_data<Gtk.Image>("application-icon", prefix); }
            prefix.set_from_gicon(app == null ? new ThemedIcon("application-x-executable-symbolic") : app.get_icon() ?? new ThemedIcon("application-x-executable-symbolic"));
        }
        void refresh_organisation() {
            if (updating) return;
            updating = true; bool all = true; string first = metadata.tags(items[0].file); bool mixed = false;
            foreach (var item in items) { all = all && metadata.favorite(item.file); if (metadata.tags(item.file) != first) mixed = true; }
            favorites.active = all; tags.subtitle = mixed ? _("Mixed tags") : first == "" ? _("None") : first; updating = false;
        }
        async void edit_tags() {
            var text = yield Dialogs.prompt(this, _("Tags"), items.size == 1 ? metadata.tags(items[0].file) : "", items.size == 1 ? _("Separate tags with commas.") : _("Applying replaces tags on all %d selected items. Separate tags with commas.").printf(items.size));
            if (text != null && !token.is_cancelled()) foreach (var item in items) metadata.set_tags(item.file, text);
        }
    }
}
