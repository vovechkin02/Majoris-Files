namespace MajorisFiles {
    public class PermissionsDialog : Adw.PreferencesDialog {
        Gee.List<FileItem> items;
        Gtk.Window owner_window;
        Cancellable token = new Cancellable();
        public PermissionsDialog(Gtk.Window owner_window, Gee.List<FileItem> items)
        {
            this.owner_window = owner_window;
            this.items = items;
            title = "Permissions";
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            page.add(group);
            add(page);
            var files = new Adw.EntryRow();
            files.title = "File Permissions (octal)";
            files.text = "0644";
            group.add(files);
            var folders = new Adw.EntryRow();
            folders.title = "Folder Permissions (octal)";
            folders.text = "0755";
            group.add(folders);
            foreach(var item in items)
                if(item.info.has_attribute("unix::mode"))
                {
                    if(item.directory)
                        folders.text = "%04o".printf(item.info.get_attribute_uint32("unix::mode") & 0777);
                    else files.text = "%04o".printf(item.info.get_attribute_uint32("unix::mode") & 0777);
                }
            var explanation = new Adw.ActionRow();
            explanation.title = "Read · Write · Execute";
            explanation.subtitle = "4 = read, 2 = write, 1 = execute. Each digit sets owner, group, and others. Folders need execute to enter.";
            group.add(explanation);
            var matrix = new Gtk.Grid();
            matrix.column_spacing = 16;
            matrix.row_spacing = 8;
            group.add(matrix);
            Gtk.CheckButton[] checks = {};
            for(int row = 0; row < 3; row++)
            {
                matrix.attach(new Gtk.Label(new string[] {"Owner", "Group", "Others"}
                    [row]), 0, row, 1, 1);
                for(int column = 0; column < 3; column++)
                {
                    var check = new Gtk.CheckButton.with_label(new string[] {"Read", "Write", "Execute"}
                        [column]);
                    uint bit = (uint)1 << ((2 - row) * 3 + (2 - column));
                    check.active = (uint.parse(files.text, 8) & bit) != 0;
                    checks += check;
                    matrix.attach(check, column + 1, row, 1, 1);
                    check.toggled.connect(() => { uint mode = 0;
                                                  for(int i = 0; i < checks.length; i++)
                                                      if(checks[i].active)
                                                          mode |= (uint)1 << ((2 - i / 3) * 3 + (2 - i % 3));
                                                  files.text = "%04o".printf(mode);
                        });
                }
            }
            var owner = new Adw.EntryRow();
            owner.title = "Owner UID (blank preserves owner)";
            group.add(owner);
            var owning_group = new Adw.EntryRow();
            owning_group.title = "Group GID (blank preserves group)";
            group.add(owning_group);
            var recursive = new Adw.SwitchRow();
            recursive.title = "Apply to Folder Contents";
            group.add(recursive);
            var apply = new Gtk.Button.with_label("Apply Permissions");
            apply.add_css_class("suggested-action");
            group.add(apply);
            apply.clicked.connect(() => apply_permissions.begin(files.text, folders.text, owner.text, owning_group.text, recursive.active, apply));
            if(items.size == 1)
            {
                var acl = new Gtk.Button.with_label("Edit Access Control List…");
                group.add(acl);
                acl.clicked.connect(() => edit_acl.begin(items[0].file));
            }
            closed.connect(() => token.cancel());
            present(owner_window);
        }
        async void apply_permissions(string files, string folders, string owner, string group, bool recursive, Gtk.Button apply)
        {
            try {
                uint file_mode = PermissionService.mode(files), folder_mode = PermissionService.mode(folders);
                uint? uid = null;
                uint? gid = null;
                uint parsed = 0;
                if(owner.strip() != "")
                {
                    if(!Regex.match_simple("^[0-9]+$", owner) || !uint.try_parse(owner, out parsed) || parsed == uint.MAX)
                        throw new FileError.INVALID("Owner UID must be a non-negative integer");
                    uid = parsed;
                }
                if(group.strip() != "")
                {
                    if(!Regex.match_simple("^[0-9]+$", group) || !uint.try_parse(group, out parsed) || parsed == uint.MAX)
                        throw new FileError.INVALID("Group GID must be a non-negative integer");
                    gid = parsed;
                }
                if(recursive && !(yield Dialogs.confirm(owner_window, "Change Permissions Recursively?", "Apply the file and folder modes to all descendants? This can remove access. Symbolic links are skipped.", "Apply")))
                    return;
                var roots = new Gee.ArrayList<File>();
                foreach(var item in items)
                    roots.add(item.file);
                apply.sensitive = false;
                yield PermissionService.apply(roots, file_mode, folder_mode, recursive, uid, gid, token);
                close();
            }
            catch(Error e) {
                if(!(e is IOError.CANCELLED))
                    Dialogs.error(owner_window, e.message);
            }
            finally {
                apply.sensitive = true;
            }
        }
        async void edit_acl(File file)
        {
            try {
                var text = yield PermissionService.read_acl(file);
                var view = new Gtk.TextView();
                view.monospace = true;
                view.buffer.text = text;
                var scroll = new Gtk.ScrolledWindow();
                scroll.height_request = 260;
                scroll.set_child(view);
                var dialog = new Adw.AlertDialog("Access Control List", "Advanced POSIX ACL entries. Changes can remove access.");
                dialog.extra_child = scroll;
                dialog.add_response("cancel", "Cancel");
                dialog.add_response("apply", "Apply ACL");
                dialog.close_response = "cancel";
                if((yield dialog.choose(owner_window, token)) == "apply")
                    yield PermissionService.write_acl(file, view.buffer.text);
            }
            catch(Error e) {
                if(!(e is IOError.CANCELLED))
                    Dialogs.error(owner_window, e.message);
            }
        }
    }
}
