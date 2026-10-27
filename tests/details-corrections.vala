using MajorisFiles;

class MetadataProbe : Object, ColumnProvider {
    public string title { owned get { return "Metadata probe"; } }
    public string[] samples={"18 bytes","24 bytes","Folder","Plain text document","Modified","Favorites","Files","Format","ABCDEFGHIJKLMNOPQRSTUVWXYZ","gjpqy","10/27/2026 02:41:48 AM","10/27/26","A long metadata value with uppercase ABCDEFGHIJKLMNOPQRSTUVWXYZ and descenders gjpqy"};
    public string text(FileItem item,MetadataStore metadata) {
        int index=0;
        if(item.name[0]>='0' && item.name[0]<='9' && item.name[1]>='0' && item.name[1]<='9')
            index=(item.name[0]-'0')*10+item.name[1]-'0';
        return samples[index%samples.length];
    }
    public int compare(FileItem a,FileItem b,MetadataStore metadata) {return strcmp(text(a,metadata),text(b,metadata));}
}
Gtk.Widget? mapped_family(Gtk.Widget widget,string family) {
    if(!widget.get_mapped())return null;
    if(widget.has_css_class(family))return widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()) {
        var result=mapped_family(child,family);if(result!=null)return result;
    }
    return null;
}
Gtk.Widget? data_row(Gtk.Widget widget) {
    if(!widget.get_mapped())return null;
    if(widget.get_css_name()=="row" && widget.get_first_child()!=null && widget.get_first_child().get_css_name()=="cell")return widget;
    if(widget.get_css_name()=="row" && widget.get_parent() is Gtk.ListView)return widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()) {
        var result=data_row(child);if(result!=null)return result;
    }
    return null;
}
int headings(Gtk.Widget widget) {
    if(!widget.get_mapped())return 0;
    int count=widget is Gtk.Label && widget.has_css_class("heading")?1:0;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())count+=headings(child);
    return count;
}
void input(string[] args) throws Error {
    string stdout,stderr;int status;
    Process.spawn_sync(null,args,null,SpawnFlags.SEARCH_PATH,null,out stdout,out stderr,out status);
    Process.check_wait_status(status);
}
void click(Gtk.Window window,Gtk.Widget widget) throws Error {
    Graphene.Rect bounds;assert(widget.compute_bounds(window,out bounds));
    int scale=widget.get_scale_factor();
    input({"xdotool","mousemove","--sync",((int)(bounds.origin.x+float.min(50,bounds.size.width/2))*scale).to_string(),((int)(bounds.origin.y+bounds.size.height/2)*scale).to_string(),"click","1"});
}
bool keyboard_focus(Gtk.Widget widget) {
    if(!widget.get_mapped())return false;
    if(widget.has_focus && (widget.get_state_flags()&Gtk.StateFlags.FOCUS_VISIBLE)!=0)return true;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())if(keyboard_focus(child))return true;
    return false;
}
void assert_header_lifecycle(Gtk.Widget view,bool grouped,bool baseline) {
    if(baseline)return;
    if(view is Gtk.ColumnView)assert((((Gtk.ColumnView)view).header_factory!=null)==grouped);
    if(view is Gtk.ListView)assert((((Gtk.ListView)view).header_factory!=null)==grouped);
    assert(grouped?headings(view)>0:headings(view)==0);
}
void assert_no_header_gap(Gtk.ColumnView view) {
    var header=view.get_first_child();var row=data_row(view);assert(header!=null&&row!=null);
    Graphene.Rect head_bounds,row_bounds;
    assert(header.compute_bounds(view,out head_bounds));assert(row.compute_bounds(view,out row_bounds));
    assert(head_bounds.size.height==32);
    assert((row_bounds.origin.y-head_bounds.origin.y-head_bounds.size.height).abs()<0.01);
}
async void correction_fixture(string output,MainLoop loop) throws Error {
    bool baseline=Environment.get_variable("MAJORIS_DETAILS_BASELINE")=="1";
    bool themed=Environment.get_variable("MAJORIS_EXPECT_THEME")=="1";
    var probe=new MetadataProbe();
    var root=DirUtils.make_tmp("majoris-details-XXXXXX");var content=Path.build_filename(root,"Files");DirUtils.create(content,0700);
    for(int i=0;i<probe.samples.length;i++)FileUtils.set_contents(Path.build_filename(content,"%02d — %s.txt".printf(i,i==0?"Favorites gjpqy":i==1?"ABCDEFGHIJKLMNOPQRSTUVWXYZ":"Documents")),string.nfill(i==0?18:24,'x'));
    DirUtils.create(Path.build_filename(content,"Folder"),0700);
    var metadata=new MetadataStore(Path.build_filename(root,"state.db"));metadata.set_state("notifications","false");
    var app=new Adw.Application("com.majoris.files.detailscorrections",ApplicationFlags.NON_UNIQUE);app.register(null);
    var window=new FilesWindow(app,metadata,new Places(metadata),new OperationManager(metadata),File.new_for_path(content));window.set_default_size(1200,860);window.present();yield pause_layout();
    input({"xdotool","search","--onlyvisible","--name","^Files$","windowfocus","--sync"});
    var browser=window.current;browser.set_view("List");browser.set_group("None");browser.active_selection.select_item(1,true);yield pause_layout();
    yield capture(window,output,"details-ungrouped");yield capture(window,output,"sidebar-and-details");
    var details=(Gtk.ColumnView)mapped_family(window,"majoris-data-column");assert(details!=null);
    assert_header_lifecycle(details,false,baseline);
    if(themed&&!baseline)assert_no_header_gap(details);
    browser.set_density("Compact");yield pause_layout();yield capture(window,output,"details-compact");browser.set_density("Standard");
    if(baseline){window.destroy();loop.quit();return;}
    if(Environment.get_variable("MAJORIS_DETAILS_METADATA_ONLY")!="1") {
        foreach(var mode in new string[]{"List","Gallery"}) {
            browser.set_view(mode);yield pause_layout();
            var view=mapped_family(window,mode=="List"?"majoris-data-column":"majoris-data-list");
            for(int round=0;round<2;round++)foreach(var grouping in new string[]{"Type","Modified Date","Size","Tags","Recent Date","None"}) {
                browser.set_group(grouping);reset_scroll(window);yield pause_layout();assert_header_lifecycle(view,grouping!="None",baseline);
                if(themed && mode=="List" && grouping=="None")assert_no_header_gap((Gtk.ColumnView)view);
                if(round==0 && grouping=="Type")yield capture(window,output,mode=="List"?"details-grouped":"gallery-grouped");
            }
            yield capture(window,output,mode=="List"?"details-regrouped-none":"gallery-ungrouped");
        }
        browser.set_view("Grid");browser.set_group("Type");yield pause_layout();yield capture(window,output,"grid-grouped");
        browser.set_group("None");yield pause_layout();yield capture(window,output,"grid-ungrouped");
        // Real X11 input exercises GTK's own input-modality and focus machinery.
        foreach(var mode in new string[]{"List","Grid","Columns","Gallery"}) {
            browser.set_view(mode);yield pause_layout();
            var family=mode=="List"?"majoris-data-column":mode=="Grid"?"majoris-data-grid":"majoris-data-list";
            var view=mapped_family(window,family);assert(view!=null);
            var row=mode=="Grid"?find_component(view,"majoris-data-tile"):data_row(view);assert(row!=null);
            click(window,row);yield pause_layout();assert(browser.selected().size>0);
            string selected=browser.selected()[0].file.get_uri();
            yield capture(window,output,(mode=="List"?"details":mode.down())+"-mouse-selected");
            input({"xdotool","key","--clearmodifiers","Down"});yield pause_layout();
            yield capture(window,output,(mode=="List"?"details":mode.down())+"-keyboard-focused");
            assert(keyboard_focus(view));assert(browser.selected().size>0);
            assert(browser.selected()[0].file.get_uri()!=selected);
            var chosen=browser.selected()[0].file;click(window,browser.search_entry);yield pause_layout();
            assert(!keyboard_focus(view));assert(browser.selected().size>0&&browser.selected()[0].file.equal(chosen));
            yield capture(window,output,(mode=="List"?"details":mode.down())+"-unfocused-selected");
            foreach(var next in new string[]{"Grid","List","Columns","Gallery",mode}) {
                browser.set_view(next);yield pause_layout();
                assert(browser.selected().size>0&&browser.selected()[0].file.equal(chosen));
            }
            browser.set_sort("Name",false);yield pause_layout();assert(browser.selected().size>0&&browser.selected()[0].file.equal(chosen));
            browser.set_sort("Name",true);yield pause_layout();
        }
        browser.set_view("List");browser.set_group("Type");browser.navigate(File.new_for_path(content));yield pause_layout();
        assert_header_lifecycle(details,true,baseline);yield capture(window,output,"details-restored-grouped");
        browser.set_group("None");browser.navigate(File.new_for_path(content));yield pause_layout();
        assert_header_lifecycle(details,false,baseline);yield capture(window,output,"details-restored-none");
        if(themed)assert_no_header_gap(details);
    }
    browser.set_view("List");browser.set_group("None");browser.register_column(probe);
    for(uint i=0;i<details.columns.get_n_items();i++) {
        var column=(Gtk.ColumnViewColumn)details.columns.get_item(i);
        column.visible=column.title=="Name"||column.title=="Metadata probe";
        if(column.title=="Metadata probe")column.fixed_width=650;
    }
    browser.active_selection.select_item(1,true);browser.preview.visible=false;yield pause_layout();yield capture(window,output,"details-metadata");
    browser.set_density("Compact");yield pause_layout();yield capture(window,output,"details-metadata-compact");
    if(themed)assert(details.has_css_class("majoris-density-compact"));
    window.destroy();loop.quit();
}
int main(string[] args) {
    assert(args.length==2);DirUtils.create_with_parents(args[1],0755);
    Gtk.init();Adw.init();Gtk.Settings.get_default().gtk_enable_animations=false;
    if(Environment.get_variable("MAJORIS_VISUAL_DARK")=="1")Adw.StyleManager.get_default().color_scheme=Adw.ColorScheme.FORCE_DARK;
    var loop=new MainLoop();int result=0;
    correction_fixture.begin(args[1],loop,(obj,res)=>{try{correction_fixture.end(res);}catch(Error e){stderr.printf("%s\n",e.message);result=1;loop.quit();}});loop.run();return result;
}
