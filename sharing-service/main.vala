namespace MajorisFiles {
    [DBus(name = "com.majoris.Files.Sharing")]
    public class SharingService : Object {
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
