namespace MajorisFiles {
    [DBus(name = "org.freedesktop.FileManager1")]
    public class FileManagerService : Object {
        Gtk.Application application;
        MetadataStore metadata;
        Places places;
        OperationManager operations;
        public FileManagerService(Gtk.Application app, MetadataStore metadata, Places places, OperationManager operations)
        {
            this.application = app;
            this.metadata = metadata;
            this.places = places;
            this.operations = operations;
        }
        public void show_folders(string[] uris, string startup_id) throws DBusError, IOError
        {
            foreach(var uri in uris)
                new FilesWindow(application, metadata, places, operations, File.new_for_uri(uri)).present();
        }
        public void show_items(string[] uris, string startup_id) throws DBusError, IOError
        {
            foreach(var uri in uris)
            {
                var file = File.new_for_uri(uri);
                var window = new FilesWindow(application, metadata, places, operations, file.get_parent() ?? file);
                window.current.select_file(file);
                window.present();
            }
        }
        public async void show_item_properties(string[] uris, string startup_id) throws DBusError, IOError
        {
            var items = new Gee.ArrayList<FileItem>();
            foreach(var uri in uris)
            {
                var file = File.new_for_uri(uri);
                try {
                    var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
                    items.add(new FileItem(file, info));
                }
                catch(Error e) {}
            }
            if(items.size > 0)
            {
                var window = new FilesWindow(application, metadata, places, operations, items[0].file.get_parent());
                window.present();
                Dialogs.show_properties(window, items, metadata, () => { return new PermissionsPage(window, items); }, () => { return new SharingPage(window, items[0].file); }, () => { return new MetadataPage(items[0], metadata); }, () => { return new AssociationsPage(window, items[0]); });
            }
        }
    }
}
