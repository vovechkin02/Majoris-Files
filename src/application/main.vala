namespace MajorisFiles {
    public class Application : Adw.Application {
        MetadataStore metadata;
        Places places;
        OperationManager operations;
        FileManagerService? manager;
        uint owner;
        public Application()
        {
            Object(application_id: "com.majoris.files", flags: ApplicationFlags.HANDLES_OPEN);
        }
        protected override void startup()
        {
            base.startup();
            metadata = new MetadataStore();
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
            Bus.unown_name(owner);
            base.shutdown();
        }
        protected override void activate()
        {
            new FilesWindow(this, metadata, places, operations).present();
        }
        protected override void open(File[] files, string hint)
        {
            foreach (var file in files)
                open_location.begin(file);
        }
        async void open_location(File file) { hold(); try { var info=yield file.query_info_async("standard::type",FileQueryInfoFlags.NONE,Priority.DEFAULT,null); var window=new FilesWindow(this,metadata,places,operations,info.get_file_type()==FileType.DIRECTORY ? file : file.get_parent()); if(info.get_file_type()!=FileType.DIRECTORY) window.current.select_file(file); window.present(); } catch(Error e) { var window=new FilesWindow(this,metadata,places,operations); window.present(); Dialogs.error(window,e.message); } finally { release(); } }
    }
}
int main(string[] args)
{
    return new MajorisFiles.Application().run(args);
}
