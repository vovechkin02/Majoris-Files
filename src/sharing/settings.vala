namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/sharing-settings.ui")]
    public class SharingPage : Adw.PreferencesPage {
        private bool template_disposing;
        Gtk.Window parent_window;
        bool managed;
        [GtkChild]
        private unowned Adw.ActionRow state_row;
        [GtkChild]
        private unowned Adw.SwitchRow enabled;
        [GtkChild]
        private unowned Adw.PreferencesGroup configuration;
        [GtkChild]
        private unowned Adw.ExpanderRow allowed;
        [GtkChild]
        private unowned Adw.ExpanderRow advanced;
        [GtkChild]
        private unowned Gtk.Button reconcile;
        File folder;
        SharingManager manager = new SharingManager();
        Cancellable token = new Cancellable();
        [GtkChild]
        private unowned Adw.EntryRow share_name;
        [GtkChild]
        private unowned Adw.SwitchRow everyone;
        [GtkChild]
        private unowned Adw.SwitchRow writable;
        [GtkChild]
        private unowned Adw.SwitchRow guest;
        [GtkChild]
        private unowned Adw.SwitchRow hidden;
        bool hidden_snapshot;
        [GtkChild]
        private unowned Adw.ActionRow address;
        [GtkChild]
        private unowned Adw.PreferencesGroup accounts;
        Gee.HashMap<string, Gtk.CheckButton> assignments = new Gee.HashMap<string, Gtk.CheckButton>();
        Gee.HashMap<string, Gtk.DropDown> levels = new Gee.HashMap<string, Gtk.DropDown>();
        string snapshot = "";
        string state_fingerprint = "";
        bool busy;
        uint monitor;
        bool monitoring;
        bool loading;
        Gee.ArrayList<Adw.ActionRow> account_rows = new Gee.ArrayList<Adw.ActionRow>();
        [GtkChild]
        private unowned Gtk.Button apply;
        [GtkChild]
        private unowned Gtk.Button stop;
        string? existing;
        string? requested;

        [GtkChild] private unowned Gtk.Box buttons;
        [GtkChild] private unowned Gtk.Button clients;
        [GtkChild] private unowned Gtk.Button close_firewall;
        [GtkChild] private unowned Gtk.Button firewall;
        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Gtk.Button reload;
        public SharingPage(Gtk.Window parent, File folder, string? requested = null, bool managed = false)
        {
            this.managed = managed;

            parent_window = parent;
            this.folder = folder;
            foreach (var row in new Adw.PreferencesRow[] {enabled, everyone, writable, guest, hidden, address, state_row, allowed, advanced}) row.use_markup = false;
            manager.warning_message.connect((message) => Dialogs.error(presenter(), message));
            this.requested = requested;

            group.title = folder.get_basename();

              reconcile.clicked.connect(() => load.begin());

            enabled.notify["active"].connect(() => {
                if (loading || busy) return;
                if (!enabled.active && existing != null) { remove.begin(); return; }
                configuration.visible = enabled.active;
            });

            share_name.text = folder.get_basename();

            everyone.notify["active"].connect(() => {
                guest.sensitive = everyone.active;
                if (!everyone.active)
                    guest.active = false;
            });

            firewall.clicked.connect(() => configure_firewall.begin(true));

            close_firewall.clicked.connect(() => configure_firewall.begin(false));

            reload.clicked.connect(() => load.begin());

            clients.clicked.connect(() => inspect_clients.begin());
            apply.sensitive = stop.sensitive = false;
            apply.clicked.connect(() => save.begin());
            stop.clicked.connect(() => remove.begin());
            everyone.notify["active"].connect(update_summary); writable.notify["active"].connect(update_summary);
            load.begin();
            monitor = Timeout.add_seconds(10, () => { check_external.begin(); return Source.CONTINUE; });
        }
        Gtk.Widget presenter() { return get_ancestor(typeof(Adw.Dialog)) ?? parent_window; }
        void update_summary() {
            int count = 0; string? uniform = null; bool mixed = false;
            foreach (var entry in assignments.entries) if (entry.value.active) {
                count++; string level = levels[entry.key].selected == 1 ? "F" : levels[entry.key].selected == 2 ? "D" : "R";
                if (uniform != null && uniform != level) mixed = true; uniform = level;
            }
            allowed.subtitle = everyone.active ? _("All authenticated users") : _("%d selected accounts").printf(count);
            if (everyone.active) { string level = writable.active ? "F" : "R"; if (uniform != null && uniform != level) mixed = true; uniform = level; }
            writable.sensitive = everyone.active;
            writable.subtitle = mixed ? _("Custom Access") : uniform == "F" ? _("Read & Write") : uniform == "R" ? _("Read Only") : _("No Access");
        }
        public void cancel() { token.cancel(); if (monitor != 0) { Source.remove(monitor); monitor = 0; } }
        async void check_external()
        {
            if (monitoring || loading || token.is_cancelled() || !apply.sensitive) return;
            monitoring = true;
            try {
                string actual = "";
                foreach (var share in (yield manager.inventory(token)))
                    if (share.name == (existing ?? share_name.text)) actual = share.path + "|" + share.acl + "|" + share.guest.to_string();
                if (actual != state_fingerprint) {
                    apply.sensitive = stop.sensitive = enabled.sensitive = false; reconcile.visible = true; state_row.visible = true; state_row.subtitle = _("Sharing changed outside Files. Reload before editing.");
                    address.subtitle = _("Sharing changed outside Files. Reload Sharing State before editing.");
                }
                if (existing != null && hidden.sensitive) {
                    SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                    if ((yield helper.get_hidden(existing)) != hidden_snapshot) {
                        apply.sensitive = stop.sensitive = enabled.sensitive = false; reconcile.visible = true; state_row.visible = true; state_row.subtitle = _("Sharing changed outside Files. Reload before editing.");
                        address.subtitle = _("Share visibility changed outside Files. Reload Sharing State before editing.");
                    }
                }
            }
            catch (Error e) { if (!token.is_cancelled()) address.subtitle = _("Could not reconcile sharing state: ") + e.message; }
            finally { monitoring = false; }
        }
        async void configure_firewall(bool enabled)
        {
            try {
                SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                var backend = yield helper.firewall_backend();
                if (backend != "firewalld") {
                    var dialog = new Adw.AlertDialog(_("Sharing Firewall"), backend == "none" ? _("No active packet-filter rules were detected. There is no supported firewall policy for Files to change. Network access still depends on Samba permissions and the surrounding network.") : _("An alternative or unknown firewall policy is present. Files cannot manage this policy; ask the administrator to configure SMB access. No rules were changed."));
                    dialog.add_response("close", _("Close")); dialog.present(presenter()); return;
                }
                if (!(yield Dialogs.confirm(presenter(), enabled ? "Allow local-network SMB sharing?" : "Close Files-owned SMB firewall access?", enabled ? "Only networks assigned to firewalld's Home or Work zones will be allowed. Public zones and administrator rules are unchanged. This applies to all local SMB shares." : "This removes only the trusted-zone access managed by Files. Other administrator rules remain unchanged.", enabled ? "Allow Trusted Networks" : "Close Access"))) return;
                yield helper.configure_firewall(enabled);
            }
            catch (Error e) { Dialogs.error(presenter(), e.message); }
        }
        async void inspect_clients()
        {
            if (existing == null) { Dialogs.error(presenter(), _("This folder is not currently shared.")); return; }
            try {
                SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                var json = yield helper.get_clients(existing);
                var parser = new Json.Parser(); parser.load_from_data(json);
                var output = new StringBuilder();
                foreach (var node in parser.get_root().get_array().get_elements()) {
                    var client = node.get_object();
                    output.append(client.get_string_member("client") + " · " + client.get_string_member("user") + " · " + client.get_string_member("share") + " · " + client.get_string_member("status") + "\n");
                }
                var dialog = new Adw.AlertDialog(_("Connected Clients"), output.len == 0 ? "No active clients were reported." : output.str);
                dialog.add_response("close", _("Close")); dialog.present(presenter());
            }
            catch (Error e) { Dialogs.error(presenter(), _("Connection status unavailable. Sharing remains usable.\n") + e.message); }
        }
        public override void unroot()
        {
            if (!managed) cancel();
            base.unroot();
        }
        void account(string id, string label, bool selected, string level = "R")
        {
            var row = new SharingAccountRow(); row.title = label;
            var check = row.check; check.active = selected; check.tooltip_text = label;
            var access = row.access; access.selected = level == "F" ? 1 : level == "D" ? 2 : 0;
            access.tooltip_text = _("Access for ") + label;
            levels[id] = access;
            accounts.add(row);
            account_rows.add(row);
            assignments[id] = check;
            check.toggled.connect(update_summary); access.notify["selected"].connect(update_summary);
        }
        async void load()
        {
            if (loading || token.is_cancelled()) return;
            loading = true;
            apply.sensitive = stop.sensitive = false;
            try {
                var shares = yield manager.inventory(token);
                foreach (var row in account_rows) accounts.remove(row);
                account_rows.clear(); assignments.clear(); levels.clear();
                everyone.active = true; writable.active = false; guest.active = false;
                existing = null; snapshot = ""; state_fingerprint = ""; share_name.editable = true;
                ShareRecord? current = null;
                foreach (var share in shares)
                    if (File.new_for_path(share.path).equal(folder) && (requested == null || requested == share.name))
                    { current = share; break; }
                var selected = new Gee.HashSet<string>();
                var rights = new Gee.HashMap<string, string>();
                if (current != null)
                {
                    existing = current.name;
                    stop.sensitive = true;
                    share_name.text = current.name;
                    // Changing a share's name would leave two access policies until
                    // deletion succeeds; edit the existing named share atomically.
                    share_name.editable = false;
                    writable.active = current.writable;
                    everyone.active = false;
                    rights = SharePolicy.parse_acl(current.acl);
                    snapshot = current.acl + "|" + current.guest.to_string();
                    state_fingerprint = current.path + "|" + snapshot;
                    foreach (var entry in rights.entries)
                    {
                        if (entry.key == "Everyone") {
                            if (entry.value == "D")
                                throw new FileError.UNSUPPORTED("An Everyone deny rule must be removed by its owner before editing this share.");
                            everyone.active = true;
                            writable.active = entry.value == "F";
                        }
                        else
                            selected.add(entry.key);
                    }
                    if (!everyone.active && current.guest)
                        throw new FileError.UNSUPPORTED("This share combines guest access with a restricted ACL and cannot be edited here safely.");
                    guest.active = current.guest;
                    address.subtitle = current.address;
                    apply.label = _("Apply Changes");
                    stop.sensitive = true;
                }
                else address.subtitle = _("Not shared");
                var users = yield AccountDirectory.load(true, token);
                foreach (var user in users)
                    if ((user.id >= 1000 && user.id < 65534) || selected.contains(user.name))
                    {
                        account(user.name, user.label, selected.contains(user.name), rights[user.name] ?? "R");
                        selected.remove(user.name);
                    }
                foreach (var id in selected)
                    account(id, id + " (unresolved account; deselect to remove)", true, rights[id] ?? "R");
                token.set_error_if_cancelled();
                apply.sensitive = true;
                try {
                    SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                    hidden.sensitive = yield helper.visibility_supported();
                    hidden_snapshot = existing != null && (yield helper.get_hidden(existing));
                    hidden.active = hidden_snapshot;
                    if (!hidden.sensitive) hidden.subtitle = _("The Majoris Samba registry-share foundation is not enabled.");
                }
                catch (Error e) { hidden.sensitive = false; hidden.subtitle = e.message; }
            }
            catch (Error e) {
                if (!token.is_cancelled())
                    address.subtitle = _("Sharing state unavailable: ") + e.message;
            }
            finally {
                loading = false;
                enabled.sensitive = !token.is_cancelled() && apply.sensitive;
                loading = true; enabled.active = existing != null; loading = false;
                configuration.visible = enabled.active;
                stop.visible = existing != null;
                reconcile.visible = !apply.sensitive; state_row.visible = !apply.sensitive; state_row.subtitle = address.subtitle;
                update_summary();
            }
        }
        async void save()
        {
            if (busy || loading || token.is_cancelled()) return;
            string[] users = {};
            var access = new Gee.HashMap<string, string>();
            if (everyone.active)
                access["Everyone"] = writable.active ? "F" : "R";
            foreach (var entry in assignments.entries)
                if (entry.value.active)
                    access[entry.key] = levels[entry.key].selected == 1 ? "F" : levels[entry.key].selected == 2 ? "D" : "R";
            if (!everyone.active)
            {
                foreach (var entry in assignments.entries)
                    if (entry.value.active)
                        users += entry.key;
                if (users.length == 0)
                {
                    Dialogs.error(presenter(), _("Select at least one account or enable access for all authenticated users."));
                    return;
                }
            }
            busy = true; enabled.sensitive = false;
            apply.sensitive = stop.sensitive = false;
            try {
                yield manager.share(folder, share_name.text, writable.active, guest.active, users, access, snapshot);
                if (hidden.sensitive) {
                    SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                    yield helper.set_hidden(share_name.text, hidden.active);
                    hidden_snapshot = hidden.active;
                }
                foreach (var share in (yield manager.inventory(token)))
                    if (share.name == share_name.text) {
                        snapshot = share.acl + "|" + share.guest.to_string(); state_fingerprint = share.path + "|" + snapshot;
                    }
                existing = share_name.text;
                configuration.visible = true; stop.visible = true; update_summary();
                share_name.editable = false;
                address.subtitle = _("smb://") + Environment.get_host_name() + "/" + Uri.escape_string(existing);
                apply.label = _("Apply Changes");
            }
            catch (Error e) { Dialogs.error(presenter(), e.message); }
            busy = false; enabled.sensitive = !token.is_cancelled();
            apply.sensitive = !token.is_cancelled();
            stop.sensitive = existing != null;
        }
        async void remove()
        {
            if (existing == null || busy || token.is_cancelled()) return;
            if (!(yield Dialogs.confirm(presenter(), "Stop sharing this folder?", "Existing clients may lose access to this share.", "Stop Sharing"))) {
                loading = true; enabled.active = true; loading = false; return;
            }
            busy = true; enabled.sensitive = false;
            apply.sensitive = stop.sensitive = false;
            try {
                yield manager.remove(existing);
                existing = null;
                snapshot = ""; state_fingerprint = "";
                address.subtitle = _("Not shared");
                apply.label = _("Share Folder");
                share_name.editable = true;
                loading = true; enabled.active = false; loading = false; configuration.visible = false; stop.visible = false;
            }
            catch (Error e) { Dialogs.error(presenter(), e.message); }
            busy = false; loading = true; enabled.active = existing != null; loading = false;
            enabled.sensitive = !token.is_cancelled(); configuration.visible = enabled.active; stop.visible = existing != null;
            apply.sensitive = !token.is_cancelled(); stop.sensitive = existing != null;
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                if (token != null) token.cancel();
                dispose_template(typeof(SharingPage));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/sharing-dialog.ui")]
    public class SharingDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        public SharingDialog(Gtk.Window parent, File folder, string? name = null)
        {
            var page = new SharingPage(parent, folder, name);
            add(page);
            closed.connect(page.cancel);
            present(parent);
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(SharingDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/shared-folders.ui")]
    public class SharedFoldersDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        Gtk.Window parent_window;
        [GtkChild]
        private unowned Adw.PreferencesGroup group;
        Cancellable token = new Cancellable();
        SharingManager manager = new SharingManager();
        Gee.ArrayList<Adw.ActionRow> rows = new Gee.ArrayList<Adw.ActionRow>();
        bool refreshing;
        string fingerprint = "";
        uint monitor;

        [GtkChild] private unowned Adw.PreferencesPage page;
        [GtkChild] private unowned Gtk.Button refresh;
        public SharedFoldersDialog(Gtk.Window parent)
        {
            parent_window = parent;

            refresh.clicked.connect(() => refresh_state.begin());
            manager.warning_message.connect((message) => Dialogs.error(parent_window, message));
            closed.connect(() => { token.cancel(); if (monitor != 0) { Source.remove(monitor); monitor = 0; } });
            monitor = Timeout.add_seconds(10, () => { refresh_state.begin(); return Source.CONTINUE; });
            refresh_state.begin();
            present(parent);
        }
        async void refresh_state()
        {
            if (refreshing || token.is_cancelled()) return;
            refreshing = true;
            try {
                var shares = yield manager.inventory(token);
                var next = new StringBuilder();
                foreach (var share in shares) next.append(share.name + "|" + share.path + "|" + share.acl + "|" + share.guest.to_string() + "\n");
                if (next.str == fingerprint && rows.size > 0) return;
                fingerprint = next.str;
                foreach (var row in rows) group.remove(row);
                rows.clear();
                group.description = shares.size == 0 ? "No Samba usershares are configured." : "Current Samba usershares. System smb.conf shares are managed by your administrator.";
                foreach (var share in shares)
                {
                    var row = new SharedFolderRow();
                    row.title = share.name;
                    row.subtitle = share.path + "\n" + share.address + "\n" + (share.writable ? "Read/write" : "Read-only") + " · " + (share.guest ? "Guests allowed" : "Authentication required") + "\n" + share.acl;
                    row.open.clicked.connect(() => {
                        AppInfo.launch_default_for_uri_async.begin(File.new_for_path(share.path).get_uri(), null, token, (obj, res) => {
                            try { AppInfo.launch_default_for_uri_async.end(res); }
                            catch (Error e) { Dialogs.error(parent_window, e.message); }
                        });
                    });
                    row.copy.clicked.connect(() => parent_window.get_clipboard().set_text(share.address));
                    row.edit.clicked.connect(() => new SharingDialog(parent_window, File.new_for_path(share.path), share.name));
                    row.stop.clicked.connect(() => stop_share.begin(share, row));
                    group.add(row);
                    rows.add(row);
                }
            }
            catch (Error e) { if (!token.is_cancelled()) group.description = _("Could not read Samba configuration: ") + e.message; }
            finally { refreshing = false; }
        }
        async void stop_share(ShareRecord share, Adw.ActionRow row)
        {
            if (!(yield Dialogs.confirm(parent_window, "Stop sharing “" + share.name + "”?", share.path, "Stop Sharing")))
                return;
            row.sensitive = false;
            try { yield manager.remove(share.name); if (rows.remove(row)) group.remove(row); }
            catch (Error e) { row.sensitive = true; Dialogs.error(parent_window, e.message); }
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                if (token != null) token.cancel();
                dispose_template(typeof(SharedFoldersDialog));
            }
            base.dispose();
        }
    }
}
