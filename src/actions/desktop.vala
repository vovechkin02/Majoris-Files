namespace MajorisFiles {
    public class DesktopActions : Object, QuickActionProvider {
        public string provider_id {
            owned get {
                return "desktop";
            }
        }
        public Gee.List<QuickAction> actions(Gee.List<FileItem> selection)
        {
            var result = new Gee.ArrayList<QuickAction>();
            if(selection.size == 1 && selection[0].file.is_native() && selection[0].mime.has_prefix("image/"))
                result.add(new QuickAction("wallpaper", "Set as Wallpaper…"));
            bool attachments = selection.size > 0;
            foreach(var item in selection)
                if(!item.file.is_native() || item.directory)
                    attachments = false;
            if(attachments)
                result.add(new QuickAction("email", "Send by Email…"));
            return result;
        }
        public async void execute(string id, Gee.List<FileItem> selection, Gtk.Window parent) throws Error
        {
            bool allowed = false;
            foreach(var action in actions(selection))
                if(action.id == id)
                    allowed = true;
            if(!allowed)
                throw new FileError.INVALID("This desktop action does not support the selection");
            var portal = new Xdp.Portal();
            var exported = Xdp.parent_new_gtk(parent);
            var token = new Cancellable();
            ulong closing = parent.close_request.connect(() => { token.cancel();
                                                                 return false;
                });
            var app = parent.application;
            if(app != null)
                app.hold();
            try {
                bool accepted;
                if(id == "wallpaper")
                    accepted = yield portal.set_wallpaper(exported, selection[0].file.get_uri(), Xdp.WallpaperFlags.BACKGROUND | Xdp.WallpaperFlags.PREVIEW, token);
                else {
                    string[] paths = {};
                    foreach(var item in selection)
                        paths += item.file.get_path();
                    accepted = yield portal.compose_email(exported, null, null, null, null, null, paths, Xdp.EmailFlags.NONE, token);
                }
                if(!accepted)
                    throw new IOError.CANCELLED("Desktop request was cancelled");
            }
            finally {
                parent.disconnect(closing);
                if(app != null)
                    app.release();
            }
        }
    }
}
