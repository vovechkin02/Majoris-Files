namespace MajorisFiles {
    public class FileLaunch : Object {
        public static bool executable(FileItem item)
        {
            return !item.directory && (item.mime == "application/x-desktop" || item.mime == "application/x-executable" || item.mime == "application/x-pie-executable" || (item.info.get_attribute_boolean("access::can-execute") && (item.mime.contains("shellscript") || item.mime.contains("python") || item.mime.contains("perl"))));
        }
        public static async void open(FileItem item, Gtk.Window parent) throws Error
        {
            if(executable(item))
            {
                var dialog = new Adw.AlertDialog(_("Open an executable file?"), "“" + item.name + "” can run code with your account’s permissions. Only run files from a source you trust.");
                dialog.add_response("cancel", _("Cancel"));
                dialog.add_response("open", _("Open With…"));
                if(item.file.is_native())
                    dialog.add_response("run", _("Run"));
                dialog.close_response = "cancel";
                var response = yield dialog.choose(parent, null);
                if(response == "cancel")
                    throw new IOError.CANCELLED("Cancelled");
                if(response == "run")
                {
                    if(item.mime == "application/x-desktop")
                    {
                        var app = new DesktopAppInfo.from_filename(item.file.get_path());
                        if(app == null)
                            throw new FileError.INVALID("Invalid application launcher");
                        app.launch(null, parent.get_display().get_app_launch_context());
                    }
                    else {
                        var info = yield item.file.query_info_async("access::can-execute,standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
                        if(!info.get_attribute_boolean("access::can-execute") || info.get_file_type() != FileType.REGULAR)
                            throw new FileError.INVALID("The selected file is not executable");
                        var launcher = new SubprocessLauncher(SubprocessFlags.NONE);
                        launcher.set_cwd(item.file.get_parent().get_path());
                        launcher.spawnv({item.file.get_path()});
                    }
                    return;
                }
                var launcher = new Gtk.FileLauncher(item.file);
                launcher.always_ask = true;
                yield launcher.launch(parent, null);
                return;
            }
            yield new Gtk.FileLauncher(item.file).launch(parent, null);
        }
    }
}
