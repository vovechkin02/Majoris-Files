namespace MajorisFiles {
    public class NearbyPeer : Object {
        public string id;
        public string name;
        public NearbyPeer(string id, string name)
        {
            this.id = id;
            this.name = name;
        }
    }
    public interface NearbyShareProvider : Object {
        public abstract string provider_id {
            owned get;
        }
        public abstract bool supports(Gee.List<FileItem> selection);
        public abstract async Gee.List<NearbyPeer> discover(Cancellable token) throws Error;
        public abstract async void send(string peer_id, Gee.List<File> files, Cancellable token) throws Error;
    }
    public class NearbyActions : Object, QuickActionProvider {
        NearbyShareProvider provider;
        public NearbyActions(NearbyShareProvider provider)
        {
            this.provider = provider;
        }
        public string provider_id {
            owned get {
                return "nearby-" + provider.provider_id;
            }
        }
        public Gee.List<QuickAction> actions(Gee.List<FileItem> selection)
        {
            var result = new Gee.ArrayList<QuickAction>();
            if(selection.size > 0 && provider.supports(selection))
                result.add(new QuickAction("send", "Send to Nearby Device…"));
            return result;
        }
        public async void execute(string id, Gee.List<FileItem> selection, Gtk.Window parent) throws Error
        {
            if(id != "send" || selection.size == 0 || !provider.supports(selection))
                throw new FileError.INVALID("Unsupported Nearby Share selection");
            var token = new Cancellable();
            ulong closing = parent.close_request.connect(() => { token.cancel();
                                                                 return false;
                });
            var app = parent.application;
            if(app != null)
                app.hold();
            try {
                var peers = yield provider.discover(token);
                if(peers.size == 0)
                    throw new FileError.UNSUPPORTED("No nearby devices are available");
                if(peers.size > 100)
                    throw new FileError.INVALID("Too many nearby devices");
                var names = new Gtk.StringList({});
                foreach(var peer in peers)
                {
                    if(peer.id == "" || !peer.name.validate())
                        throw new FileError.INVALID("Invalid nearby device");
                    names.append(peer.name);
                }
                var target = new Adw.ComboRow();
                target.title = _("Device");
                target.model = names;
                var dialog = new Adw.AlertDialog(_("Send Selected Files?"), "%d selected items will be sent by the installed Nearby Share provider.".printf(selection.size));
                dialog.extra_child = target;
                dialog.add_response("cancel", _("Cancel"));
                dialog.add_response("send", _("Send"));
                dialog.close_response = "cancel";
                if((yield dialog.choose(parent, token)) != "send")
                    return;
                var files = new Gee.ArrayList<File>();
                foreach(var item in selection)
                    files.add(item.file);
                yield provider.send(peers[(int)target.selected].id, files, token);
            }
            finally {
                parent.disconnect(closing);
                if(app != null)
                    app.release();
            }
        }
    }
}
