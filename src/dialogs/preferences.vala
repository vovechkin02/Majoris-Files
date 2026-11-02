namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/preferences.ui")]
    public class PreferencesDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        MetadataStore metadata;
        [GtkChild] private unowned Adw.PreferencesGroup extensions;
        [GtkChild] private unowned Adw.SwitchRow setting_1;
        [GtkChild] private unowned Adw.SwitchRow setting_2;
        [GtkChild] private unowned Adw.SwitchRow setting_3;
        [GtkChild] private unowned Adw.SwitchRow setting_4;
        [GtkChild] private unowned Adw.SwitchRow setting_5;
        [GtkChild] private unowned Adw.SwitchRow setting_6;
        [GtkChild] private unowned Adw.SwitchRow setting_7;
        [GtkChild] private unowned Adw.ComboRow setting_8;
        [GtkChild] private unowned Adw.ComboRow setting_9;
        [GtkChild] private unowned Adw.SwitchRow setting_10;
        [GtkChild] private unowned Adw.SwitchRow setting_11;
        [GtkChild] private unowned Adw.SwitchRow setting_12;
        [GtkChild] private unowned Adw.SwitchRow setting_13;
        [GtkChild] private unowned Adw.ComboRow setting_14;
        [GtkChild] private unowned Adw.SwitchRow setting_15;
        [GtkChild] private unowned Adw.SwitchRow setting_16;
        [GtkChild] private unowned Adw.SpinRow setting_17;
        [GtkChild] private unowned Adw.SpinRow setting_18;
        [GtkChild] private unowned Adw.ComboRow setting_19;
        [GtkChild] private unowned Adw.SpinRow setting_20;
        [GtkChild] private unowned Adw.SwitchRow setting_21;
        [GtkChild] private unowned Adw.SwitchRow setting_22;
        [GtkChild] private unowned Adw.SwitchRow setting_23;
        [GtkChild] private unowned Adw.ComboRow setting_24;
        [GtkChild] private unowned Adw.SpinRow setting_25;
        [GtkChild] private unowned Adw.SwitchRow setting_26;
        [GtkChild] private unowned Adw.SwitchRow setting_27;
        [GtkChild] private unowned Adw.SwitchRow setting_28;
        [GtkChild] private unowned Adw.SwitchRow setting_29;
        [GtkChild] private unowned Adw.ActionRow setting_30;
        [GtkChild] private unowned Adw.ActionRow setting_31;
        [GtkChild] private unowned Adw.ActionRow setting_32;
        public PreferencesDialog(MetadataStore metadata) {
            this.metadata = metadata;
            toggle(setting_1, "single-click", false);
            toggle(setting_2, "default-folders-first", true);
            toggle(setting_3, "extension-warning", true);
            toggle(setting_4, "confirm-delete", true);
            toggle(setting_5, "restore-session", true);
            toggle(setting_6, "notifications", true);
            toggle(setting_7, "scripts-enabled", false);
            choice(setting_8, "default-view", {"Grid", "List", "Columns", "Gallery"}, "Grid");
            choice(setting_9, "default-density", {"Compact", "Standard", "Large"}, "Standard");
            toggle(setting_10, "remember-folder-settings", true);
            toggle(setting_11, "show-hidden", false);
            toggle(setting_12, "show-extensions", true);
            toggle(setting_13, "default-checkboxes", false);
            choice(setting_14, "thumbnail-policy", {"Local", "All", "Never"}, "Local");
            toggle(setting_15, "preview-pane-default", false);
            toggle(setting_16, "autoplay-media", false);
            number(setting_17, "remote-import-limit-gib", 10, 1, 1024);
            number(setting_18, "remote-import-timeout-minutes", 30, 1, 1440);
            choice(setting_19, "remote-preview-policy", {"Never", "On Request", "Automatic"}, "On Request");
            number(setting_20, "remote-preview-limit-mib", 16, 1, 1024);
            toggle(setting_21, "indexed-search", true);
            toggle(setting_22, "exhaustive-search", false);
            toggle(setting_23, "rank-search-results", true);
            choice(setting_24, "recursive-search", {"Never", "Local", "Always"}, "Never");
            number(setting_25, "remote-thumbnail-limit", 8, 1, 128);
            toggle(setting_26, "home-favorites", true);
            toggle(setting_27, "home-recent", true);
            toggle(setting_28, "home-downloads", true);
            toggle(setting_29, "home-recommended", true);
            foreach (var extension in ExtensionManager.get_default(metadata).extensions) {
                var row = new Adw.SwitchRow(); row.title = extension.name;
                row.subtitle = extension.id + (extension.failure == "" ? "" : " · Unavailable: " + extension.failure);
                row.active = extension.enabled;
                row.notify["active"].connect(() => extension.set_enabled(row.active));
                extensions.add(row);
            }
        }
        void number(Adw.SpinRow row, string key, uint fallback, uint minimum, uint maximum)
        {
            uint value = fallback;
            uint.try_parse(metadata.state(key, fallback.to_string()), out value);
            row.value = value.clamp(minimum, maximum);
            row.notify["value"].connect(() => metadata.set_state(key, ((uint)row.value).to_string()));
        }
        void toggle(Adw.SwitchRow row, string key, bool fallback)
        {
            row.active = metadata.state(key, fallback ? "true" : "false") == "true";
            row.notify["active"].connect(() => metadata.set_state(key, row.active ? "true" : "false"));
        }
        void choice(Adw.ComboRow row, string key, string[] values, string fallback)
        {
            string selected = metadata.state(key, fallback);
            for(uint i = 0; i < values.length; i++)
                if(values[i] == selected)
                    row.selected = i;
            row.notify["selected"].connect(() => metadata.set_state(key, values[row.selected]));
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(PreferencesDialog));
            }
            base.dispose();
        }
    }
}
