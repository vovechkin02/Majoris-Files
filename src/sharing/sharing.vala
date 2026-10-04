namespace MajorisFiles {
    public class SharePolicy : Object {
        public static bool valid_name(string name)
        {
            if (name.length == 0 || name.length > 80 || name == "." || name == ".." || name.has_prefix("-"))
                return false;
            foreach (char c in name.to_utf8())
                if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == ' '))
                    return false;
            return name.strip() == name;
        }
        public static string acl(bool writable, string[] users) throws Error
        {
            if (users.length == 0)
                return "Everyone:" + (writable ? "F" : "R");
            string result = "";
            foreach (var user in users)
            {
                if (user == "" || user.has_prefix("-") || !Regex.match_simple("^[a-zA-Z0-9_][a-zA-Z0-9_.-]*$", user))
                    throw new FileError.INVALID("Invalid user name");
                if (result != "")
                    result += ",";
                result += user + ":" + (writable ? "F" : "R");
            }
            return result;
        }
        public static string[] arguments(string name, string path, bool writable, bool guest, string[] users) throws Error
        {
            if (!valid_name(name) || !Path.is_absolute(path))
                throw new FileError.INVALID("Invalid share name or path");
            return {
                       "net", "usershare", "add", name, path, "Majoris shared folder", acl(writable, users), guest ? "guest_ok=y" : "guest_ok=n"
            };
        }
    }
    [DBus(name = "com.majoris.Files.Sharing")]
    public interface SharingProxy : Object {
        public abstract async void enable_services() throws DBusError, IOError;
        public abstract async void provision_password(string password) throws DBusError, IOError;
    }
    public class SharingManager : Object {
        public async string invoke(string[] arguments, Cancellable? token = null) throws Error
        {
            var process = new Subprocess.newv(arguments, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string output, errors;
            try {
                yield process.communicate_utf8_async(null, token, out output, out errors);
            }
            catch (Error e) {
                process.force_exit();
                throw e;
            }
            if (!process.get_successful())
                throw new FileError.INVALID(errors.strip() != "" ? errors.strip() : "The Majoris sharing system component needs repair");
            return output;
        }
        public async void share(File folder, string name, bool writable, bool guest, string[] users) throws Error
        {
            if (!folder.is_native())
                throw new FileError.INVALID("Only local folders can be shared");
            var info = yield folder.query_info_async("standard::type,standard::is-symlink,owner::user", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
            if (info.get_file_type() != FileType.DIRECTORY || info.get_is_symlink())
                throw new FileError.INVALID("Select a local folder rather than a symbolic link");
            string path = folder.get_path();
            if (path == "/" || path.has_prefix("/etc") || path.has_prefix("/proc") || path.has_prefix("/sys") || path.has_prefix("/dev") || path.has_prefix("/boot") || path.has_prefix("/root"))
                throw new FileError.INVALID("System folders cannot be shared");
            var args = SharePolicy.arguments(name, path, writable, guest, users);
            SharingProxy helper = yield Bus.get_proxy(BusType.SYSTEM, "com.majoris.Files.Sharing", "/com/majoris/Files/Sharing");
            yield helper.enable_services();
            yield invoke(args);
        }
        public async void remove(string name) throws Error
        {
            if (!SharePolicy.valid_name(name))
                throw new FileError.INVALID("Invalid share name");
            yield invoke({"net", "usershare", "delete", name});
        }
    }
    public class SharingDialog : Adw.PreferencesDialog {
        public SharingDialog(Gtk.Window parent, File folder)
        {
            title = "Network Sharing";
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            group.title = folder.get_basename();
            page.add(group);
            add(page);
            var name = new Adw.EntryRow();
            name.title = "Share Name";
            name.text = folder.get_basename();
            group.add(name);
            var users = new Adw.EntryRow();
            users.title = "Specific Users (comma separated; empty for everyone)";
            group.add(users);
            var writable = new Adw.SwitchRow();
            writable.title = "Allow Creating, Modifying, and Deleting Files";
            group.add(writable);
            var guest = new Adw.SwitchRow();
            guest.title = "Allow Guest Access";
            group.add(guest);
            var address = new Adw.ActionRow();
            address.title = "Network Address";
            address.subtitle_selectable = true;
            group.add(address);
            var manager = new SharingManager();
            var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            var enable = new Gtk.Button.with_label("Share Folder");
            enable.add_css_class("suggested-action");
            var stop = new Gtk.Button.with_label("Stop Sharing");
            buttons.append(enable);
            buttons.append(stop);
            group.add(buttons);
            enable.clicked.connect(() => { enable.sensitive = false;
                                           string[] names = {};
                                           foreach (var user in users.text.split(","))
                                               if (user.strip() != "")
                                                   names += user.strip();
                                           manager.share.begin(folder, name.text, writable.active, guest.active, names, (obj, res) => { enable.sensitive = true;
                                                                                                                                        try { manager.share.end(res);
                                                                                                                                              address.subtitle = "smb://" + Environment.get_host_name() + "/" + Uri.escape_string(name.text);
                                                                                                                                        }
                                                                                                                                        catch (Error e) { Dialogs.error(parent, e.message);
                                                                                                                                        }
                                               });
                });
            stop.clicked.connect(() => manager.remove.begin(name.text, (obj, res) => { try { manager.remove.end(res);
                                                                                             address.subtitle = "Sharing stopped";
                                                                                       }
                                                                                       catch (Error e) { Dialogs.error(parent, e.message);
                                                                                       }
                }));
            present(parent);
        }
    }
}
