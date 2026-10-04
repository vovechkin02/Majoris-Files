using MajorisFiles;
int main(string[] args)
{
    try {
        var root = DirUtils.make_tmp("majoris-visual-XXXXXX");
        Environment.set_variable("XDG_DATA_HOME", root, true);
        Environment.set_variable("XDG_CACHE_HOME", root, true);
        Environment.set_variable("XDG_CONFIG_HOME", root, true);
        FileUtils.set_contents(Path.build_filename(root, "notes.txt"), "Majoris Files preview\nA local document.");
        DirUtils.create(Path.build_filename(root, "Documents"), 0700);
        DirUtils.create(Path.build_filename(root, "Pictures"), 0700);
        Gtk.init();
        Adw.init();
        var app = new Adw.Application("com.majoris.files.visualtest", ApplicationFlags.NON_UNIQUE);
        app.register(null);
        var metadata = new MetadataStore(Path.build_filename(root, "metadata.db"));
        var places = new Places(metadata);
        var operations = new OperationManager(metadata);
        var window = new FilesWindow(app, metadata, places, operations, File.new_for_path(root));
        window.present();
        var loop = new MainLoop();
        int stage = 0;
        Timeout.add(600, () => { if(stage == 0)
                                 {
                                     screenshot(window, "files-window.png");
                                     window.current.set_view("List");
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 1)
                                 {
                                     screenshot(window, "files-list.png");
                                     var options = new ChooserOptions(false, new VariantBuilder(VariantType.VARDICT).end());
                                     options.initial = File.new_for_path(root);
                                     var chooser = new ChooserWindow(options, metadata, places);
                                     chooser.present();
                                     Timeout.add(500, () => { screenshot(chooser, "file-chooser.png");
                                                              chooser.cancel_request();
                                                              window.destroy();
                                                              loop.quit();
                                                              return Source.REMOVE;
                                         });
                                     return Source.REMOVE;
                                 }
                                 return Source.REMOVE;
            });
        loop.run();
        return 0;
    }
    catch(Error e) {
        stderr.printf("%s\n", e.message);
        return 1;
    }
}
void screenshot(Gtk.Window window, string filename)
{
    var paintable = new Gtk.WidgetPaintable(window);
    var snapshot = new Gtk.Snapshot();
    paintable.snapshot(snapshot, window.get_width(), window.get_height());
    var node = snapshot.to_node();
    assert(node != null);
    var renderer = Gsk.Renderer.for_surface(window.get_surface());
    var texture = renderer.render_texture(node, null);
    assert(texture.save_to_png(filename));
    renderer.unrealize();
}
