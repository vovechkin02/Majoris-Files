namespace MajorisFiles {
    [DBus(name = "com.majoris.Files.Sharing")]
    public class SharingService : Object {
        public async string get_clients(string share, BusName sender) throws DBusError, IOError
        {
            try {
                if (!Regex.match_simple("^[A-Za-z0-9_][A-Za-z0-9_ -]{0,79}$", share)) throw new DBusError.INVALID_ARGS("Invalid share name");
                yield authorize(sender, "com.majoris.files.sharing.manage");
                var bus = yield Bus.get(BusType.SYSTEM);
                var response = yield bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixUser", new Variant("(s)", sender), new VariantType("(u)"), DBusCallFlags.NONE, 5000, null);
                uint uid = response.get_child_value(0).get_uint32();
                var info = yield File.new_for_path("/var/lib/samba/usershares/" + share).query_info_async("standard::type,standard::is-symlink,unix::uid", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
                if (info.get_file_type() != FileType.REGULAR || info.get_is_symlink() || !info.has_attribute("unix::uid") || info.get_attribute_uint32("unix::uid") != uid)
                    throw new DBusError.ACCESS_DENIED("Connection status is restricted to the usershare owner");
                var process = new Subprocess.newv({"/usr/bin/smbstatus", "--json"}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                uint timeout = Timeout.add_seconds(5, () => { process.force_exit(); return Source.REMOVE; });
                Source? timer = MainContext.default().find_source_by_id(timeout);
                try {
                    uint8[] bytes = new uint8[1024 * 1024 + 1]; size_t count;
                    yield process.get_stdout_pipe().read_all_async(bytes, Priority.DEFAULT, null, out count);
                    if (count >= bytes.length) { process.force_exit(); throw new IOError.NO_SPACE("Samba status exceeds the safety limit"); }
                    yield process.wait_check_async(null); bytes[count] = 0;
                    return SharingClients.filter((string)bytes, share);
                }
                finally { if (timer != null && !timer.is_destroyed()) Source.remove(timeout); }
            }
            catch (DBusError e) { throw e; }
            catch (IOError e) { throw e; }
            catch (Error e) { throw new DBusError.FAILED(e.message); }
        }
        public async void reconcile_firewall(BusName sender) throws DBusError, IOError
        {
            try {
                yield authorize(sender, "com.majoris.files.sharing.manage");
                var process = new Subprocess.newv({"/usr/bin/net", "usershare", "list"}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                string output;
                yield process.communicate_utf8_async(null, null, out output, null);
                if (!process.get_successful()) throw new IOError.FAILED("Could not verify remaining system usershares");
                if (output.strip() == "") yield SharingFirewall.configure(yield Bus.get(BusType.SYSTEM), false);
            }
            catch (Error e) { throw new DBusError.FAILED(e.message); }
        }
        public async void configure_firewall(bool enabled, BusName sender) throws DBusError, IOError
        {
            try {
                yield authorize(sender, "com.majoris.files.sharing.manage");
                yield SharingFirewall.configure(yield Bus.get(BusType.SYSTEM), enabled);
            }
            catch (Error e) { throw new DBusError.FAILED(e.message); }
        }
        async void authorize(BusName sender, string action) throws Error
        {
            var authority = yield Polkit.Authority.get_async(null);
            var subject = new Polkit.SystemBusName(sender);
            var result = yield authority.check_authorization(subject, action, null, Polkit.CheckAuthorizationFlags.ALLOW_USER_INTERACTION, null);
            if (!result.get_is_authorized())
                throw new DBusError.ACCESS_DENIED("Sharing authorization was denied");
        }
        public async void enable_services(BusName sender) throws DBusError, IOError
        {
            try {
                yield authorize(sender, "com.majoris.files.sharing.manage");
                // A fixed service action, never an arbitrary unit/command supplied by the client.
                var connection = yield Bus.get(BusType.SYSTEM);
                yield connection.call("org.freedesktop.systemd1", "/org/freedesktop/systemd1", "org.freedesktop.systemd1.Manager", "StartUnit", new Variant("(ss)", "smbd.service", "replace"), null, DBusCallFlags.NONE, -1, null);
            }
            catch (Error e) {
                throw new DBusError.FAILED(e.message);
            }
        }
        public async void provision_password(string password, BusName sender) throws DBusError, IOError
        {
            try {
                if (password.length == 0 || password.length > 1024 || password.contains("\n") || password.contains("\r"))
                    throw new DBusError.INVALID_ARGS("Invalid SMB password");
                yield authorize(sender, "com.majoris.files.sharing.credentials");
                var connection = yield Bus.get(BusType.SYSTEM);
                var response = yield connection.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "GetConnectionUnixUser", new Variant("(s)", sender), new VariantType("(u)"), DBusCallFlags.NONE, -1, null);
                uint uid = response.get_child_value(0).get_uint32();
                if (uid == 0)
                    throw new DBusError.ACCESS_DENIED("Root SMB credentials cannot be provisioned");
                unowned Posix.Passwd? account = Posix.getpwuid(uid);
                if (account == null)
                    throw new DBusError.INVALID_ARGS("Local account unavailable");
                var process = new Subprocess.newv({"/usr/bin/smbpasswd", "-s", "-a", account.pw_name}, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_SILENCE);
                yield process.communicate_utf8_async(password + "\n" + password + "\n", null, null, null);
                if (!process.get_successful())
                    throw new DBusError.FAILED("SMB account provisioning failed");
            }
            catch (Error e) {
                throw new DBusError.FAILED(e.message);
            }
        }
    }
}
int main(string[] args)
{
    var loop = new MainLoop();
    MajorisFiles.SharingService? service = null;
    Bus.own_name(BusType.SYSTEM, "com.majoris.Files.Sharing", BusNameOwnerFlags.NONE, (connection) => { try { service = new MajorisFiles.SharingService();
                                                                                                              connection.register_object("/com/majoris/Files/Sharing", service);
                                                                                                        }
                                                                                                        catch (Error e) { critical("Sharing service registration failed: %s", e.message);
                                                                                                                          loop.quit();
                                                                                                        }
        }, null, () => loop.quit());
    loop.run();
    return 0;
}
