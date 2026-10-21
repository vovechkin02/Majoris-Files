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
        Adw.ActionRow address = new Adw.ActionRow();
        Adw.PreferencesGroup accounts = new Adw.PreferencesGroup();
        Gee.HashMap<string, Gtk.CheckButton> assignments = new Gee.HashMap<string, Gtk.CheckButton>();
        Gtk.Button apply = new Gtk.Button.with_label("Share Folder");
        Gtk.Button stop = new Gtk.Button.with_label("Stop Sharing");
        string? existing;
        string? requested;
        public SharingPage(Gtk.Window parent, File folder, string? requested = null)
        {
            title = "Sharing";
            icon_name = "folder-remote-symbolic";
            parent_window = parent;
            this.folder = folder;
            this.requested = requested;
            var group = new Adw.PreferencesGroup();
            group.title = folder.get_parse_name();
            group.description = "Network permissions also depend on filesystem permissions. Write access permits creating, modifying and deleting content.";
            add(group);
            share_name.title = "Share Name";
            share_name.text = folder.get_basename();
            group.add(share_name);
            everyone.title = "All Authenticated Users";
            everyone.active = true;
            group.add(everyone);
            writable.title = "Read and Write";
            group.add(writable);
            guest.title = "Allow Guest Access";
            group.add(guest);
            address.title = "Network Address";
            address.subtitle = "Loading sharing state…";
            address.subtitle_selectable = true;
            group.add(address);
            accounts.title = "Allowed Accounts";
            accounts.description = "Select at least one account when access for all authenticated users is disabled. Samba credentials must be configured for each account.";
            add(accounts);
            everyone.notify["active"].connect(() => {
                accounts.sensitive = !everyone.active;
                guest.sensitive = everyone.active;
                if (!everyone.active)
                    guest.active = false;
            });
            accounts.sensitive = false;
            var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            apply.add_css_class("suggested-action");
            buttons.append(apply);
            buttons.append(stop);
            group.add(buttons);
            apply.sensitive = stop.sensitive = false;
            apply.clicked.connect(() => save.begin());
            stop.clicked.connect(() => remove.begin());
            load.begin();
        }
        public void cancel() { token.cancel(); }
        public override void unroot()
        {
            token.cancel();
            base.unroot();
        }
        void account(string id, string label, bool selected)
        {
            var row = new Adw.ActionRow();
            row.title = label;
            var check = new Gtk.CheckButton();
            check.active = selected;
            check.valign = Gtk.Align.CENTER;
            check.tooltip_text = label;
            row.add_suffix(check);
            row.activatable_widget = check;
            accounts.add(row);
            assignments[id] = check;
        }
        async void load()
        {
            try {
                var shares = yield manager.inventory(token);
                ShareRecord? current = null;
                foreach (var share in shares)
                    if (File.new_for_path(share.path).equal(folder) && (requested == null || requested == share.name))
                    { current = share; break; }
                var selected = new Gee.HashSet<string>();
                if (current != null)
                {
                    existing = current.name;
                    share_name.text = current.name;
                    // Changing a share's name would leave two access policies until
                    // deletion succeeds; edit the existing named share atomically.
                    share_name.editable = false;
                    writable.active = current.writable;
                    everyone.active = false;
                    foreach (var entry in current.acl.split(","))
                    {
                        var pair = entry.split(":");
                        if (pair.length != 2 || (pair[1] != "R" && pair[1] != "F"))
                            throw new FileError.UNSUPPORTED("This share has an advanced ACL. Manage it with the system sharing administrator.");
                        if (pair[0] == "Everyone" || pair[0] == "S-1-1-0")
                            everyone.active = true;
                        else
                            selected.add(pair[0]);
                        if ((pair[1] == "F") != current.writable)
                            throw new FileError.UNSUPPORTED("This share has mixed per-account permissions. Manage it with the system sharing administrator.");
                    }
                    if (everyone.active && selected.size > 0)
                        throw new FileError.UNSUPPORTED("This share has an advanced ACL that cannot be edited here safely.");
                    if (!everyone.active && current.guest)
                        throw new FileError.UNSUPPORTED("This share combines guest access with a restricted ACL and cannot be edited here safely.");
                    guest.active = current.guest;
                    address.subtitle = current.address;
                    apply.label = "Apply Changes";
                    stop.sensitive = true;
                }
                else address.subtitle = "Not shared";
                var users = yield AccountDirectory.load(true, token);
                foreach (var user in users)
                    if ((user.id >= 1000 && user.id < 65534) || selected.contains(user.name))
                    {
                        account(user.name, user.label, selected.contains(user.name));
                        selected.remove(user.name);
                    }
                foreach (var id in selected)
                    account(id, id + " (unresolved account; deselect to remove)", true);
                token.set_error_if_cancelled();
                apply.sensitive = true;
            }
            catch (Error e) {
                if (!token.is_cancelled())
                    address.subtitle = "Sharing state unavailable: " + e.message;
            }
        }
        async void save()
        {
            string[] users = {};
            if (!everyone.active)
            {
                foreach (var entry in assignments.entries)
                    if (entry.value.active)
                        users += entry.key;
                if (users.length == 0)
                {
                    Dialogs.error(parent_window, "Select at least one account or enable access for all authenticated users.");
                    return;
                }
            }
            apply.sensitive = stop.sensitive = false;
            try {
                yield manager.share(folder, share_name.text, writable.active, guest.active, users);
                existing = share_name.text;
                share_name.editable = false;
                address.subtitle = "smb://" + Environment.get_host_name() + "/" + Uri.escape_string(existing);
                apply.label = "Apply Changes";
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
                address.subtitle = "Not shared";
                apply.label = "Share Folder";
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
        public SharedFoldersDialog(Gtk.Window parent)
        {
            title = "Shared Folders";
            parent_window = parent;
            var page = new Adw.PreferencesPage();
            page.add(group);
            add(page);
            closed.connect(() => token.cancel());
            refresh.begin();
            present(parent);
        }
        async void refresh()
        {
            try {
                var shares = yield new SharingManager().inventory(token);
                group.description = shares.size == 0 ? "No Samba usershares are configured." : "Current Samba usershares. System smb.conf shares are managed by your administrator.";
                foreach (var share in shares)
                {
                    var row = new Adw.ActionRow();
                    row.title = share.name;
                    row.subtitle = share.path + "\n" + share.address + "\n" + (share.writable ? "Read/write" : "Read-only") + " · " + (share.guest ? "Guests allowed" : "Authentication required") + "\n" + share.acl;
                    var actions = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
                    actions.valign = Gtk.Align.CENTER;
                    actions.append(Browser.button("folder-open-symbolic", "Open Folder", () => {
                        AppInfo.launch_default_for_uri_async.begin(File.new_for_path(share.path).get_uri(), null, token, (obj, res) => {
                            try { AppInfo.launch_default_for_uri_async.end(res); }
                            catch (Error e) { Dialogs.error(parent_window, e.message); }
                        });
                    }));
                    actions.append(Browser.button("edit-copy-symbolic", "Copy Network Address", () => parent_window.get_clipboard().set_text(share.address)));
                    actions.append(Browser.button("document-properties-symbolic", "Edit Share", () => new SharingDialog(parent_window, File.new_for_path(share.path), share.name)));
                    actions.append(Browser.button("process-stop-symbolic", "Stop Sharing", () => stop_share.begin(share, row)));
                    row.add_suffix(actions);
                    group.add(row);
                }
            }
            catch (Error e) { if (!token.is_cancelled()) group.description = "Could not read Samba configuration: " + e.message; }
        }
        async void stop_share(ShareRecord share, Adw.ActionRow row)
        {
            if (!(yield Dialogs.confirm(parent_window, "Stop sharing “" + share.name + "”?", share.path, "Stop Sharing")))
                return;
            row.sensitive = false;
            try { yield new SharingManager().remove(share.name); group.remove(row); }
            catch (Error e) { row.sensitive = true; Dialogs.error(parent_window, e.message); }
        }
    }
}
