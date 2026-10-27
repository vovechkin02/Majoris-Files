using MajorisFiles;

Gtk.Button? sidebar_control(Gtk.Widget widget) {
    if(widget is Gtk.Button && widget.tooltip_text=="Show or Hide Locations")return (Gtk.Button)widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()) {
        var button=sidebar_control(child);if(button!=null)return button;
    }
    return null;
}
async void run_fixture(string output,MainLoop loop) throws Error {
    string root=DirUtils.make_tmp("majoris-integration-XXXXXX");
    var metadata=new MetadataStore(Path.build_filename(root,"state.db"));metadata.set_state("notifications","false");
    foreach(var name in new string[]{"Documents","Downloads","Favorites","Folders","Files","Find","Properties","New Folder","gjpqy ABCDEFGHIJKLMNOPQRSTUVWXYZ"})DirUtils.create(Path.build_filename(root,name),0700);
    FileUtils.set_contents(Path.build_filename(root,"A very long filename that wraps onto two lines and then ellipsises.txt"),"Majoris Files");
    FileUtils.set_contents(Path.build_filename(root,"notes.txt"),"Majoris Files preview");
    // Exercise the unchanged asynchronous thumbnail path with three aspect ratios.
    int[] widths={120,40,80};int[] heights={40,120,80};
    for(int i=0;i<3;i++){var pixels=new Gdk.Pixbuf(Gdk.Colorspace.RGB,false,8,widths[i],heights[i]);pixels.fill(0x6366f1ff);pixels.save(Path.build_filename(root,"image-%d.png".printf(i)),"png");}
    var app=new Adw.Application("com.majoris.files.integration",ApplicationFlags.NON_UNIQUE);app.register(null);
    var window=new FilesWindow(app,metadata,new Places(metadata),new OperationManager(metadata),File.new_for_path(root));
    window.set_default_size(1040,820);window.present();yield pause_layout();
    var browser=window.current;browser.active_selection.select_item(0,true);yield pause_layout();
    yield capture(window,output,"grid-standard");
    browser.navigate(File.new_for_uri("recent:///"));yield pause_layout();yield capture(window,output,"sidebar");
    browser.navigate(File.new_for_path(root));yield pause_layout();browser.active_selection.select_item(0,true);
    assert(browser.sidebar_width==224);
    browser.set_density("Compact");yield pause_layout();yield capture(window,output,"grid-compact");
    browser.set_density("Large");yield pause_layout();yield capture(window,output,"grid-large");
    browser.set_density("Standard");browser.set_group("Type");yield pause_layout();yield capture(window,output,"grouped-grid");
    browser.set_group("None");browser.set_view("List");yield pause_layout();yield capture(window,output,"details-standard");
    browser.set_density("Compact");yield pause_layout();yield capture(window,output,"details-compact");
    foreach(var mode in new string[]{"Columns","Gallery"}) {
        browser.set_density("Standard");browser.set_view(mode);yield pause_layout();yield capture(window,output,mode.down());
        browser.set_density("Compact");yield pause_layout();yield capture(window,output,mode.down()+"-compact");
    }
    browser.set_density("Standard");browser.set_view("Grid");browser.sidebar_width=260;
    window.set_default_size(560,820);yield pause_layout();yield capture(window,output,"narrow-sidebar");assert(browser.narrow);
    if(browser.narrow) {
    var toggle=sidebar_control(window);assert(toggle!=null);toggle.clicked();yield pause_layout();
    yield capture(window,output,"narrow-sidebar-overlay");
    assert(find_component(window,"navigation-sidebar").get_mapped());
    browser.navigate(File.new_for_path(root));yield pause_layout();
    assert(!find_component(window,"navigation-sidebar").get_mapped());
    }
    window.set_default_size(1040,820);yield pause_layout();assert(!browser.narrow);assert(browser.sidebar_width==260);
    yield capture(window,output,"restored-sidebar");
    window.destroy();loop.quit();
}
int main(string[] args) {
    assert(args.length==2);DirUtils.create_with_parents(args[1],0755);
    Gtk.init();Adw.init();Gtk.Settings.get_default().gtk_enable_animations=false;
    if(Environment.get_variable("MAJORIS_VISUAL_DARK")=="1")Adw.StyleManager.get_default().color_scheme=Adw.ColorScheme.FORCE_DARK;
    var loop=new MainLoop();int result=0;
    run_fixture.begin(args[1],loop,(obj,res)=>{try{run_fixture.end(res);}catch(Error e){stderr.printf("%s\n",e.message);result=1;loop.quit();}});loop.run();return result;
}
