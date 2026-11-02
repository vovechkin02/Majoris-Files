namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/permissions-dialog.ui")]
    public class PermissionsDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        public PermissionsDialog(Gtk.Window owner_window, Gee.List<FileItem> items) {
            var page = new PermissionsPage(owner_window, items);
            add(page); page.applied.connect(() => close()); closed.connect(page.cancel); present(owner_window);
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(PermissionsDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/permissions.ui")]
    public class PermissionsPage : Adw.PreferencesPage {
        private bool template_disposing;
        public signal void applied();
        public void cancel() { token.cancel(); }
        Gee.ArrayList<FileItem> items = new Gee.ArrayList<FileItem>();
        Gtk.Window owner_window;
        Cancellable token = new Cancellable();
        bool managed;
        bool syncing;
        bool acl_safe;
        [GtkChild]
        private unowned Adw.PreferencesGroup basic;
        [GtkChild] private unowned Adw.ActionRow owner_summary;
        [GtkChild] private unowned Adw.ActionRow group_summary;
        Adw.ComboRow[] access = {};
        [GtkChild]
        public unowned Adw.ExpanderRow advanced;
        [GtkChild]
        public unowned Adw.EntryRow files;
        [GtkChild]
        public unowned Adw.EntryRow folders;
        [GtkChild]
        private unowned Adw.EntryRow owner;
        [GtkChild]
        private unowned Adw.EntryRow owning_group;
        [GtkChild]
        private unowned Adw.SwitchRow recursive;
        [GtkChild]
        public unowned Gtk.Button apply;
        Gtk.CheckButton[] checks = {};
        uint file_mask;
        uint folder_mask;
        uint file_value;
        uint folder_value;
        string initial_files = "";
        string initial_folders = "";

        [GtkChild] private unowned Adw.PreferencesGroup account_group;
        [GtkChild] private unowned Adw.PreferencesGroup actions;
        [GtkChild] private unowned Adw.PreferencesGroup extra;
        [GtkChild] private unowned Gtk.Grid matrix;
        [GtkChild] private unowned Adw.ActionRow matrix_row;
        [GtkChild] private unowned Adw.PreferencesGroup ownership;
        [GtkChild] private unowned Adw.PreferencesGroup unavailable;
        [GtkChild] private unowned Adw.ComboRow access_owner;
        [GtkChild] private unowned Adw.ComboRow access_group;
        [GtkChild] private unowned Adw.ComboRow access_others;
        [GtkChild] private unowned Gtk.CheckButton permission_0;
        [GtkChild] private unowned Gtk.CheckButton permission_1;
        [GtkChild] private unowned Gtk.CheckButton permission_2;
        [GtkChild] private unowned Gtk.CheckButton permission_3;
        [GtkChild] private unowned Gtk.CheckButton permission_4;
        [GtkChild] private unowned Gtk.CheckButton permission_5;
        [GtkChild] private unowned Gtk.CheckButton permission_6;
        [GtkChild] private unowned Gtk.CheckButton permission_7;
        [GtkChild] private unowned Gtk.CheckButton permission_8;
        [GtkChild] private unowned Adw.ActionRow enclosed;
        [GtkChild] private unowned Adw.ComboRow owner_picker;
        [GtkChild] private unowned Adw.ComboRow group_picker;
        public PermissionsPage(Gtk.Window owner_window, Gee.List<FileItem> selected, bool managed = false) {
            this.owner_window = owner_window; this.managed = managed;
            foreach (var item in selected) items.add(item);

            owner_summary.subtitle = common_attribute("owner::user");
            group_summary.subtitle = common_attribute("owner::group");
            foreach (var item in items) if (!item.file.is_native() || Paths.is_symlink(item.info) || !item.info.has_attribute("unix::mode") || (item.info.has_attribute("access::can-write") && !item.info.get_attribute_boolean("access::can-write") && item.info.has_attribute("owner::user") && item.info.get_attribute_string("owner::user") != Environment.get_user_name())) {
                unavailable.visible = true; return;
            }

            basic.visible = extra.visible = actions.visible = true;
            access = {access_owner, access_group, access_others};
            checks = {permission_0, permission_1, permission_2, permission_3, permission_4, permission_5, permission_6, permission_7, permission_8};
            for (int i = 0; i < 3; i++) {
                int index = i; var row = access[i];
                row.notify["selected"].connect(() => { if (!syncing && row.selected < 3) change_basic(index, row.selected); });
            }

            bool has_folder = false; foreach (var item in items) has_folder = has_folder || item.directory;
            enclosed.visible = has_folder;

            enclosed.activated.connect(() => { advanced.expanded = true; recursive.active = true; });

            files.text = common_mode(false); folders.text = common_mode(true);
            initial_files = files.text; initial_folders = folders.text;



             matrix_row.title = items.size == 1 && items[0].directory ? _("Folder access bits") : _("File access bits");
            for (int r = 0; r < 3; r++) {
                for (int c = 0; c < 3; c++) {
                    var check = checks[r * 3 + c];
                    check.toggled.connect(() => {
                        if (syncing) return;
                        var field = items.size == 1 && items[0].directory ? folders : files;
                        uint mode = 0; if (!uint.try_parse(field.text, out mode, null, 8)) return;
                        mode &= 07000;
                        for (int j = 0; j < checks.length; j++) if (checks[j].active) mode |= (uint)1 << (8 - j);
                        field.text = "%04o".printf(mode);
                    });
                }
            }

            // Account selectors share the same numeric proposal and remain advanced.

             account_picker.begin(owner_picker, owner, true); account_picker.begin(group_picker, owning_group, false);
              recursive.visible = has_folder;
            if (items.size == 1) { var acl = PropertiesDialog.value_row(_("Edit Access Control List…"), _("Advanced POSIX ACL entries")); acl.activatable = true; acl.activated.connect(() => edit_acl.begin(items[0].file)); advanced.add_row(acl); }

            files.changed.connect(() => mode_changed(false)); folders.changed.connect(() => mode_changed(true));
            owner.changed.connect(update_apply); owning_group.changed.connect(update_apply); recursive.notify["active"].connect(update_apply);
            apply.clicked.connect(() => apply_permissions.begin());
            refresh_controls(); check_acls.begin();
        }
        Gtk.Widget presenter() { return get_ancestor(typeof(Adw.Dialog)) ?? owner_window; }
        public override void unroot() { if (!managed) cancel(); base.unroot(); }
        string common_attribute(string key) {
            string first = items[0].info.get_attribute_string(key) ?? _("Unavailable");
            foreach (var item in items) if ((item.info.get_attribute_string(key) ?? _("Unavailable")) != first) return _("Mixed");
            return first;
        }
        string common_mode(bool directory) {
            string? value = null;
            foreach (var item in items) if (item.directory == directory) {
                string current = "%04o".printf(item.info.get_attribute_uint32("unix::mode") & 07777);
                if (value != null && value != current) return ""; value = current;
            }
            return value ?? (directory ? "0755" : "0644");
        }
        async void check_acls() {
            acl_safe = true;
            try { foreach (var item in items) {
                string acl = yield PermissionService.read_acl(item.file);
                if (Regex.match_simple("(?m)^(default:|mask:|user:[^:]|group:[^:])", acl)) acl_safe = false;
                token.set_error_if_cancelled();
            }} catch (Error e) { acl_safe = false; }
            if (token.is_cancelled()) return;
            basic.description = acl_safe ? _("File execution and special bits are preserved by basic changes. Folders include traversal access.") : _("Extended access rules are present or unavailable. Use Advanced Permissions to change access explicitly.");
            foreach (var row in access) row.sensitive = acl_safe;
            refresh_controls();
        }
        void mode_changed(bool directory) {
            if (syncing) return;
            var field = directory ? folders : files;
            uint value = 0; bool valid = uint.try_parse(field.text, out value, null, 8) && value <= 07777;
            if (directory) { folder_value = value; folder_mask = field.text == initial_folders ? 0 : valid ? 07777 : 0; }
            else { file_value = value; file_mask = field.text == initial_files ? 0 : valid ? 07777 : 0; }
            refresh_controls(); update_apply();
        }
        uint effective(FileItem item) {
            uint value = item.info.get_attribute_uint32("unix::mode") & 07777;
            uint mask = item.directory ? folder_mask : file_mask;
            return (value & ~mask) | ((item.directory ? folder_value : file_value) & mask);
        }
        void refresh_controls() {
            syncing = true;
            for (int index = 0; index < access.length; index++) {
                uint? choice = null;
                foreach (var item in items) {
                    uint mode = effective(item), bits = (mode >> ((2 - index) * 3)) & 7;
                    uint selected = bits == 0 ? 0 : bits == (item.directory ? 5 : 4) ? 1 : bits == (item.directory ? 7 : 6) ? 2 : 3;
                    if ((mode & 07000) != 0 || !acl_safe) selected = 3;
                    if (choice != null && choice != selected) { choice = 4; break; } choice = selected;
                }
                access[index].selected = choice ?? 4;
            }
            var field = items.size == 1 && items[0].directory ? folders : files;
            uint mode = 0; bool valid = uint.try_parse(field.text, out mode, null, 8) && mode <= 07777;
            for (int i = 0; i < checks.length; i++) { checks[i].sensitive = valid; checks[i].active = valid && (mode & ((uint)1 << (8 - i))) != 0; }
            syncing = false;
        }
        void change_basic(int index, uint choice) {
            uint shift = (uint)(2 - index) * 3;
            foreach (bool directory in new bool[] {false, true}) {
                bool present = false; foreach (var item in items) if (item.directory == directory) present = true; if (!present) continue;
                uint mask = (directory ? 7u : 6u) << (int)shift;
                uint bits = (choice == 0 ? 0u : choice == 1 ? (directory ? 5u : 4u) : (directory ? 7u : 6u)) << (int)shift;
                var field = directory ? folders : files; uint current = 0; bool common = uint.try_parse(field.text, out current, null, 8);
                if (directory) { folder_value = (folder_value & ~mask) | bits; folder_mask |= mask; }
                else { file_value = (file_value & ~mask) | bits; file_mask |= mask; }
                if (common) { syncing = true; field.text = "%04o".printf((current & ~mask) | bits); syncing = false; }
            }
            refresh_controls(); update_apply();
        }
        void update_apply() {
            if (syncing) return;
            bool changed = owner.text != "" || owning_group.text != "" || recursive.active;
            foreach (var item in items) if (effective(item) != (item.info.get_attribute_uint32("unix::mode") & 07777)) changed = true;
            if (files.text != "" && !Regex.match_simple("^[0-7]{3,4}$", files.text)) changed = true;
            if (folders.text != "" && !Regex.match_simple("^[0-7]{3,4}$", folders.text)) changed = true;
            apply.sensitive = changed && !token.is_cancelled();
        }
        async void apply_permissions() {
            try {
                uint fm = file_value, dm = folder_value, fmask = file_mask, dmask = folder_mask;
                if (files.text != "") PermissionService.mode(files.text);
                if (folders.text != "") PermissionService.mode(folders.text);
                if (recursive.active) { fm = PermissionService.mode(files.text); dm = PermissionService.mode(folders.text); fmask = dmask = 07777; }
                uint? uid = null; uint? gid = null; uint parsed = 0;
                if (owner.text != "") { if (!Regex.match_simple("^[0-9]+$", owner.text) || !uint.try_parse(owner.text, out parsed) || parsed == uint.MAX) throw new FileError.INVALID("Owner UID must be a non-negative integer"); uid = parsed; }
                if (owning_group.text != "") { if (!Regex.match_simple("^[0-9]+$", owning_group.text) || !uint.try_parse(owning_group.text, out parsed) || parsed == uint.MAX) throw new FileError.INVALID("Group GID must be a non-negative integer"); gid = parsed; }
                if (recursive.active && !(yield Dialogs.confirm(presenter(), "Apply Recursively?", "Apply the file and folder modes to all descendants? This can remove access. Symbolic links are skipped.", "Apply"))) return;
                token.set_error_if_cancelled(); apply.sensitive = false;
                var roots = new Gee.ArrayList<File>(); foreach (var item in items) roots.add(item.file);
                yield PermissionService.apply(roots, fm, dm, recursive.active, uid, gid, token, fmask, dmask);
                for (int i = 0; i < items.size; i++) { var info = yield items[i].file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token); items[i] = new FileItem(items[i].file, info); }
                syncing = true; files.text = common_mode(false); folders.text = common_mode(true); initial_files = files.text; initial_folders = folders.text; owner.text = ""; owning_group.text = ""; recursive.active = false; file_mask = folder_mask = 0;
                owner_summary.subtitle = common_attribute("owner::user"); group_summary.subtitle = common_attribute("owner::group"); syncing = false;
                refresh_controls(); check_acls.begin(); applied();
            } catch (Error e) { if (!token.is_cancelled()) Dialogs.error(presenter(), e.message); }
            finally { update_apply(); }
        }
        async void account_picker(Adw.ComboRow row, Adw.EntryRow numeric, bool users)
        {
            row.subtitle = _("Current: ") + common_attribute(users ? "owner::user" : "owner::group");
            applied.connect(() => row.subtitle = _("Current: ") + common_attribute(users ? "owner::user" : "owner::group"));
            try {
                var accounts = yield AccountDirectory.load(users, token);
                if(token.is_cancelled())
                    return;
                var labels = new Gtk.StringList({_("Keep Current")});
                foreach(var account in accounts)
                    labels.append(account.label);
                row.model = labels;
                row.notify["selected"].connect(() => {
                    if(row.selected == 0)
                        numeric.text = "";
                    else if(row.selected <= accounts.size)
                        numeric.text = accounts[(int)row.selected - 1].id.to_string();
                });
            }
            catch(Error e) {
                if(!token.is_cancelled())
                {
                    row.subtitle = _("Account lookup unavailable; enter a numeric ID above");
                    row.sensitive = false;
                }
            }
        }
        async void edit_acl(File file)
        {
            try {
                var text = yield PermissionService.read_acl(file);
                var dialog = new AclDialog(); var view = dialog.view;
                view.buffer.text = text;
                if((yield dialog.choose(presenter(), token)) == "apply")
                    yield PermissionService.write_acl(file, view.buffer.text);
            }
            catch(Error e) {
                if(!(e is IOError.CANCELLED))
                    Dialogs.error(presenter(), e.message);
            }
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                if (token != null) token.cancel();
                dispose_template(typeof(PermissionsPage));
            }
            base.dispose();
        }
    }
}
