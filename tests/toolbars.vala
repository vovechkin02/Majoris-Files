using MajorisFiles;

Gtk.Widget? tool(Gtk.Widget root, string tooltip) {
    if (root.tooltip_text == tooltip) return root;
    for (var child = root.get_first_child(); child != null; child = child.get_next_sibling()) {
        var found = tool(child, tooltip); if (found != null) return found;
    }
    return null;
}
void click(Gtk.Widget root, string tooltip) {
    var control = tool(root, tooltip) as Gtk.Button;
    assert(control != null && control.sensitive);
    control.clicked();
}
void collect_bars(Gtk.Widget root, Gee.ArrayList<Majoris.Ui.Toolbar> bars) {
    if (root is Majoris.Ui.Toolbar) bars.add((Majoris.Ui.Toolbar)root);
    for (var child = root.get_first_child(); child != null; child = child.get_next_sibling()) collect_bars(child, bars);
}
Gtk.Picture? picture(Gtk.Widget root) {
    if (root is Gtk.Picture) return (Gtk.Picture)root;
    for (var child=root.get_first_child();child!=null;child=child.get_next_sibling()) { var found=picture(child);if(found!=null)return found; }
    return null;
}
void assert_segments(Browser browser, string active) {
    var switcher = find_component(browser, "majoris-toolbar-segmented"); assert(switcher != null);
    int selected = 0;
    for (var child = switcher.get_first_child(); child != null; child = child.get_next_sibling()) {
        assert(child is Gtk.ToggleButton);
        assert(!child.has_css_class("majoris-toolbar-control"));
        if (((Gtk.ToggleButton)child).active) { selected++; if(child.tooltip_text != active) error("Selected segment %s; expected %s; model %s",child.tooltip_text,active,browser.view_mode); }
    }
    assert(selected == 1 && browser.view_mode == active);
}
void geometry(Gtk.Widget widget, bool compact = false) {
    if (Environment.get_variable("MAJORIS_TOOLBAR_GEOMETRY") != "1") return;
    bool large = Environment.get_variable("MAJORIS_TOOLBAR_LARGE_TEXT") == "1";
    int height = widget.get_allocated_height();
    assert(large ? height >= (compact ? 28 : 32) : height == (compact ? 28 : 32));
}
async void respond(FilesWindow window, string value) {
    yield pause_layout();
    var dialog = window.visible_dialog as Adw.AlertDialog; assert(dialog != null);
    ((Gtk.Entry)dialog.extra_child).text = value; dialog.response("apply"); dialog.close();
    yield pause_layout();
    assert(window.visible_dialog == null);
}
Gtk.Button? labelled(Gtk.Widget widget, string text) {
    if(widget is Gtk.Button && ((Gtk.Button)widget).label == text) return (Gtk.Button)widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var found=labelled(child,text);if(found!=null)return found;}
    return null;
}
async void keyboard(FilesWindow window, string key, Gtk.Widget? target = null) throws Error {
    // Re-focusing the X window between adjacent keystrokes restores GTK's
    // remembered focus and is not how a user types Arrow followed by Space.
    if (target != null || !window.is_active) {
        window.title = "Majoris Toolbar Regression";
        var search = new Subprocess.newv({"xdotool","search","--name","^Majoris Toolbar Regression$"},SubprocessFlags.STDOUT_PIPE|SubprocessFlags.STDERR_PIPE);
        string? result; yield search.communicate_utf8_async(null,null,out result,null);
        assert(search.get_successful());
        var focus = new Subprocess.newv({"xdotool","windowfocus","--sync",result.strip()},SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_PIPE);
        yield focus.wait_check_async(null); yield pause_layout();
        if (target != null) { assert(target.grab_focus()); assert(target.has_focus); }
        window.title = "Files";
    }
    var input = new Subprocess.newv({"xdotool","key",key},SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_PIPE);
    yield input.wait_check_async(null); yield pause_layout();
}
bool has_text(Gtk.Widget widget, string text) {
    if(widget is Gtk.Label && ((Gtk.Label)widget).label == text) return true;
    for(var child = widget.get_first_child(); child != null; child = child.get_next_sibling())
        if(has_text(child, text)) return true;
    return false;
}
async void right_click(Gtk.Window window, Gtk.Widget widget) throws Error {
    window.title = "Majoris Context Regression";
    Graphene.Rect bounds; assert(widget.compute_bounds(window, out bounds));
    var search = new Subprocess.newv({"xdotool", "search", "--name", "^Majoris Context Regression$"}, SubprocessFlags.STDOUT_PIPE);
    string? result; yield search.communicate_utf8_async(null, null, out result, null);
    assert(search.get_successful());
    var input = new Subprocess.newv({"xdotool", "mousemove", "--window", result.strip(),
        ((int)(bounds.origin.x + bounds.size.width / 2)).to_string(),
        ((int)(bounds.origin.y + bounds.size.height / 2)).to_string(), "click", "3"}, SubprocessFlags.NONE);
    yield input.wait_check_async(null); yield pause_layout();
}
Gtk.Popover? visible_popup(Gtk.Widget widget) {
    if(widget is Gtk.Popover && widget.visible) return (Gtk.Popover)widget;
    for(var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
        var popup = visible_popup(child); if(popup != null) return popup;
    }
    return null;
}
async void run_toolbar_fixture(string? output) throws Error {
    var folder = File.new_for_path(DirUtils.make_tmp("majoris-toolbar-files-XXXXXX"));
    folder.get_child("child").make_directory();
    FileUtils.set_contents(folder.get_child("alpha.txt").get_path(), "alpha");
    FileUtils.set_contents(folder.get_child("beta.txt").get_path(), "beta");
    var metadata = new MetadataStore(folder.get_child("state.db").get_path()); metadata.set_state("notifications", "false");
    var app = new Adw.Application("com.majoris.files.toolbarcheck", ApplicationFlags.NON_UNIQUE); app.register(null);
    var window = new FilesWindow(app, metadata, new Places(metadata), new OperationManager(metadata), folder);
    if (Environment.get_variable("MAJORIS_TOOLBAR_LARGE_TEXT") == "1") {
        var css = new Gtk.CssProvider();
        css.load_from_string(".toolbar-regression-large-text { font-size: 32px; }");
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER + 2);
        var large_action = (Gtk.Button)tool(window.current,"New Folder");
        large_action.add_css_class("toolbar-regression-large-text");
        ((Gtk.Label)((Gtk.Box)large_action.child).get_last_child()).label = "New Folder gjpqy";
        window.current.search_entry.add_css_class("toolbar-regression-large-text");
    }
    window.set_default_size(1100, 820); window.present(); yield pause_layout();
    var browser = window.current;
    var bars = new Gee.ArrayList<Majoris.Ui.Toolbar>(); collect_bars(browser, bars); assert(bars.size == 2);
    foreach (var bar in bars) {
        assert(!bar.compact && bar.spacing == 0 && bar.divider);
        if (Environment.get_variable("MAJORIS_TOOLBAR_GEOMETRY") == "1")
            assert(Environment.get_variable("MAJORIS_TOOLBAR_LARGE_TEXT") == "1" ? bar.get_allocated_height() >= 40 : bar.get_allocated_height() == 40);
    }
    geometry(tool(browser, "Back")); geometry(browser.search_entry);
    var location = find_component(browser, "majoris-location-bar");
    assert(location != null && !location.has_css_class("majoris-toolbar-control"));
    assert(!browser.path.has_css_class("majoris-toolbar-field"));
    double ratio = (double)location.get_allocated_width() / browser.search_entry.get_allocated_width();
    stdout.printf("Address width %d search width %d ratio %.2f\n", location.get_allocated_width(), browser.search_entry.get_allocated_width(), ratio);
    assert(ratio > 2.8 && ratio < 3.3);
    foreach(int width in new int[]{700, 800, 1100}) {
        window.set_default_size(width, 820); yield pause_layout();
        if(!browser.search_entry.get_mapped()) {
            assert(tool(browser, "Search files (Ctrl+F)").get_mapped());
            continue;
        }
        Graphene.Rect search_bounds;
        assert(browser.search_entry.compute_bounds(window, out search_bounds));
        assert(search_bounds.origin.x + search_bounds.size.width <= window.get_width());
        assert(location.get_allocated_width() > 2.8 * browser.search_entry.get_allocated_width());
    }
    yield right_click(window, location);
    var address_menu = visible_popup(location); assert(address_menu != null);
    assert(has_text(address_menu, "Copy Address") && has_text(address_menu, "Copy Address as Text") && has_text(address_menu, "Edit Address"));
    assert(!has_text(address_menu, "New Folder"));
    if(output != null) {
        yield capture(window, output, "location-context");
        // Popovers use native surfaces and are absent from WidgetPaintable(window).
        var screenshot = new Subprocess.newv({"import", "-window", "root", Path.build_filename(output, "location-menu-native.png")}, SubprocessFlags.NONE);
        yield screenshot.wait_check_async(null);
    }
    address_menu.popdown(); yield pause_layout();
    assert(location.activate_action("address.copy", null));
    assert((yield location.get_clipboard().read_text_async(null)) == browser.location.get_uri());
    assert(location.activate_action("address.text", null));
    assert((yield location.get_clipboard().read_text_async(null)) == browser.location.get_path());
    assert(location.activate_action("address.edit", null));
    assert(browser.path.get_mapped() && browser.path.text == browser.location.get_parse_name());
    yield keyboard(window, "Escape");
    assert(visible_popup(browser.file_surface) == null);
    // Empty sidebar and toolbar surfaces must not route into file operations.
    yield right_click(window, find_component(browser, "navigation-sidebar"));
    assert(visible_popup(browser.file_surface) == null);
    yield keyboard(window, "Escape");
    yield right_click(window, bars[0]);
    assert(visible_popup(browser.file_surface) == null);
    yield keyboard(window, "Escape");
    if (output != null) {
        yield capture(window, output, "standard");
        tool(browser,"Back").grab_focus(); yield keyboard(window,"Tab"); yield capture(window,output,"keyboard-focus");
        window.maximize(); yield pause_layout(); yield capture(window,output,"maximised");
        window.unmaximize(); window.set_default_size(1100,820); yield pause_layout();
    }
    click(browser, "New Folder"); yield respond(window, "made-by-toolbar");
    assert(folder.get_child("made-by-toolbar").query_exists());
    browser.select_file(folder.get_child("alpha.txt")); yield pause_layout();
    click(browser, "Rename"); yield respond(window, "renamed.txt"); assert(folder.get_child("renamed.txt").query_exists());
    browser.select_file(folder.get_child("renamed.txt")); click(browser, "Cut");
    browser.navigate(folder.get_child("child")); yield pause_layout(); click(browser, "Paste"); yield pause_layout();
    assert(folder.get_child("child/renamed.txt").query_exists() && !folder.get_child("renamed.txt").query_exists());
    click(browser, "Back"); yield pause_layout(); assert(browser.location.equal(folder));
    click(browser, "Forward"); yield pause_layout(); assert(browser.location.equal(folder.get_child("child")));
    click(browser, "Parent Folder"); yield pause_layout(); assert(browser.location.equal(folder));
    FileUtils.set_contents(folder.get_child("refresh.txt").get_path(), "refresh"); click(browser, "Refresh"); yield pause_layout();
    browser.select_file(folder.get_child("beta.txt")); click(browser, "Copy");
    browser.navigate(folder.get_child("child")); yield pause_layout(); click(browser, "Paste"); yield pause_layout();
    assert(folder.get_child("child/beta.txt").query_exists());
    browser.select_file(folder.get_child("child/beta.txt")); click(browser, "Move to Trash"); yield pause_layout();
    assert(!folder.get_child("child/beta.txt").query_exists());
    browser.edit_location(); browser.path.text = folder.get_path(); browser.path.activate(); yield pause_layout();
    assert(browser.location.equal(folder));
    browser.edit_location();browser.path.text=folder.get_path()+"/made";yield pause_layout();
    var suggestion=labelled(browser.path,folder.get_child("made-by-toolbar").get_path());assert(suggestion!=null);
    assert(!suggestion.has_css_class("majoris-toolbar-control"));suggestion.clicked();yield pause_layout();
    assert(browser.location.equal(folder.get_child("made-by-toolbar")));browser.navigate(folder);yield pause_layout();
    // Native breadcrumb callbacks retain their navigation destinations.
    var crumb = find_component(browser, "majoris-location-current") as Gtk.Button; assert(crumb != null); crumb.clicked(); yield pause_layout();
    browser.search_entry.text = "refresh"; browser.search_entry.search_changed(); yield pause_layout();
    assert(browser.active_selection.get_n_items() == 1);
    browser.search_entry.text = ""; browser.search_entry.search_changed(); yield pause_layout();
    var options = tool(browser, "Search Options") as Gtk.MenuButton; options.popup(); yield pause_layout(); assert(options.popover.visible); options.popdown();
    foreach (var mode in new string[] {"List", "Columns", "Gallery", "Grid"}) {
        browser.set_view(mode); yield pause_layout(); assert_segments(browser, mode);
    }
    ((Gtk.ToggleButton)tool(browser, "List")).active = true; assert_segments(browser, "List");
    browser.navigate(folder.get_child("child")); yield pause_layout(); browser.navigate(folder); yield pause_layout(); assert_segments(browser, "List");
    yield keyboard(window,"alt+Left",tool(browser,"List")); assert(browser.location.equal(folder.get_child("child")));
    yield keyboard(window,"alt+Right"); assert(browser.location.equal(folder)); assert_segments(browser,"List");
    yield keyboard(window,"Left",tool(browser,"List")); assert(tool(browser,"Grid").has_focus);
    assert(!((SimpleAction)window.lookup_action("quick-preview")).enabled);
    yield keyboard(window,"space"); assert_segments(browser,"Grid"); browser.set_view("List");
    var sort = (Gtk.MenuButton)tool(browser, "Sort"); sort.popup(); yield pause_layout(); assert(sort.popover.visible); sort.popdown();
    window.activate_action("sort-size", null); click(browser, "View Settings"); yield pause_layout(); assert(window.visible_dialog != null); window.visible_dialog.close(); yield pause_layout();
    click(browser, "Preview"); assert(browser.preview.visible); click(browser, "Preview");
    browser.select_file(folder.get_child("child")); window.update_commands(); assert(browser.share_button.sensitive);
    browser.share_button.popup(); yield pause_layout(); assert(browser.share_button.popover.visible); browser.share_button.popdown();
    // Both tab-specific view callbacks and window GActions keep their routing.
    window.new_tab(folder.get_child("child")); yield pause_layout(); var second = window.current;
    second.set_view("Gallery"); assert_segments(second, "Gallery");
    window.tabs.selected_page = window.tabs.get_nth_page(0); yield pause_layout(); assert(window.current == browser); assert_segments(browser, "List");
    window.set_default_size(500,820); yield pause_layout(); assert(browser.narrow);
    assert(tool(browser,"Other Locations and Collections").get_mapped());
    var compact_search = tool(browser,"Search files (Ctrl+F)") as Gtk.MenuButton; assert(compact_search.visible);
    compact_search.popup(); yield pause_layout(); assert(browser.search_entry.get_mapped()); compact_search.popdown();
    var overflow = tool(browser,"File Actions") as Gtk.MenuButton; assert(overflow.visible); overflow.popup(); yield pause_layout(); assert(overflow.popover.visible); overflow.popdown();
    assert(find_component(browser,"majoris-toolbar-segmented").get_mapped());
    if (output != null) yield capture(window,output,"narrow");
    window.set_default_size(1100,820); yield pause_layout(); assert(!browser.narrow && browser.search_entry.get_mapped());
    assert(tool(browser,"Show or Hide Locations") == null);
    browser.toggle_locations(); browser.toggle_locations();
    // Mutate a genuine packaged Toolbar without replacing application callbacks.
    var dynamic_bar = new Majoris.Ui.Toolbar(); var group = dynamic_bar.append_group(); assert(!group.visible);
    var action = new SimpleAction("fixture",null); int calls=0; action.activate.connect(()=>calls++); window.add_action(action);
    var control = new Gtk.Button.with_label("Dynamic"); control.action_name="win.fixture"; group.append_control(control); assert(group.visible);
    bars[1].append_widget(dynamic_bar); control.clicked(); assert(calls==1);
    group.remove_control(control); assert(!group.visible); dynamic_bar.insert_control(control,0); control.clicked(); assert(calls==2);
    var separator=dynamic_bar.append_separator(); assert(!separator.visible);
    var tail=new Gtk.Button.with_label("Tail"); dynamic_bar.append_control(tail); assert(separator.visible);
    dynamic_bar.move_control(tail,0); dynamic_bar.remove_control(tail); assert(!separator.visible);
    control.visible=false; control.visible=true; control.clicked(); assert(calls==3);
    dynamic_bar.remove_control(control); bars[1].remove_control(dynamic_bar);
    // Every chooser variant receives exactly the two shared, reduced toolbars.
    foreach (bool save in new bool[]{false,true}) {
        var opts=new ChooserOptions(save,new VariantBuilder(VariantType.VARDICT).end());opts.initial=folder;
        var chooser=new ChooserWindow(opts,metadata,new Places(metadata));chooser.present();yield pause_layout();
        var chooser_bars=new Gee.ArrayList<Majoris.Ui.Toolbar>();collect_bars(chooser.browser,chooser_bars);assert(chooser_bars.size==2);
        assert(tool(chooser.browser,"New Folder")==null && tool(chooser.browser,"Preview")==null);
        if(output!=null)yield capture(chooser,output,save?"save-chooser":"open-chooser");chooser.cancel_request();
    }
    // Compact native preview controls retain real decoder/rendering semantics.
    var pixels=new Gdk.Pixbuf(Gdk.Colorspace.RGB,false,8,80,40);pixels.fill(0x6366f1ff);
    var image=folder.get_child("image.png");pixels.save(image.get_path(),"png");
    var item=new FileItem(image,image.query_info(FileItem.ATTRIBUTES,FileQueryInfoFlags.NONE));
    var token=new Cancellable(); var image_view=new ImageView(item,Gdk.Texture.from_file(image),token);
    var preview_window=new Gtk.Window();preview_window.default_width=500;preview_window.default_height=400;preview_window.child=image_view;if(Environment.get_variable("MAJORIS_TOOLBAR_LARGE_TEXT")=="1")tool(image_view,"Zoom In").add_css_class("toolbar-regression-large-text");preview_window.present();yield pause_layout();
    geometry(tool(image_view,"Zoom In"),true);click(image_view,"Zoom In");assert(!picture(image_view).can_shrink);click(image_view,"Fit Image");assert(picture(image_view).can_shrink);
    click(image_view,"Rotate Preview Clockwise");yield pause_layout();assert(picture(image_view).paintable.get_intrinsic_width()==40);
    if(output!=null)yield capture(preview_window,output,"image-preview");
    var gif=folder.get_child("animated.gif");FileUtils.set_data(gif.get_path(),Base64.decode("R0lGODlhAQABAIAAAAAAAP///yH5BAAKAAAALAAAAAABAAEAAAICRAEAIfkEAAoAAAAsAAAAAAEAAQAAAgJMAQA7"));
    var gif_item=new FileItem(gif,gif.query_info(FileItem.ATTRIBUTES,FileQueryInfoFlags.NONE));
    var frames=yield PreviewSandbox.run(gif_item,"image-animation",{},token);
    var animation=new AnimatedImageView(frames,token);preview_window.child=animation;yield pause_layout();
    click(animation,"Play or Pause Animation");click(animation,"Zoom In");assert(!picture(animation).can_shrink);click(animation,"Zoom Out");click(animation,"Fit Image");assert(picture(animation).can_shrink);
    if(output!=null)yield capture(preview_window,output,"animation-preview");
    var pdf=folder.get_child("pages.pdf");var surface=new Cairo.PdfSurface(pdf.get_path(),200,200);var context=new Cairo.Context(surface);context.show_text("Page one");context.show_page();context.show_text("Page two");context.show_page();surface.finish();
    var pdf_item=new FileItem(pdf,pdf.query_info(FileItem.ATTRIBUTES,FileQueryInfoFlags.NONE));
    var pdf_view=new PdfView(pdf_item,2,token);if(Environment.get_variable("MAJORIS_TOOLBAR_LARGE_TEXT")=="1")find_component(pdf_view,"majoris-toolbar-metadata").add_css_class("toolbar-regression-large-text");preview_window.child=pdf_view;yield pause_layout();
    var first=picture(pdf_view).paintable;assert(first!=null);click(pdf_view,"Next Page");yield pause_layout();assert(picture(pdf_view).paintable!=first);
    click(pdf_view,"Previous Page");yield pause_layout();click(pdf_view,"Zoom In");yield pause_layout();click(pdf_view,"Zoom Out");yield pause_layout();
    if(output!=null)yield capture(preview_window,output,"pdf-preview");
    token.cancel();preview_window.destroy();browser.cancel();second.cancel();window.destroy();
    stdout.printf("Native toolbar actions, composites, responsive routing, chooser, preview and mutation checks passed\n");
}
int main(string[] args) {
    try {
        var root=DirUtils.make_tmp("majoris-toolbar-env-XXXXXX");Environment.set_variable("HOME",root,true);
        if(Environment.get_variable("MAJORIS_TOOLBAR_GEOMETRY")!="1") {Environment.set_variable("XDG_CONFIG_HOME",root,true);Environment.set_variable("XDG_DATA_HOME",root,true);}
        Environment.set_variable("XDG_CACHE_HOME",root,true);
        Gtk.init();Adw.init();Gtk.Settings.get_default().gtk_enable_animations=false;
        if(Environment.get_variable("MAJORIS_VISUAL_DARK")=="1")Adw.StyleManager.get_default().color_scheme=Adw.ColorScheme.FORCE_DARK;
        string? output=args.length>1?args[1]:null;if(output!=null)DirUtils.create_with_parents(output,0755);
        var loop=new MainLoop();int result=0;
        run_toolbar_fixture.begin(output,(obj,res)=>{try{run_toolbar_fixture.end(res);}catch(Error e){stderr.printf("%s\n",e.message);result=1;}loop.quit();});loop.run();return result;
    }catch(Error e){stderr.printf("%s\n",e.message);return 1;}
}

