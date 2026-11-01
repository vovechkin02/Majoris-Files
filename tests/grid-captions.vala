using MajorisFiles;
string fixture;
string evidence;
Adw.ComboRow? caption_control;
Browser? caption_owner;

async void frame(uint delay=100) {Timeout.add(delay,()=>{frame.callback();return Source.REMOVE;});yield;}
async void ready(Browser browser) {
    for(int i=0;i<150&&browser.directory.loading;i++)yield frame();
    assert(!browser.directory.loading);yield frame(180);
}
Gtk.Widget? titled(Gtk.Widget widget,string title) {
    if(widget is Adw.PreferencesRow&&((Adw.PreferencesRow)widget).title==title)return widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=titled(child,title);if(found!=null)return found;}return null;
}
Gtk.ColumnView? details(Gtk.Widget widget) {
    if(widget is Gtk.ColumnView)return (Gtk.ColumnView)widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=details(child);if(found!=null)return found;}return null;
}
Gtk.ColumnViewColumn location_column(Browser browser) {
    var view=details(browser.file_surface);assert(view!=null);
    for(uint i=0;i<view.columns.get_n_items();i++){var column=(Gtk.ColumnViewColumn)view.columns.get_item(i);if(column.title=="Location")return column;}assert_not_reached();
}
void tiles(Gtk.Widget widget,Gee.ArrayList<Gtk.Box> result) {
    if(widget is Gtk.Box&&widget.has_css_class("majoris-data-tile"))result.add((Gtk.Box)widget);
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())tiles(child,result);
}
Gee.ArrayList<Gtk.Box> tile_widgets(Browser browser) {var result=new Gee.ArrayList<Gtk.Box>();tiles(browser.file_surface,result);return result;}
Gtk.Label caption(Gtk.Box tile){return (Gtk.Label)tile.get_first_child().get_next_sibling().get_next_sibling();}
FilenameCell filename(Gtk.Box tile){return (FilenameCell)tile.get_first_child().get_next_sibling();}
void check_captions(Browser browser,string key) {
    int bound=0;
    foreach(var tile in tile_widgets(browser)) {
        var cell=filename(tile);var secondary=caption(tile);
        if(cell.item==null){assert(secondary.label==""&&!secondary.visible);continue;}
        if(!tile.get_mapped())continue;
        bound++;assert(cell.label.label==cell.item.name&&cell.label.visible);
        assert(tile.tooltip_text==cell.item.file.get_parse_name());
        if(key=="None")assert(!secondary.visible&&secondary.label==""&&secondary.height_request==-1);
        else {
            assert(secondary.visible&&!secondary.label.contains("://")&&secondary.label!=cell.item.file.get_parse_name()&&(cell.item.file.get_parent()==null||secondary.label!=cell.item.file.get_parent().get_parse_name()));
            if(key=="Size")assert(secondary.label==(cell.item.directory?"—":Paths.size(cell.item.bytes)));
            if(key=="Type")assert(secondary.label==ContentType.get_description(cell.item.mime));
            if(key=="Modified")assert(secondary.label==new DateTime.from_unix_local((int64)cell.item.info.get_attribute_uint64("time::modified")).format("%x %X"));
        }
    }
    assert(bound>0);
}
async void choose_caption(FilesWindow window,Browser browser,string key) {
    if(caption_owner!=browser){
        browser.show_view_settings();yield frame();caption_control=titled(window,"Grid Metadata Caption") as Adw.ComboRow;caption_owner=browser;
        assert(caption_control!=null&&titled(window,"Location")!=null);
        var dialog=caption_control.get_ancestor(typeof(Adw.PreferencesDialog)) as Adw.PreferencesDialog;assert(dialog!=null);dialog.close();yield frame();
    }
    var row=caption_control;uint selected=uint.MAX;
    for(uint i=0;i<row.model.get_n_items();i++) {
        string name=((Gtk.StringObject)row.model.get_item(i)).get_string();
        assert(name!="Location"&&name!="Name");if(name==key)selected=i;
    }
    assert(selected!=uint.MAX);
    // Keep one native settings control per Browser. Navigation can change the
    // preference without changing this retained control's selected index.
    if(row.selected==selected)row.notify_property("selected");else row.selected=selected;
    yield frame();
}
bool text_exists(Gtk.Widget widget,string text) {
    if(widget is Gtk.Label&&((Gtk.Label)widget).label==text&&widget.get_mapped())return true;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())if(text_exists(child,text))return true;return false;
}
bool group_heading(Gtk.Widget widget) {
    if(widget is Gtk.Label&&widget.has_css_class("heading")&&widget.get_mapped())return true;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())if(group_heading(child))return true;return false;
}
Gtk.GridView? plain_grid(Gtk.Widget widget) {
    if(widget is Gtk.GridView&&widget.get_mapped()&&widget.get_data<GridSlice>("majoris-grid-slice")==null)return (Gtk.GridView)widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=plain_grid(child);if(found!=null)return found;}return null;
}
async void scenario() throws Error {
    var root=File.new_for_path(fixture+"/Documents");root.make_directory();
    var elsewhere=File.new_for_path(fixture+"/Pictures");elsewhere.make_directory();
    for(int i=0;i<6;i++)FileUtils.set_contents(root.get_child("Document-%04d.txt".printf(i)).get_path(),"Grid caption fixture\n"+i.to_string());
    root.get_child("Folder").make_directory();
    var bulk=File.new_for_path(fixture+"/Recycled");bulk.make_directory();
    for(int i=0;i<1200;i++)FileUtils.set_contents(bulk.get_child("Document-%04d.txt".printf(i)).get_path(),"Recycled caption fixture "+i.to_string());
    var image=elsewhere.get_child("Photo.png");var pixels=new Gdk.Pixbuf(Gdk.Colorspace.RGB,false,8,80,60);pixels.fill(0x6655bbff);pixels.save(image.get_path(),"png");
    var document=root.get_child("Document-0000.txt");string database=fixture+"/state.db";
    var metadata=new MetadataStore(database);metadata.set_state("notifications","false");metadata.set_state("thumbnail-policy","Never");metadata.set_state("indexed-search","false");
    metadata.set_favorite(document,true);metadata.set_favorite(image,true);var members=new Gee.ArrayList<File>();members.add(document);members.add(image);var tag=metadata.create_tag("Caption fixtures","",members);
    Gtk.RecentManager.get_default().add_item(document.get_uri());Gtk.RecentManager.get_default().add_item(image.get_uri());
    var query=new SearchQuery();query.text="Document";query.scope="recursive";metadata.save_search("Caption Search",root,query.serialize());
    var columns=new VariantBuilder(new VariantType("a(sbi)"));columns.add("(sbi)","Name",true,180);columns.add("(sbi)","Location",true,320);columns.add("(sbi)","Size",true,120);
    string saved=new Variant("(sbbib@a(sbi))","Type",false,false,128,true,columns.end()).print(true);
    metadata.set_state("display:"+root.get_uri(),saved);metadata.set_state("group:"+root.get_uri(),"Type");metadata.set_state("caption:"+root.get_uri(),"Location");metadata.set_state("unrelated-caption-sentinel","retain");
    var app=new Adw.Application("com.majoris.files.gridcaptions",ApplicationFlags.NON_UNIQUE);app.register(null);
    var window=new FilesWindow(app,metadata,new Places(metadata),new OperationManager(metadata),root);window.set_default_size(1100,800);window.present();var browser=window.current;yield ready(browser);
    Test.message("legacy migration");check_captions(browser,"None");assert(metadata.state("caption:"+root.get_uri())=="None"&&metadata.state("display:"+root.get_uri())==saved&&metadata.state("group:"+root.get_uri())=="Type");
    assert(browser.sort_key=="Type"&&!browser.ascending&&location_column(browser).visible&&location_column(browser).fixed_width==320&&location_column(browser).resizable);
    assert(metadata.state("unrelated-caption-sentinel")=="retain");
    foreach(var tile in tile_widgets(browser))if(tile.get_mapped()){assert(((Gtk.Image)((Gtk.Overlay)tile.get_first_child()).child).pixel_size==128);break;}
    // Real preference controls, navigation and a fresh store/window exercise persistence.
    yield choose_caption(window,browser,"Size");check_captions(browser,"Size");browser.set_group("None");yield frame();window.destroy();yield frame();
    metadata=new MetadataStore(database);window=new FilesWindow(app,metadata,new Places(metadata),new OperationManager(metadata),root);window.set_default_size(1100,800);window.present();browser=window.current;yield ready(browser);check_captions(browser,"Size");assert(metadata.state("caption:"+root.get_uri())=="Size");
    metadata.set_state("caption:"+root.get_uri(),"Location");browser.navigate(root);yield ready(browser);check_captions(browser,"None");browser.set_group("None");yield frame();window.destroy();yield frame();
    metadata=new MetadataStore(database);window=new FilesWindow(app,metadata,new Places(metadata),new OperationManager(metadata),root);window.set_default_size(1100,800);window.present();browser=window.current;yield ready(browser);check_captions(browser,"None");assert(metadata.state("caption:"+root.get_uri())=="None");
    File[] locations={root,File.new_for_uri("recent:///"),File.new_for_uri("majoris:///favorites"),tag.location(),File.new_for_uri("majoris:///search/Caption%20Search")};
    foreach(var location in locations) {
        Test.message("collection %s",location.get_uri());
        browser.set_group("None");yield frame();browser.navigate(location);yield ready(browser);browser.set_view("Grid");browser.set_density("Standard");yield frame();
        foreach(string grouping in new string[]{"None","Type"}) {
            Test.message("group %s",grouping);
            browser.set_group(grouping);yield frame();
            foreach(string key in new string[]{"None","Size","Type","Modified"}) {yield choose_caption(window,browser,key);check_captions(browser,key);}
            yield choose_caption(window,browser,"None");if(grouping!="None")assert(group_heading(browser.file_surface));
        }
        foreach(string mode in new string[]{"List","Grid","Columns","Grid"}){browser.set_view(mode);yield frame();if(mode=="Grid")check_captions(browser,"None");}
        if(browser.virtual_collection){browser.set_view("List");yield frame();assert(location_column(browser).visible);assert(text_exists(browser.file_surface,root.get_path())||text_exists(browser.file_surface,elsewhere.get_path()));browser.set_view("Grid");yield frame();check_captions(browser,"None");}
    }
    Test.message("invalid preferences");
    // Legacy and unknown values are rejected on every collection before binding.
    foreach(var location in new File[]{root,File.new_for_uri("recent:///"),File.new_for_uri("majoris:///favorites"),tag.location()})foreach(string invalid in new string[]{"Location","Unknown caption"}) {
        Test.message("legacy %s %s",location.get_uri(),invalid);browser.set_group("None");yield frame();metadata.set_state("caption:"+location.get_uri(),invalid);browser.navigate(location);yield ready(browser);browser.set_view("Grid");yield frame();check_captions(browser,"None");assert(metadata.state("caption:"+location.get_uri())=="None");
    }
    // A remote-backed model uses the same factory without making network requests.
    browser.set_group("None");yield frame();browser.navigate(root);yield ready(browser);browser.set_group("None");yield choose_caption(window,browser,"None");
    browser.directory.virtual_location(File.new_for_uri("sftp://example.invalid/fixture/"));
    for(int i=0;i<6;i++){var local=root.get_child("Document-%04d.txt".printf(i));browser.directory.items.append(new FileItem(File.new_for_uri("sftp://example.invalid/fixture/"+local.get_basename()),local.query_info(FileItem.ATTRIBUTES,FileQueryInfoFlags.NONE)));}
    yield frame();check_captions(browser,"None");yield choose_caption(window,browser,"Size");check_captions(browser,"Size");
    Test.message("tile recycling");
    // Force virtualisation, retaining old widgets to check cleared unbound cells.
    browser.set_group("None");yield frame();browser.navigate(bulk);yield ready(browser);browser.set_group("None");browser.set_sort("Name",true);yield choose_caption(window,browser,"Size");
    var held=tile_widgets(browser);assert(held.size>0);yield choose_caption(window,browser,"None");var grid=plain_grid(browser.file_surface);assert(grid!=null);grid.scroll_to(1100,Gtk.ListScrollFlags.NONE,null);yield frame(250);check_captions(browser,"None");
    foreach(var tile in held)assert(caption(tile).label==""&&!caption(tile).visible);
    yield choose_caption(window,browser,"Size");check_captions(browser,"Size");grid.scroll_to(0,Gtk.ListScrollFlags.NONE,null);yield frame(250);check_captions(browser,"Size");yield choose_caption(window,browser,"None");
    browser.set_group("Type");yield frame();check_captions(browser,"None");assert(group_heading(browser.file_surface));browser.set_group("None");yield frame();check_captions(browser,"None");
    // Original location navigation and Details sorting/resizing remain operational.
    browser.set_group("None");yield frame();browser.navigate(File.new_for_uri("majoris:///favorites"));yield ready(browser);browser.select_file(document);window.lookup_action("source-folder").activate(null);yield ready(browser);assert(browser.location.equal(root));
    Gtk.CssProvider? theme_css=null;
    foreach(bool dark in new bool[]{false,true}) {
        var theme=Environment.get_variable("MAJORIS_CAPTION_THEME");if(theme!=null){if(theme_css!=null)Gtk.StyleContext.remove_provider_for_display(Gdk.Display.get_default(),theme_css);theme_css=new Gtk.CssProvider();theme_css.load_from_path(theme+"/gtk-4.0/"+(dark?"gtk-dark.css":"gtk.css"));Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),theme_css,Gtk.STYLE_PROVIDER_PRIORITY_USER);}
        Adw.StyleManager.get_default().color_scheme=dark?Adw.ColorScheme.FORCE_DARK:Adw.ColorScheme.FORCE_LIGHT;string prefix=dark?"dark-":"light-";
        for(int i=0;i<4;i++){browser.set_group("None");yield frame();browser.navigate(locations[i]);yield ready(browser);browser.set_view("Grid");browser.set_density("Standard");browser.set_group("None");yield choose_caption(window,browser,"None");check_captions(browser,"None");if(evidence!="")yield capture(window,evidence,prefix+new string[]{"ordinary","recent","favorites","tags"}[i]);}
        browser.set_group("Type");yield frame();check_captions(browser,"None");if(evidence!="")yield capture(window,evidence,prefix+"grouped");
        browser.set_group("None");yield frame();browser.navigate(root);yield ready(browser);browser.set_group("None");yield choose_caption(window,browser,"Size");check_captions(browser,"Size");if(evidence!="")yield capture(window,evidence,prefix+"size");
        browser.navigate(File.new_for_uri("majoris:///favorites"));yield ready(browser);browser.set_group("None");browser.set_view("List");yield frame();
        var view=details(browser.file_surface);for(uint i=0;i<view.columns.get_n_items();i++){var column=(Gtk.ColumnViewColumn)view.columns.get_item(i);column.visible=column.title=="Name"||column.title=="Size"||column.title=="Location";}
        location_column(browser).fixed_width=400;browser.set_sort("Location",true);yield frame();assert(location_column(browser).visible&&location_column(browser).resizable&&browser.sort_key=="Location");
        if(evidence!="")yield capture(window,evidence,prefix+"details-location");
    }
    caption_control=null;caption_owner=null;browser.cancel();window.destroy();
}
int main(string[] args) {
    try{fixture=DirUtils.make_tmp("majoris-grid-captions-XXXXXX");Environment.set_variable("HOME",fixture,true);Environment.set_variable("XDG_CONFIG_HOME",fixture+"/config",true);Environment.set_variable("XDG_DATA_HOME",fixture+"/data",true);Environment.set_variable("XDG_CACHE_HOME",fixture+"/cache",true);}catch(Error e){error("%s",e.message);}
    evidence=Environment.get_variable("MAJORIS_CAPTION_EVIDENCE")??"";Test.init(ref args);Gtk.init();Adw.init();Gtk.Settings.get_default().gtk_enable_animations=false;
    Test.add_func("/grid-captions/preferences-factories-and-collections",()=>{var loop=new MainLoop();scenario.begin((o,r)=>{try{scenario.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});return Test.run();
}
