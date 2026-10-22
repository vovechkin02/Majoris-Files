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
    // Transport belongs to an explicitly installed extension. Files provides
    // discovery/confirmation/cancellation, never an invented wireless protocol.
    public class ExternalNearby : Object, NearbyShareProvider {
        ExternalExtension extension;
        public string provider_id {owned get{return extension.id;}}
        public ExternalNearby(ExternalExtension extension){this.extension=extension;}
        public bool supports(Gee.List<FileItem> selection){
            if(!extension.enabled||!("nearby" in extension.capabilities)||selection.size==0||selection.size>1000)return false;
            foreach(var item in selection)if(!item.file.is_native()||item.directory||Paths.is_symlink(item.info))return false;
            return true;
        }
        public async Gee.List<NearbyPeer> discover(Cancellable token) throws Error {
            var reply=yield extension.call("GetNearbyPeers",null,"(a(ss))",token);var values=reply.get_child_value(0);
            if(values.n_children()>100)throw new FileError.INVALID("Too many nearby peers");
            var result=new Gee.ArrayList<NearbyPeer>();var seen=new Gee.HashSet<string>();
            for(size_t i=0;i<values.n_children();i++){var value=values.get_child_value(i);string id=value.get_child_value(0).get_string(),name=value.get_child_value(1).get_string();if(id==""||id.length>200||name==""||name.length>200||!seen.add(id)||name.contains("\n")||name.contains("\r"))throw new FileError.INVALID("Invalid nearby peer");result.add(new NearbyPeer(id,name));}
            return result;
        }
        public async void send(string peer_id,Gee.List<File> files,Cancellable token) throws Error {
            string[] uris={};foreach(var file in files){if(!file.is_native())throw new FileError.UNSUPPORTED("Nearby transfers require materialised local files");uris+=file.get_uri();}
            string operation=(yield extension.call("StartNearbyTransfer",new Variant("(s^as)",peer_id,uris),"(o)",token)).get_child_value(0).get_string();
            if(!operation.has_prefix(extension.object_path=="/"?"/":extension.object_path+"/"))throw new FileError.INVALID("Nearby provider returned an unrelated operation");
            bool complete=false;int64 deadline=get_monotonic_time()+1800*1000000L;
            try{
                while(true){token.set_error_if_cancelled();if(get_monotonic_time()>deadline)throw new IOError.TIMED_OUT("Nearby transfer exceeded its time limit");
                    var status=yield extension.call("GetNearbyTransfer",new Variant("(o)",operation),"(ss)",token);string state=status.get_child_value(0).get_string(),message=status.get_child_value(1).get_string();
                    if(message.length>4096)throw new FileError.INVALID("Oversized nearby transfer status");
                    if(state=="completed"){complete=true;return;}if(state=="error")throw new IOError.FAILED(message);if(state=="cancelled")throw new IOError.CANCELLED("Nearby transfer cancelled");if(state!="running")throw new FileError.INVALID("Invalid nearby transfer status");
                    Timeout.add(200,()=>{send.callback();return Source.REMOVE;});yield;
                }
            }finally{if(!complete)try{yield extension.call("CancelNearbyTransfer",new Variant("(o)",operation),"()",null);}catch(Error ignored){}}
        }
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
