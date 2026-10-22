namespace MajorisFiles {
    public class SharingPage : Adw.PreferencesPage {
        Gtk.Window parent_window;
        File folder;
        SharingManager manager = new SharingManager();
        Cancellable token = new Cancellable();
        Adw.EntryRow share_name = new Adw.EntryRow();
        Adw.SwitchRow everyone = new Adw.SwitchRow();
        Adw.SwitchRow writable = new Adw.SwitchRow();
        Adw.SwitchRow guest = new Adw.SwitchRow();
        Adw.SwitchRow hidden = new Adw.SwitchRow();
        bool hidden_snapshot;
        Adw.ActionRow address = new Adw.ActionRow();
        Adw.PreferencesGroup accounts = new Adw.PreferencesGroup();
        Gee.HashMap<string, Gtk.CheckButton> assignments = new Gee.HashMap<string, Gtk.CheckButton>();
        Gee.HashMap<string, Gtk.DropDown> levels = new Gee.HashMap<string, Gtk.DropDown>();
        string snapshot = "";
        uint monitor;
        bool monitoring;
        bool loading;
        Gee.ArrayList<Adw.ActionRow> account_rows = new Gee.ArrayList<Adw.ActionRow>();
        Gtk.Button apply = new Gtk.Button.with_label(_("Share Folder"));
        Gtk.Button stop = new Gtk.Button.with_label(_("Stop Sharing"));
        string? existing;
        string? requested;
        public SharingPage(Gtk.Window parent, File folder, string? requested = null)
        {
            title = "Sharing";
            icon_name = "folder-remote-symbolic";
            parent_window = parent;
            this.folder = folder;
            manager.warning_message.connect((message) => Dialogs.error(parent_window, message));
            this.requested = requested;
            var group = new Adw.PreferencesGroup();
            group.title = folder.get_parse_name();
            group.description = _("Network permissions also depend on filesystem permissions. Write access permits creating, modifying and deleting content.");
            add(group);
            share_name.title = _("Share Name");
            share_name.text = folder.get_basename();
            group.add(share_name);
            everyone.title = _("All Authenticated Users");
            everyone.active = true;
            group.add(everyone);
            writable.title = _("Read and Write");
            group.add(writable);
            guest.title = _("Allow Guest Access");
            group.add(guest);
            hidden.title = _("Hide from network browsing");
            hidden.subtitle = _("Direct access still requires the configured authentication and permissions.");
            hidden.sensitive = false;
            group.add(hidden);
            address.title = _("Network Address");
            address.subtitle = _("Loading sharing state…");
            address.subtitle_selectable = true;
            group.add(address);
            accounts.title = _("Allowed Accounts");
            accounts.description = _("Select at least one account when access for all authenticated users is disabled. Samba credentials must be configured for each account.");
            add(accounts);
            everyone.notify["active"].connect(() => {
                guest.sensitive = everyone.active;
                if (!everyone.active)
                    guest.active = false;
            });
            accounts.sensitive = true;
            var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            apply.add_css_class("suggested-action");
            buttons.append(apply);
            buttons.append(stop);
            group.add(buttons);
            var firewall = new Gtk.Button.with_label(_("Allow SMB on Home and Work Networks…"));
            group.add(firewall);
            firewall.clicked.connect(() => configure_firewall.begin(true));
            var close_firewall = new Gtk.Button.with_label(_("Close Files-owned SMB Firewall Access…"));
            group.add(close_firewall);
            close_firewall.clicked.connect(() => configure_firewall.begin(false));
            var reload = new Gtk.Button.with_label(_("Reload Sharing State"));
            group.add(reload);
            reload.clicked.connect(() => load.begin());
            var clients = new Gtk.Button.with_label(_("Inspect Connected Clients…"));
            group.add(clients);
            clients.clicked.connect(() => inspect_clients.begin());
            apply.sensitive = stop.sensitive = false;
            apply.clicked.connect(() => save.begin());
            stop.clicked.connect(() => remove.begin());
            load.begin();
            monitor = Timeout.add_seconds(10, () => { check_external.begin(); return Source.CONTINUE; });
        }
        public void cancel() { token.cancel(); if (monitor != 0) { Source.remove(monitor); monitor = 0; } }
        async void check_external()
        {
            if (monitoring || loading || token.is_cancelled() || !apply.sensitive) return;
            monitoring = true;
            try {
                string actual = "";
                foreach (var share in (yield manager.inventory(token)))
                    if (share.name == (existing ?? share_name.text)) actual = share.acl + "|" + share.guest.to_string();
                if (actual != snapshot) {
                    apply.sensitive = stop.sensitive = false;
                    address.subtitle = _("Sharing changed outside Files. Reload Sharing State before editing.");
                }
                if (existing != null && hidden.sensitive) {
                    SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                    if ((yield helper.get_hidden(existing)) != hidden_snapshot) {
                        apply.sensitive = false;
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
                    dialog.add_response("close", _("Close")); dialog.present(parent_window); return;
                }
                if (!(yield Dialogs.confirm(parent_window, enabled ? "Allow local-network SMB sharing?" : "Close Files-owned SMB firewall access?", enabled ? "Only networks assigned to firewalld's Home or Work zones will be allowed. Public zones and administrator rules are unchanged. This applies to all local SMB shares." : "This removes only the trusted-zone access managed by Files. Other administrator rules remain unchanged.", enabled ? "Allow Trusted Networks" : "Close Access"))) return;
                yield helper.configure_firewall(enabled);
            }
            catch (Error e) { Dialogs.error(parent_window, e.message); }
        }
        async void inspect_clients()
        {
            if (existing == null) { Dialogs.error(parent_window, _("This folder is not currently shared.")); return; }
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
                dialog.add_response("close", _("Close")); dialog.present(parent_window);
            }
            catch (Error e) { Dialogs.error(parent_window, _("Connection status unavailable. Sharing remains usable.\n") + e.message); }
        }
        public override void unroot()
        {
            cancel();
            base.unroot();
        }
        void account(string id, string label, bool selected, string level = "R")
        {
            var row = new Adw.ActionRow();
            row.title = label;
            row.subtitle = _("Share-level access; filesystem permissions can further restrict it.");
            var check = new Gtk.CheckButton();
            check.active = selected;
            check.valign = Gtk.Align.CENTER;
            check.tooltip_text = label;
            row.add_suffix(check);
            var access = new Gtk.DropDown.from_strings({"Read Only", "Read and Write", "No Access"});
            access.selected = level == "F" ? 1 : level == "D" ? 2 : 0;
            access.valign = Gtk.Align.CENTER;
            access.tooltip_text = _("Access for ") + label;
            row.add_suffix(access);
            levels[id] = access;
            row.activatable_widget = check;
            accounts.add(row);
            account_rows.add(row);
            assignments[id] = check;
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
                existing = null; snapshot = ""; share_name.editable = true;
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
            finally { loading = false; }
        }
        async void save()
        {
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
                    Dialogs.error(parent_window, _("Select at least one account or enable access for all authenticated users."));
                    return;
                }
            }
            apply.sensitive = stop.sensitive = false;
            try {
                yield manager.share(folder, share_name.text, writable.active, guest.active, users, access, snapshot);
                if (hidden.sensitive) {
                    SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
                    yield helper.set_hidden(share_name.text, hidden.active);
                    hidden_snapshot = hidden.active;
                }
                foreach (var share in (yield manager.inventory(token)))
                    if (share.name == share_name.text)
                        snapshot = share.acl + "|" + share.guest.to_string();
                existing = share_name.text;
                share_name.editable = false;
                address.subtitle = _("smb://") + Environment.get_host_name() + "/" + Uri.escape_string(existing);
                apply.label = _("Apply Changes");
            }
            catch (Error e) { Dialogs.error(parent_window, e.message); }
            apply.sensitive = true;
            stop.sensitive = existing != null;
        }
        async void remove()
        {
            if (existing == null || !(yield Dialogs.confirm(parent_window, "Stop sharing this folder?", "Existing clients may lose access to this share.", "Stop Sharing")))
                return;
            apply.sensitive = stop.sensitive = false;
            try {
                yield manager.remove(existing);
                existing = null;
                snapshot = "";
                address.subtitle = _("Not shared");
                apply.label = _("Share Folder");
                share_name.editable = true;
            }
            catch (Error e) { Dialogs.error(parent_window, e.message); }
            apply.sensitive = true;
            stop.sensitive = existing != null;
        }
    }
    public class SharingDialog : Adw.PreferencesDialog {
        public SharingDialog(Gtk.Window parent, File folder, string? name = null)
        {
            title = "Network Sharing";
            var page = new SharingPage(parent, folder, name);
            add(page);
            closed.connect(page.cancel);
            present(parent);
        }
    }
    public class SharedFoldersDialog : Adw.PreferencesDialog {
        Gtk.Window parent_window;
        Adw.PreferencesGroup group = new Adw.PreferencesGroup();
        Cancellable token = new Cancellable();
        SharingManager manager = new SharingManager();
        Gee.ArrayList<Adw.ActionRow> rows = new Gee.ArrayList<Adw.ActionRow>();
        bool refreshing;
        string fingerprint = "";
        uint monitor;
        public SharedFoldersDialog(Gtk.Window parent)
        {
            title = "Shared Folders";
            parent_window = parent;
            var page = new Adw.PreferencesPage();
            page.add(group);
            add(page);
            var refresh = new Gtk.Button.with_label(_("Refresh Shared Folders"));
            group.add(refresh);
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
                    var row = new Adw.ActionRow();
                    row.title = share.name;
                    row.subtitle = share.path + "\n" + share.address + "\n" + (share.writable ? "Read/write" : "Read-only") + " · " + (share.guest ? "Guests allowed" : "Authentication required") + "\n" + share.acl;
                    var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
                    actions.valign = Gtk.Align.CENTER;
                    actions.append(Browser.button("folder-open-symbolic", _("Open Folder"), () => {
                        AppInfo.launch_default_for_uri_async.begin(File.new_for_path(share.path).get_uri(), null, token, (obj, res) => {
                            try { AppInfo.launch_default_for_uri_async.end(res); }
                            catch (Error e) { Dialogs.error(parent_window, e.message); }
                        });
                    }));
                    actions.append(Browser.button("edit-copy-symbolic", _("Copy Network Address"), () => parent_window.get_clipboard().set_text(share.address)));
                    actions.append(Browser.button("document-properties-symbolic", _("Edit Share"), () => new SharingDialog(parent_window, File.new_for_path(share.path), share.name)));
                    actions.append(Browser.button("process-stop-symbolic", _("Stop Sharing"), () => stop_share.begin(share, row)));
                    row.add_suffix(actions);
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
    }
}
