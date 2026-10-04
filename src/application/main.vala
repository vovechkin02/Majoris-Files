namespace MajorisFiles {
    public class Application : Adw.Application, SessionRecorder {
        MetadataStore metadata;
        Places places;
        OperationManager operations;
        FileManagerService? manager;
        uint owner;
        string recovery_session = "";
        string recovery_details = "";
        bool activated_once;
        uint session_save;
        public Application()
        {
            Object(application_id: "com.majoris.files", flags: ApplicationFlags.HANDLES_OPEN);
        }
        protected override void startup()
        {
            base.startup();
            metadata = new MetadataStore();
            if(metadata.state("session-clean", "true") == "false")
            {
                recovery_session = metadata.state("session-last");
                if(metadata.state("session-details-for") == Checksum.compute_for_string(ChecksumType.SHA256, recovery_session))
                    recovery_details = metadata.state("session-details");
            }
            metadata.set_state("session-clean", "false");
            window_added.connect(queue_session_save);
            window_removed.connect(queue_session_save);
            places = new Places(metadata);
            operations = new OperationManager(metadata);
            var action = new SimpleAction("new-window", null);
            action.activate.connect(() => new FilesWindow(this, metadata, places, operations).present());
            add_action(action);
            set_accels_for_action("app.new-window", {"<Control>n"});
            owner = Bus.own_name(BusType.SESSION, "org.freedesktop.FileManager1", BusNameOwnerFlags.NONE, (connection) => { try { manager = new FileManagerService(this, metadata, places, operations);
                                                                                                                                  connection.register_object("/org/freedesktop/FileManager1", manager);
                                                                                                                            }
                                                                                                                            catch(Error e) { warning("FileManager1 registration failed: %s", e.message);
                                                                                                                            }
                });
        }
        protected override void shutdown()
        {
            if(session_save != 0)
            {
                Source.remove(session_save);
                session_save = 0;
            }
            save_session();
            metadata.set_state("session-clean", "true");
            Bus.unown_name(owner);
            base.shutdown();
        }
        protected override void activate()
        {
            if(get_active_window() != null)
            {
                get_active_window().present();
                return;
            }
            if(!activated_once && recovery_session != "" && metadata.state("restore-session", "true") == "true")
            {
                activated_once = true;
                try {
                    var snapshot = Variant.parse(new VariantType("a(a(ss)u)"), recovery_session);
                    Variant? details = null;
                    if(recovery_details != "")
                    {
                        try {
                            details = Variant.parse(new VariantType("aas"), recovery_details);
                        }
                        catch(Error ignored) {}
                    }
                    if(snapshot.n_children() > 32)
                        throw new FileError.INVALID("Too many saved windows");
                    for(size_t i = 0; i < snapshot.n_children(); i++)
                    {
                        var saved = snapshot.get_child_value(i);
                        var pages = saved.get_child_value(0);
                        if(pages.n_children() == 0 || pages.n_children() > 64)
                            continue;
                        var window = new FilesWindow(this, metadata, places, operations, null, true);
                        for(size_t j = 0; j < pages.n_children(); j++)
                        {
                            var page = pages.get_child_value(j);
                            string uri = page.get_child_value(0).get_string();
                            if(Uri.parse_scheme(uri) == null)
                                continue;
                            window.new_tab(File.new_for_uri(uri));
                            window.current.set_view(page.get_child_value(1).get_string());
                            if(details != null && i < details.n_children())
                            {
                                var states = details.get_child_value(i);
                                if(j < states.n_children())
                                {
                                    try {
                                        window.current.restore_session_state(states.get_child_value(j).get_string());
                                    }
                                    catch(Error ignored) {}
                                }
                            }
                        }
                        if(window.tabs.n_pages > 0)
                        {
                            window.tabs.selected_page = window.tabs.get_nth_page((int)uint.min(saved.get_child_value(1).get_uint32(), window.tabs.n_pages - 1));
                            window.present();
                        }
                        else window.destroy();
                    }
                    if(get_windows().length() > 0)
                        return;
                }
                catch(Error e) {
                    warning("Cannot recover browsing session: %s", e.message);
                }
            }
            activated_once = true;
            new FilesWindow(this, metadata, places, operations).present();
        }
        public void queue_session_save()
        {
            if(session_save != 0)
                return;
            session_save = Idle.add(() => { session_save = 0;
                                            save_session();
                                            return Source.REMOVE;
                });
        }
        void save_session()
        {
            var windows = new VariantBuilder(new VariantType("a(a(ss)u)"));
            var details = new VariantBuilder(new VariantType("aas"));
            uint count = 0;
            foreach(var candidate in get_windows())
            {
                var window = candidate as FilesWindow;
                if(window == null || window.tabs.n_pages == 0)
                    continue;
                var tabs = new VariantBuilder(new VariantType("a(ss)"));
                var states = new VariantBuilder(new VariantType("as"));
                for(int i = 0; i < window.tabs.n_pages; i++)
                {
                    var browser = (Browser)window.tabs.get_nth_page(i).child;
                    tabs.add("(ss)", browser.directory.location.get_uri(), browser.view_mode);
                    states.add("s", browser.session_state());
                }
                windows.add_value(new Variant("(@a(ss)u)", tabs.end(), (uint)window.tabs.get_page_position(window.tabs.selected_page)));
                details.add_value(states.end());
                count++;
            }
            if(count > 0)
            {
                var snapshot = windows.end().print(true);
                metadata.set_state("session-details", details.end().print(true));
                metadata.set_state("session-details-for", Checksum.compute_for_string(ChecksumType.SHA256, snapshot));
                metadata.set_state("session-last", snapshot);
            }
        }
        protected override void open(File[] files, string hint)
        {
            foreach (var file in files)
                open_location.begin(file);
        }
        async void open_location(File file)
        {
            hold();
            try {
                var info = yield file.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
                var window = new FilesWindow(this, metadata, places, operations, info.get_file_type() == FileType.DIRECTORY ? file : file.get_parent());
                if(info.get_file_type() != FileType.DIRECTORY)
                    window.current.select_file(file);
                window.present();
            }
            catch(Error e) {
                var window = new FilesWindow(this, metadata, places, operations);
                window.present();
                Dialogs.error(window, e.message);
            }
            finally {
                release();
            }
        }
    }
}
int main(string[] args)
{
    return new MajorisFiles.Application().run(args);
}
