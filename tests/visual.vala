using MajorisFiles;
int main(string[] args)
{
    try {
        var root = DirUtils.make_tmp("majoris-visual-XXXXXX");
        Environment.set_variable("HOME", root, true);
        Environment.set_variable("XDG_DATA_HOME", Environment.get_variable("MAJORIS_VISUAL_THEME_DATA") ?? root, true);
        Environment.set_variable("XDG_CACHE_HOME", root, true);
        Environment.set_variable("XDG_CONFIG_HOME", Environment.get_variable("MAJORIS_VISUAL_THEME_CONFIG") ?? root, true);
        FileUtils.set_contents(Path.build_filename(root, "notes.txt"), "Majoris Files preview\nA local document.");
        DirUtils.create(Path.build_filename(root, "Documents"), 0700);
        DirUtils.create(Path.build_filename(root, "Pictures"), 0700);
        string configuration="";
        string[] kinds={"DESKTOP","DOCUMENTS","DOWNLOAD","PICTURES","MUSIC","VIDEOS"};
        string[] names={"Desktop","Documents","Downloads","Pictures","Music","Videos"};
        for(int i=0;i<kinds.length;i++){
            DirUtils.create(Path.build_filename(root,names[i]),0700);
            configuration+="XDG_"+kinds[i]+"_DIR=\"$HOME/"+names[i]+"\"\n";
        }
        FileUtils.set_contents(Path.build_filename(root,"user-dirs.dirs"),configuration);
        Environment.set_variable("GDK_BACKEND","x11",true);Environment.set_variable("GSK_RENDERER","cairo",true);Gtk.init();
        Gtk.Settings.get_default().gtk_enable_animations=false;
        Environment.set_prgname("majoris-files-visual-check");
        Environment.set_application_name("Majoris Files Visual Check");
        Adw.init();
        if (Environment.get_variable("MAJORIS_VISUAL_DARK") == "1") Adw.StyleManager.get_default().color_scheme = Adw.ColorScheme.FORCE_DARK;
        var app = new Adw.Application("com.majoris.files.visualtest", ApplicationFlags.NON_UNIQUE);
        app.register(null);
        var metadata = new MetadataStore(Path.build_filename(root, "metadata.db"));
        metadata.set_favorite(File.new_for_path(Path.build_filename(root, "notes.txt")), true);
        Gtk.RecentManager.get_default().add_item(File.new_for_path(Path.build_filename(root, "notes.txt")).get_uri());
        var places = new Places(metadata);
        var operations = new OperationManager(metadata);
        var window = new FilesWindow(app, metadata, places, operations, File.new_for_path(root));
        window.present();
        window.current.set_group("Type");
        var loop = new MainLoop();
        int stage = 0;
        Timeout.add(600, () => { if(stage == 0)
                                 {
                                     screenshot(window, "files-window.png");
                                     window.current.set_view("List");
                                     window.current.set_group("Type");
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 1)
                                 {
                                     screenshot(window, "files-list.png");
                                     window.current.navigate(File.new_for_uri("majoris:///home"));
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 2)
                                 {
                                     screenshot(window, "files-recent.png");
                                     var filters = new SearchFilters(new SearchQuery());
                                     filters.present(window);
                                     Timeout.add(500, () => { screenshot(window, "search-filters.png");
                                                              filters.close();
                                                              return Source.REMOVE;
                                         });
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 3)
                                 {
                                     window.current.navigate(File.new_for_path(root));
                                     window.current.set_view("List");
                                     window.current.show_view_settings();
                                     Timeout.add(500, () => {
                    screenshot(window, "view-settings.png");
                    if(window.visible_dialog != null)
                        window.visible_dialog.close();
                    return Source.REMOVE;
                });
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 4)
                                 {
                                     var items = new Gee.ArrayList<FileItem>();
                                     for(uint i = 0; i < window.current.active_selection.get_n_items(); i++)
                                         items.add((FileItem)window.current.active_selection.get_item(i));
                                     Dialogs.show_properties(window, items, metadata);
                                     Timeout.add(500, () => {
                    screenshot(window, "multi-properties.png");
                    if(window.visible_dialog != null)
                        window.visible_dialog.close();
                    return Source.REMOVE;
                });
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 5)
                                 {
                                     var preferences = new PreferencesDialog(metadata);
                                     preferences.present(window);
                                     Timeout.add(500, () => { screenshot(window, "preferences.png");
                                                              preferences.close();
                                                              return Source.REMOVE;
                                         });
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 6)
                                 {
                                     var shortcuts = new ShortcutsDialog();
                                     shortcuts.present(window);
                                     Timeout.add(500, () => { screenshot(window, "shortcuts.png");
                                                              shortcuts.close();
                                                              return Source.REMOVE;
                                         });
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 7)
                                 {
                                     window.set_default_size(500, 680);
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 8)
                                 {
                                     assert(window.current.narrow);
                                     screenshot(window, "files-narrow.png");
                                     stage++;
                                     return Source.CONTINUE;
                                 }
                                 if(stage == 9)
                                 {
                                     try {
                                         var options = new ChooserOptions(false, new VariantBuilder(VariantType.VARDICT).end());
                                         options.initial = File.new_for_path(root);
                                         var chooser = new ChooserWindow(options, metadata, places);
                                         chooser.set_default_size(1040, 820);
                                         chooser.present();
                                         Timeout.add(500, () => { screenshot(chooser, "file-chooser.png");
                                                                  chooser.cancel_request();
                                                                  window.destroy();
                                                                  loop.quit();
                                                                  return Source.REMOVE;
                                             });
                                     }
                                     catch(Error e) { error("%s", e.message);
                                     }
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
