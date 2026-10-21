namespace MajorisFiles {
    public class PreferencesDialog : Adw.PreferencesDialog {
        MetadataStore metadata;
        public PreferencesDialog(MetadataStore metadata)
        {
            this.metadata = metadata;
            title = "Preferences";
            var general = page("General", "preferences-system-symbolic");
            var browsing = group(general, "Browsing");
            toggle(browsing, "Single Click to Open", "single-click", false);
            toggle(browsing, "Folders First by Default", "default-folders-first", true);
            toggle(browsing, "Warn When Changing File Extensions", "extension-warning", true);
            toggle(browsing, "Confirm Permanent Deletion", "confirm-delete", true);
            toggle(browsing, "Restore Tabs After an Unexpected Exit", "restore-session", true);
            toggle(browsing, "Notify About Background Operations", "notifications", true);
            toggle(browsing, "Enable User Scripts", "scripts-enabled", false);
            var view = group(page("View", "view-grid-symbolic"), "Defaults for New Folders");
            choice(view, "Default View", "default-view", {"Grid", "List", "Columns", "Gallery"}, "Grid");
            choice(view, "Default Icon Density", "default-density", {"Compact", "Standard", "Large"}, "Standard");
            toggle(view, "Remember Folder Settings", "remember-folder-settings", true);
            toggle(view, "Show Hidden Files", "show-hidden", false);
            toggle(view, "Show File Extensions", "show-extensions", true);
            toggle(view, "Item Selection Checkboxes", "default-checkboxes", false);
            var preview = group(page("Preview", "document-preview-symbolic"), "Previews and Thumbnails");
            choice(preview, "Thumbnails", "thumbnail-policy", {"Local", "All", "Never"}, "Local");
            var limit = new Adw.SpinRow.with_range(1, 128, 1);
            limit.title = _("Remote Thumbnail Download Limit (MiB)");
            uint value = 8;
            uint.try_parse(metadata.state("remote-thumbnail-limit", "8"), out value);
            limit.value = value.clamp(1, 128);
            limit.notify["value"].connect(() => metadata.set_state("remote-thumbnail-limit", ((uint)limit.value).to_string()));
            preview.add(limit);
            toggle(preview, "Show Preview Pane by Default", "preview-pane-default", false);
            toggle(preview, "Auto-play Media Previews", "autoplay-media", false);
            var network = group(page("Network", "network-workgroup-symbolic"), "Remote Content");
            number(network, "File Dialog Download Limit (GiB)", "remote-import-limit-gib", 10, 1, 1024);
            number(network, "File Dialog Download Timeout (minutes)", "remote-import-timeout-minutes", 30, 1, 1440);
            choice(network, "Remote Previews", "remote-preview-policy", {"Never", "On Request", "Automatic"}, "On Request");
            number(network, "Remote Preview Download Limit (MiB)", "remote-preview-limit-mib", 16, 1, 1024);
            var search = group(page("Search", "system-search-symbolic"), "Search Scope");
            var extensions = group(page("Extensions", "application-x-addon-symbolic"), "Installed External Extensions");
            extensions.description = _("Extensions run as separate user services. Enable only providers you trust; they receive selected file locations. Reopen Files to add or remove extension columns.");
            foreach (var extension in ExtensionManager.get_default(metadata).extensions) {
                var row = new Adw.SwitchRow(); row.title = extension.name;
                row.subtitle = extension.id + (extension.failure == "" ? "" : " · Unavailable: " + extension.failure);
                row.active = extension.enabled;
                row.notify["active"].connect(() => extension.set_enabled(row.active));
                extensions.add(row);
            }
            toggle(search, "Use the System Search Index", "indexed-search", true);
            toggle(search, "Rank Search Results by Relevance", "rank-search-results", true);
            choice(search, "Recursive Search by Default", "recursive-search", {"Never", "Local", "Always"}, "Never");
            var home = group(page("Home", "go-home-symbolic"), "Home Sections");
            foreach(var key in new string[] {"favorites", "recent", "downloads", "recommended"})
                toggle(home, key == "favorites" ? "Favorites" : key == "recent" ? "Recent" : key == "downloads" ? "Recent Downloads" : "Recommended", "home-" + key, true);
        }
        Adw.PreferencesPage page(string title, string icon)
        {
            var result = new Adw.PreferencesPage();
            result.title = title;
            result.icon_name = icon;
            add(result);
            return result;
        }
        void number(Adw.PreferencesGroup group, string title, string key, uint fallback, uint minimum, uint maximum)
        {
            var row = new Adw.SpinRow.with_range(minimum, maximum, 1);
            row.title = title;
            uint value = fallback;
            uint.try_parse(metadata.state(key, fallback.to_string()), out value);
            row.value = value.clamp(minimum, maximum);
            row.notify["value"].connect(() => metadata.set_state(key, ((uint)row.value).to_string()));
            group.add(row);
        }
        Adw.PreferencesGroup group(Adw.PreferencesPage page, string title)
        {
            var result = new Adw.PreferencesGroup();
            result.title = title;
            page.add(result);
            return result;
        }
        void toggle(Adw.PreferencesGroup group, string title, string key, bool fallback)
        {
            var row = new Adw.SwitchRow();
            row.title = title;
            row.active = metadata.state(key, fallback ? "true" : "false") == "true";
            row.notify["active"].connect(() => metadata.set_state(key, row.active ? "true" : "false"));
            group.add(row);
        }
        void choice(Adw.PreferencesGroup group, string title, string key, string[] values, string fallback)
        {
            var row = new Adw.ComboRow();
            row.title = title;
            row.model = new Gtk.StringList(values);
            string selected = metadata.state(key, fallback);
            for(uint i = 0; i < values.length; i++)
                if(values[i] == selected)
                    row.selected = i;
            row.notify["selected"].connect(() => metadata.set_state(key, values[row.selected]));
            group.add(row);
        }
    }
}
