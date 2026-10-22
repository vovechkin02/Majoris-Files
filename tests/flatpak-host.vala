using MajorisFiles;
int main(string[] args)
{
    // Backend test host: only the sandbox client uses the public portal API.
    Environment.set_variable("GDK_DEBUG", "no-portals", true);
    Environment.set_variable("ADW_DISABLE_PORTAL", "1", true);
    Environment.set_variable("GDK_BACKEND","x11",true);
    Gtk.init(); Adw.init();
    var loop = new MainLoop(); int status = 1;
    run.begin(args[1], (obj, res) => { try { run.end(res); status = 0; } catch (Error e) { stderr.printf("%s\n", e.message); } loop.quit(); });
    loop.run(); return status;
}
async void run(string root_path) throws Error
{
    var root = File.new_for_path(root_path);
    var selection = root.get_child("selection"); yield selection.make_directory_async(Priority.DEFAULT, null);
    FileUtils.set_contents(selection.get_child("allowed.txt").get_path(), "allowed fixture");
    FileUtils.set_contents(selection.get_child("another.txt").get_path(), "another fixture");
    var secret = root.get_child("private.txt"); FileUtils.set_contents(secret.get_path(), "must remain inaccessible");
    var bus = Bus.get_sync(BusType.SESSION);
    var app = new Adw.Application("com.majoris.Files.FlatpakHost", ApplicationFlags.NON_UNIQUE); app.register(null);
    var backend = new PortalBackend(bus, app);
    uint registration = bus.register_object("/org/freedesktop/portal/desktop", backend);
    bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", new Variant("(su)", "org.freedesktop.impl.portal.desktop.majoris", 0u), null, DBusCallFlags.NONE, 5000, null);
    var acted = new Gee.HashSet<ChooserWindow>();
    File active_root=selection;
    uint poll = Timeout.add(20, () => {
        foreach (var candidate in app.get_windows()) {
            var window = candidate as ChooserWindow;
            if (window == null || acted.contains(window) || window.browser.directory.loading || !window.browser.location.equal(active_root)) continue;
            acted.add(window);
            if (window.title == "cancel") { window.cancel_request(); continue; }
            if (!window.options.save && !window.options.directory)
                for (uint i = 0; i < window.browser.selection.get_n_items(); i++) {
                    var item = (FileItem)window.browser.selection.get_item(i);
                    if (item.name == "allowed.txt" || (window.options.multiple && item.name == "another.txt")) window.browser.selection.select_item(i, !window.options.multiple);
                }
            window.accept_selection.begin();
        }
        return Source.CONTINUE;
    });
    try {
        foreach (var mode in new string[] {"open", "multiple", "save", "folder", "savefiles", "cancel"}) {
            acted.clear();
            var process = new Subprocess.newv({"flatpak", "run", "--user", "com.majoris.PortalTest", mode, selection.get_path(), secret.get_path()}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string output, errors;
            yield process.communicate_utf8_async(null, null, out output, out errors);
            if (!process.get_successful()) throw new IOError.FAILED("Flatpak " + mode + " failed: " + errors);
            stdout.printf("Flatpak %s: selected access verified; unselected file denied\n", mode);
        }
        foreach (var mode in new string[] {"open", "multiple", "save", "folder", "cancel"}) {
            acted.clear();
            var process = new Subprocess.newv({"flatpak", "run", "--user", "--command=gtk-portal-client", "com.majoris.PortalTest", mode, selection.get_path(), secret.get_path()}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            string output, errors; yield process.communicate_utf8_async(null, null, out output, out errors);
            if (!process.get_successful()) throw new IOError.FAILED("GTK Flatpak " + mode + " failed: " + errors);
            stdout.printf("GTK Gtk.FileDialog %s: selected access verified; unselected file denied\n", mode);
        }
        foreach (var name in new string[] {"saved.txt", "gtk-saved.txt", "partA.txt", "partB.txt"}) {
            string data; FileUtils.get_contents(selection.get_child(name).get_path(), out data);
            assert(data == "saved-through-portal");
        }
        string? remote_uri=Environment.get_variable("MAJORIS_REMOTE_URI");
        if(remote_uri!=null){
            var remote=File.new_for_uri(remote_uri);var mount=new MountOperation();
            mount.ask_password.connect(()=>{mount.set_username(Environment.get_variable("MAJORIS_FIXTURE_USER")??"");mount.set_password(Environment.get_variable("MAJORIS_FIXTURE_PASSWORD")??"");mount.set_password_save(PasswordSave.NEVER);mount.reply(MountOperationResult.HANDLED);});
            mount.ask_question.connect(()=>{mount.set_choice(0);mount.reply(MountOperationResult.HANDLED);});
            try{yield remote.mount_enclosing_volume(MountMountFlags.NONE,mount,null);}catch(IOError.ALREADY_MOUNTED e){}
            string? bridge=remote.get_path();if(bridge==null)throw new IOError.NOT_SUPPORTED("Remote Flatpak fixture requires GVfs/FUSE");
            Environment.unset_variable("MAJORIS_FIXTURE_PASSWORD");active_root=remote;
            foreach(bool gtk in new bool[]{false,true})foreach(var mode in new string[]{"open","save"}){
                acted.clear();
                string[] arguments={"flatpak","run","--user"};if(gtk)arguments+="--command=gtk-portal-client";
                foreach(var arg in new string[]{"com.majoris.PortalTest",mode,bridge,secret.get_path()})arguments+=arg;
                var client=new Subprocess.newv(arguments,SubprocessFlags.STDOUT_PIPE|SubprocessFlags.STDERR_PIPE);string output,errors;yield client.communicate_utf8_async(null,null,out output,out errors);
                if(!client.get_successful())throw new IOError.FAILED("Remote Flatpak %s failed: %s".printf(mode,errors));
                stdout.printf("Remote %s Flatpak %s: document grant and unselected-file denial verified\n",gtk?"GTK":"public portal",mode);
            }
            foreach(var name in new string[]{"saved.txt","gtk-saved.txt"}){uint8[] data;yield remote.get_child(name).load_contents_async(null,out data,null);assert((string)data=="saved-through-portal");}
            stdout.printf("PASS: remote Flatpak Save bytes persisted at the SMB destination\n");
        }
    }
    finally { Source.remove(poll); bus.unregister_object(registration); }
}
