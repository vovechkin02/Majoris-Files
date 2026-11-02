using MajorisFiles;
string output;
class MenuCloud : Object, CloudFileProvider {
    File location;
    public File root { get { return location; } }
    public MenuCloud(File location) { this.location = location; }
    public async CloudFileState query(File file, Cancellable token) throws Error {
        var state = new CloudFileState(); state.state = "online-only"; state.capabilities = {"pin"}; return state;
    }
    public async File perform(File file, string action, uint64 maximum_bytes, Cancellable token, CloudProgress? progress = null) throws Error { throw new IOError.NOT_SUPPORTED("Menu fixture only"); }
}
string[] labels(MenuModel model, bool recursive = true) {
    string[] result = {};
    for (int i = 0; i < model.get_n_items(); i++) {
        assert(model.get_item_attribute_value(i, "icon", null) == null);
        var label = model.get_item_attribute_value(i, "label", VariantType.STRING);
        if (label != null) result += label.get_string();
        var section = model.get_item_link(i, Menu.LINK_SECTION);
        if (section != null) { assert(section.get_n_items() > 0); foreach (var text in labels(section, recursive)) result += text; }
        var sub = model.get_item_link(i, Menu.LINK_SUBMENU);
        if (sub != null) { assert(sub.get_n_items() > 0); if (recursive) foreach (var text in labels(sub)) result += text; }
    }
    return result;
}
Gtk.PopoverMenu? file_popup(Gtk.Widget widget) {
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) if (c is Gtk.PopoverMenu) return (Gtk.PopoverMenu)c;
    return null;
}
Gtk.Widget? menu_label(Gtk.Widget widget, string text) {
    if (widget is Gtk.Label && ((Gtk.Label)widget).label == text && widget.get_mapped()) return widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = menu_label(c, text); if (found != null) return found; } return null;
}
Gtk.MenuButton? menu_button(Gtk.Widget widget, string icon) {
    if (widget is Gtk.MenuButton && ((Gtk.MenuButton)widget).icon_name == icon) return (Gtk.MenuButton)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = menu_button(c, icon); if (found != null) return found; } return null;
}
void verify_arrows(Gtk.Widget widget) {
    if (widget.get_css_name() == "arrow" && widget.get_mapped()) assert(widget.get_width() == 0);
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) verify_arrows(c);
}
Gtk.ListBoxRow? place_row(Gtk.Widget widget) {
    if (widget is Gtk.ListBoxRow && widget.get_data<Place>("majoris-place") != null && widget.get_data<Place>("majoris-place").system) return (Gtk.ListBoxRow)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = place_row(c); if (found != null) return found; } return null;
}
Gtk.ListBoxRow? destination_row(Gtk.Widget widget,string uri) {
    if(widget is Gtk.ListBoxRow){var place=widget.get_data<Place>("majoris-place");if(place!=null&&(uri=="tag"?place.tag!=null:place.file.get_uri()==uri))return (Gtk.ListBoxRow)widget;}
    for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling()){var found=destination_row(c,uri);if(found!=null)return found;}return null;
}
Gtk.MenuButton? tooltip_menu(Gtk.Widget widget,string tooltip){if(widget is Gtk.MenuButton&&widget.tooltip_text==tooltip)return (Gtk.MenuButton)widget;for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling()){var found=tooltip_menu(c,tooltip);if(found!=null)return found;}return null;}
Gtk.Button? labelled_button(Gtk.Widget widget,string label){if(widget is Gtk.Button&&((Gtk.Button)widget).label==label)return (Gtk.Button)widget;for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling()){var found=labelled_button(c,label);if(found!=null)return found;}return null;}
Gtk.ProgressBar? progress_bar(Gtk.Widget widget){if(widget is Gtk.ProgressBar)return (Gtk.ProgressBar)widget;for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling()){var found=progress_bar(c);if(found!=null)return found;}return null;}
Gtk.Button? command_button(Gtk.Widget widget,string action){if(widget is Gtk.Button&&((Gtk.Button)widget).action_name==action)return (Gtk.Button)widget;for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling()){var found=command_button(c,action);if(found!=null)return found;}return null;}
Gtk.Entry? prompt_entry(Gtk.Widget widget){if(widget is Gtk.Entry)return (Gtk.Entry)widget;for(var c=widget.get_first_child();c!=null;c=c.get_next_sibling()){var found=prompt_entry(c);if(found!=null)return found;}return null;}
void dismiss_popovers(Gtk.Widget widget) {
    var c = widget.get_first_child();
    while (c != null) { var next = c.get_next_sibling(); dismiss_popovers(c); c = next; }
    if (widget is Gtk.Popover) ((Gtk.Popover)widget).popdown();
}
Gtk.Widget? file_view(Gtk.Widget widget) {
    if (widget is Gtk.GridView && widget.get_mapped()) return widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = file_view(c); if (found != null) return found; } return null;
}
FilenameCell? file_cell(Gtk.Widget widget, string name) {
    if (widget is FilenameCell && widget.get_mapped() && ((FilenameCell)widget).item != null && ((FilenameCell)widget).item.name == name) return (FilenameCell)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = file_cell(c, name); if (found != null) return found; } return null;
}
Adw.PreferencesRow? preference(Gtk.Widget widget, string title) {
    if (widget is Adw.PreferencesRow && ((Adw.PreferencesRow)widget).title == title) return (Adw.PreferencesRow)widget;
    for (var c = widget.get_first_child(); c != null; c = c.get_next_sibling()) { var found = preference(c, title); if (found != null) return found; } return null;
}
async void screenshot(string name) throws Error {
    if (output == "") return;
    yield pause_layout();
    var path = Path.build_filename(output, name);
    var grab = new Subprocess.newv({"xwd", "-silent", "-root", "-out", path + ".xwd"}, SubprocessFlags.NONE); yield grab.wait_check_async(null);
    var convert = new Subprocess.newv({"magick", path + ".xwd", path + ".png"}, SubprocessFlags.NONE); yield convert.wait_check_async(null); FileUtils.unlink(path + ".xwd");

}
void scroll_bottom(Gtk.Widget widget){if(widget is Gtk.ScrolledWindow){var adjustment=((Gtk.ScrolledWindow)widget).vadjustment;adjustment.value=adjustment.upper-adjustment.page_size;}for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling())scroll_bottom(child);}
async void capture_popup(Gtk.Window window,Gtk.Popover popup,string name) throws Error {
    if(output=="")return;yield pause_layout();var contents=popup.get_first_child();assert(contents!=null&&contents.get_mapped());
    var paintable=new Gtk.WidgetPaintable(contents);var snapshot=new Gtk.Snapshot();paintable.snapshot(snapshot,contents.get_allocated_width(),contents.get_allocated_height());var node=snapshot.to_node();assert(node!=null);
    var renderer=Gsk.Renderer.for_surface(window.get_surface());var texture=renderer.render_texture(node,null);assert(texture.save_to_png(Path.build_filename(output,name+".png")));renderer.unrealize();
}
async void capture_empty_click(FilesWindow window, Browser browser) throws Error {
    var search = new Subprocess.newv({"xdotool", "search", "--onlyvisible", "--name", "^Files$"}, SubprocessFlags.STDOUT_PIPE);
    string? ids; yield search.communicate_utf8_async(null, null, out ids, null);
    assert(search.get_successful());
    Graphene.Rect bounds; assert(browser.file_surface.compute_bounds(window, out bounds));
    var click = new Subprocess.newv({"xdotool", "windowfocus", "--sync", ids.strip(), "mousemove", "--window", ids.strip(),
        ((int)(bounds.origin.x + bounds.size.width / 2)).to_string(), ((int)(bounds.origin.y + bounds.size.height - 40)).to_string(), "click", "3"}, SubprocessFlags.NONE);
    yield click.wait_check_async(null); yield pause_layout();
}
async void scenarios() throws Error {
    var app_menu=FilesWindow.application_menu();assert(app_menu.get_n_items()==2);
    string[] expected={"app.new-window","win.new-tab","win.reopen","win.preferences","win.shortcuts","win.about"};
    for(int section=0;section<2;section++){var entries=app_menu.get_item_link(section,Menu.LINK_SECTION);assert(entries!=null&&entries.get_n_items()==3);for(int i=0;i<3;i++){assert(entries.get_item_link(i,Menu.LINK_SUBMENU)==null);assert(entries.get_item_attribute_value(i,"action",VariantType.STRING).get_string()==expected[section*3+i]);}}
    var application_labels=labels(app_menu);string[] expected_labels={"New Window","New Tab","Reopen Closed Tab","Preferences…","Keyboard Shortcuts","About Files"};assert(application_labels.length==6);for(int i=0;i<6;i++)assert(application_labels[i]==expected_labels[i]);

    var folder = File.new_for_path(DirUtils.make_tmp("majoris-menu-fixture-XXXXXX"));
    FileUtils.set_contents(folder.get_child("document.txt").get_path(), "text");
    FileUtils.set_contents(folder.get_child("archive.zip").get_path(), "archive menu fixture");
    yield folder.get_child("Folder").make_directory_async(Priority.DEFAULT, null);
    var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 16, 16); surface.write_to_png(folder.get_child("image.png").get_path());
    var metadata = new MetadataStore(Path.build_filename(DirUtils.make_tmp("majoris-menu-state-XXXXXX"), "state.db")); metadata.set_state("notifications", "false");
    var app = new Adw.Application("com.majoris.files.menucheck", ApplicationFlags.NON_UNIQUE); app.register(null);var new_window=new SimpleAction("new-window",null);app.add_action(new_window);app.set_accels_for_action("app.new-window",{"<Control>n"});
    var operations=new OperationManager(metadata);
    var window = new FilesWindow(app, metadata, new Places(metadata), operations, folder); window.present();
    var browser = window.current; while (browser.directory.loading) yield pause_layout(); yield pause_layout();
    if(Environment.get_variable("MAJORIS_MENU_APPLICATION_ONLY")=="1"){
        foreach(bool dark in new bool[]{false,true}){
            Adw.StyleManager.get_default().color_scheme=dark?Adw.ColorScheme.FORCE_DARK:Adw.ColorScheme.FORCE_LIGHT;
            var theme=Environment.get_variable("MAJORIS_MENU_THEME");if(theme!=null){var css=new Gtk.CssProvider();css.load_from_path(theme+"/gtk-4.0/"+(dark?"gtk-dark.css":"gtk.css"));Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),css,Gtk.STYLE_PROVIDER_PRIORITY_USER);}
            yield pause_layout();var button=menu_button(window,"open-menu-symbolic");assert(button!=null);Graphene.Rect bounds;assert(button.compute_bounds(window,out bounds));
            var click=new Subprocess.newv({"xdotool","search","--onlyvisible","--name","^Files$","mousemove","--window","%@",((int)(bounds.origin.x+bounds.size.width/2)).to_string(),((int)(bounds.origin.y+bounds.size.height/2)).to_string(),"click","1"},SubprocessFlags.NONE);yield click.wait_check_async(null);yield pause_layout();
            Test.message("Application popup %dx%d mapped=%s",button.popover.get_width(),button.popover.get_height(),button.popover.get_mapped().to_string());assert(button.popover.get_mapped());
            string suffix=dark?"-dark":"-light";string name="application"+suffix;yield capture_popup(window,button.popover,name);
            if(output!=""){var tree=new Json.Builder();record_tree(button.popover,tree);var generator=new Json.Generator();generator.set_root(tree.get_root());generator.pretty=true;FileUtils.set_contents(Path.build_filename(output,name+".json"),generator.to_data(null));}
            button.popdown();yield pause_layout();
            var context=file_popup(browser.file_surface);var model=new Menu();window.populate_context(model,browser);context.menu_model=model;Gdk.Rectangle anchor={browser.file_surface.get_width()/2,browser.file_surface.get_height()/3,1,1};context.pointing_to=anchor;context.popup();yield pause_layout();yield capture_popup(window,context,"empty"+suffix);context.popdown();yield pause_layout();
            var progress=FileOperationsPresentation.get_window(operations);progress.present();yield pause_layout();yield capture(progress,output,"operations-no-recovery"+suffix);progress.close();yield pause_layout();
            window.lookup_action("preferences").activate(null);yield pause_layout();var preferences=window.visible_dialog as Adw.PreferencesDialog;assert(preferences!=null);var sharing=preference(preferences,"Shared Folders…");preferences.visible_page=(Adw.PreferencesPage)sharing.get_ancestor(typeof(Adw.PreferencesPage));yield pause_layout();scroll_bottom(preferences.visible_page);yield screenshot("preferences-network"+suffix);preferences.close();yield pause_layout();
        }window.destroy();return;
    }
    assert(!window.lookup_action("reopen").enabled);
    window.templates_available=true;window.update_commands();var template_menu=new Menu();window.populate_context(template_menu,browser);assert("New Document from Template…" in labels(template_menu)&&window.lookup_action("templates").enabled);window.templates_available=false;window.update_commands();assert(!window.lookup_action("templates").enabled);

    window.lookup_action("new-tab").activate(null);yield pause_layout();window.lookup_action("close-tab").activate(null);yield pause_layout();assert(window.lookup_action("reopen").enabled);
    window.lookup_action("reopen").activate(null);yield pause_layout();assert(!window.lookup_action("reopen").enabled);window.lookup_action("close-tab").activate(null);yield pause_layout();
    browser=window.current;
    browser.active_selection.unselect_all();window.update_commands();assert(!window.lookup_action("select-none").enabled);
    window.lookup_action("select-all").activate(null);assert(browser.selected().size==4);window.lookup_action("invert-selection").activate(null);assert(browser.selected().size==0);
    string default_hidden=metadata.state("show-hidden","false");browser.toggle_hidden();assert(metadata.state("show-hidden","false")==default_hidden);browser.toggle_hidden();
    var progress_fixture=new Job("Progress fixture");operations.jobs.append(progress_fixture);var operations_control=FileOperationsPresentation.get_window(operations);operations_control.present();yield pause_layout();var cancel_button=labelled_button(operations_control,"Cancel");var retry_button=labelled_button(operations_control,"Retry Remaining Items");var bar=progress_bar(operations_control);assert(cancel_button!=null&&retry_button!=null&&bar!=null);progress_fixture.progress=0.4;yield pause_layout();assert(bar.fraction==0.4);cancel_button.activate();yield pause_layout();assert(progress_fixture.cancellable.is_cancelled());progress_fixture.done=true;progress_fixture.can_retry=true;assert(!cancel_button.sensitive&&retry_button.visible&&retry_button.sensitive);operations_control.close();operations.jobs.remove_all();
    var isolated_trash=folder.get_child("Isolated Trash");yield isolated_trash.make_directory_async(Priority.DEFAULT,null);
    assert((yield ExtraActions.trash_contents(isolated_trash)).size==0);
    yield ExtraActions.empty_trash_at(window,operations,isolated_trash);yield pause_layout();var empty_notice=window.visible_dialog as Adw.AlertDialog;assert(empty_notice!=null&&empty_notice.heading=="Trash is Empty");empty_notice.close();yield pause_layout();
    bool enumeration_failed=false;try{yield ExtraActions.trash_contents(isolated_trash.get_child("missing"));}catch(Error e){enumeration_failed=true;}assert(enumeration_failed);
    FileUtils.set_contents(isolated_trash.get_child("discard.txt").get_path(),"isolated fixture");var discard=yield ExtraActions.trash_contents(isolated_trash);assert(discard.size==1);
    uint cancel=Timeout.add(50,()=>{var alert=window.visible_dialog as Adw.AlertDialog;if(alert==null)return Source.CONTINUE;assert(alert.heading=="Empty Trash?");alert.response("cancel");alert.close();return Source.REMOVE;});
    yield ExtraActions.empty_trash_at(window,operations,isolated_trash);assert(isolated_trash.get_child("discard.txt").query_exists());yield pause_layout();
    uint confirm=Timeout.add(50,()=>{var alert=window.visible_dialog as Adw.AlertDialog;if(alert==null)return Source.CONTINUE;alert.response("apply");alert.close();return Source.REMOVE;});
    yield ExtraActions.empty_trash_at(window,operations,isolated_trash);assert(!isolated_trash.get_child("discard.txt").query_exists());yield isolated_trash.delete_async(Priority.DEFAULT,null);
    operations.jobs.remove_all();
    browser.navigate(folder);while(browser.directory.loading)yield pause_layout();yield pause_layout();
    foreach (bool dark in new bool[] {false, true}) {
        Adw.StyleManager.get_default().color_scheme = dark ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
        string suffix = dark ? "-dark" : "-light";
        var theme = Environment.get_variable("MAJORIS_MENU_THEME");
        if (theme != null) {
            var css = new Gtk.CssProvider(); css.load_from_path(theme + "/gtk-4.0/" + (dark ? "gtk-dark.css" : "gtk.css"));
            Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_USER);
        }
        foreach (var filename in new string[] {"document.txt", "Folder", "archive.zip", "image.png", "multiple", "empty"}) {
            browser.active_selection.unselect_all();
            if (filename != "empty") browser.select_file(folder.get_child(filename == "multiple" ? "document.txt" : filename));
            if (filename == "multiple") for (uint i = 0; i < browser.active_selection.get_n_items(); i++) if (((FileItem)browser.active_selection.get_item(i)).name == "Folder") browser.active_selection.select_item(i, false);
            var model = new Menu(); window.populate_context(model, browser); var all = labels(model); var main = labels(model, false);
            assert(!("Permissions…" in all) && !("Default Application…" in all) && !("Custom Icon…" in all));
            assert(!("Extract with Password…" in all) && !("Create Encrypted ZIP…" in all));
            if (filename == "empty") { assert("New Folder" in main); assert(!("Properties" in main)); }
            else {
                assert(main[main.length - 1] == "Properties"); assert("More Actions…" in main); assert("Compress…" in all); assert(!("Compress…" in main));
                assert("Add to Favorites" in main); assert("Tags…" in main);
                if (filename == "multiple") { assert(!("Open" in main)); assert("Batch Rename…" in main); }
                else assert("Open" in main);
                if (filename == "Folder") { assert("Open in New Tab" in main); assert(!("Open With…" in main)); }
                if (filename == "archive.zip") assert("Extract…" in main);
                if (filename == "image.png") { assert("Quick Actions…" in all); assert(!("Rotate Clockwise" in main)); }
            }
            var popup = file_popup(browser.file_surface); assert(popup != null && !popup.has_arrow);
            popup.menu_model = model;
            Gdk.Rectangle anchor = {browser.file_surface.get_width() / 2, browser.file_surface.get_height() / 3, 1, 1}; popup.pointing_to = anchor; popup.popup();
            if (filename == "empty" && output != "") {
                popup.popdown(); yield pause_layout();
                yield capture_empty_click(window, browser);
            }
            yield screenshot(filename + suffix);
            if (filename == "document.txt") {
                // GtkPopoverMenu exposes native submenu navigation as an action.
                var more = menu_label(popup, "More Actions…"); assert(more != null); more.get_parent().activate(); yield pause_layout();
                assert(menu_label(popup, "Duplicate") != null); if (theme != null) verify_arrows(popup);
                yield screenshot("more-actions" + suffix);
            }
            popup.popdown();yield pause_layout();
        }
        foreach (var icon in new string[] {"open-menu-symbolic", "view-more-symbolic"}) {
            dismiss_popovers(window);yield pause_layout();
            var button = menu_button(window, icon); assert(button != null);
            if (!button.get_mapped()) { window.set_default_size(500, 740); yield pause_layout(); }
            if (button.get_mapped()) { button.popup(); yield pause_layout(); assert(!button.popover.has_arrow&&button.popover.get_mapped()); yield screenshot((icon == "open-menu-symbolic" ? "application" : "overflow") + suffix); button.popdown();yield pause_layout(); }
        }
        window.set_default_size(1100, 740); yield pause_layout();
        var row = place_row(browser); assert(row != null); var controllers = row.get_parent().observe_controllers();
        for (uint i = 0; i < controllers.get_n_items(); i++) {
            var gesture = controllers.get_item(i) as Gtk.GestureClick;
            if (gesture != null && gesture.button == 3) { Graphene.Rect bounds; row.compute_bounds(row.get_parent(), out bounds); gesture.pressed(1, 16, bounds.origin.y + 8); yield pause_layout(); var device_popup = file_popup(row.get_parent()); assert(device_popup != null && device_popup.get_mapped());
                Test.message("Sidebar popup: %dx%d items=%d", device_popup.get_width(), device_popup.get_height(), device_popup.menu_model.get_n_items());
                assert(menu_label(device_popup, "Open in New Tab") != null); assert(menu_label(device_popup, "Properties") != null); assert(menu_label(device_popup, "Eject") == null && menu_label(device_popup, "Unmount") == null && menu_label(device_popup, "Mount") == null); yield screenshot("sidebar" + suffix); break; }
        }
        dismiss_popovers(window);
        foreach(var uri in new string[]{"trash:///","network:///","tag"}){
            var destination=destination_row(browser,uri);assert(destination!=null);var list=(Gtk.ListBox)destination.get_parent();list.select_row(destination);destination.grab_focus();
            var inputs=list.observe_controllers();bool opened=false;
            for(uint i=0;i<inputs.get_n_items();i++){var key=inputs.get_item(i) as Gtk.EventControllerKey;if(key!=null){opened=key.key_pressed(Gdk.Key.Menu,0,0);if(opened)break;}}
            assert(opened);yield pause_layout();var popup=file_popup(list);assert(popup!=null&&popup.visible);var entries=labels(popup.menu_model);
            assert(("Empty Trash…" in entries)==(uri=="trash:///"));assert(("Connect to Server…" in entries)==(uri=="network:///"));assert(("Manage Tags…" in entries)==(uri=="tag"));
            if(uri=="trash:///")assert(entries.length==3&&entries[0]=="Open"&&entries[1]=="Open in New Tab");
            yield screenshot((uri=="trash:///"?"trash-sidebar":uri=="network:///"?"network-sidebar":"tag-sidebar")+suffix);popup.popdown();yield pause_layout();
            if(uri=="network:///"){assert(list.activate_action("win.connect-server",null));yield pause_layout();var connect=window.visible_dialog as Adw.AlertDialog;assert(connect!=null);connect.response("cancel");connect.close();yield pause_layout();}
            if(uri=="trash:///"){for(uint i=0;i<inputs.get_n_items();i++){var key=inputs.get_item(i) as Gtk.EventControllerKey;if(key!=null&&key.key_pressed(Gdk.Key.F10,0,Gdk.ModifierType.SHIFT_MASK))break;}yield pause_layout();assert(file_popup(list).visible);file_popup(list).popdown();yield pause_layout();}
        }
        window.lookup_action("preferences").activate(null);yield pause_layout();var preferences=(Adw.PreferencesDialog)window.visible_dialog;
        var sharing=preference(preferences,"Shared Folders…");assert(sharing!=null&&preference(preferences,"SMB Account Password…")!=null);
        preferences.visible_page=(Adw.PreferencesPage)sharing.get_ancestor(typeof(Adw.PreferencesPage));yield screenshot("preferences-network"+suffix);
        var tags=preference(preferences,"Manage Tags…");assert(tags!=null);preferences.visible_page=(Adw.PreferencesPage)tags.get_ancestor(typeof(Adw.PreferencesPage));yield screenshot("preferences-tags"+suffix);
        preferences.visible_page=(Adw.PreferencesPage)sharing.get_ancestor(typeof(Adw.PreferencesPage));yield pause_layout();var shared_button=command_button(preferences,"win.shared-folders");assert(shared_button!=null);shared_button.activate();yield pause_layout();var shared=window.visible_dialog as SharedFoldersDialog;assert(shared!=null);window.lookup_action("shared-folders").activate(null);assert(window.visible_dialog==shared);shared.close();yield pause_layout();
        var password_button=command_button(preferences,"win.smb-password");assert(password_button!=null);password_button.activate();yield pause_layout();var password_dialog=window.visible_dialog as Adw.AlertDialog;assert(password_dialog!=null&&password_dialog.extra_child is Gtk.PasswordEntry);var password=(Gtk.PasswordEntry)password_dialog.extra_child;password.text="fixture-only";password_dialog.response("cancel");password_dialog.close();yield pause_layout();assert(password.text=="");
        var definitions=metadata.tag_definitions();foreach(var definition in definitions)metadata.update_tag(definition.id,definition.name,definition.color,false);yield pause_layout();assert(destination_row(browser,"tag")==null);
        preferences.visible_page=(Adw.PreferencesPage)tags.get_ancestor(typeof(Adw.PreferencesPage));yield pause_layout();var manage=command_button(preferences,"win.manage-tags");assert(manage!=null);manage.activate();yield pause_layout();assert(window.visible_dialog is TagsDialog);window.visible_dialog.close();yield pause_layout();
        foreach(var definition in definitions)metadata.update_tag(definition.id,definition.name,definition.color,definition.sidebar_visible);preferences.close();yield pause_layout();
        window.lookup_action("about").activate(null);yield pause_layout();var about=window.visible_dialog as Adw.AboutDialog;assert(about!=null&&about.version==APP_VERSION&&about.application_icon=="com.majoris.files");yield screenshot("about"+suffix);about.close();yield pause_layout();
        browser.show_view_settings();yield pause_layout();var settings=window.visible_dialog;assert(preference(settings,"Show Hidden Files")!=null);yield screenshot("view-settings"+suffix);settings.close();yield pause_layout();
        browser.search_entry.text="document";yield pause_layout();yield pause_layout();assert(window.lookup_action("save-search").enabled);
        var search_options=menu_button(browser,"system-search-symbolic");
        // Locate by tooltip because Search Options uses a distinct symbolic icon.
        search_options=tooltip_menu(browser,"Search Options");assert(search_options!=null);search_options.popup();yield screenshot("search-options"+suffix);search_options.popdown();yield pause_layout();
        window.lookup_action("save-search").activate(null);yield pause_layout();var save=window.visible_dialog as Adw.AlertDialog;assert(save!=null);var entry=prompt_entry(save);assert(entry!=null);entry.text="Saved document"+suffix;
        string original_query=browser.saved_query();window.new_tab(folder.get_child("Folder"));save.response("apply");save.close();yield pause_layout();var saved=metadata.saved_searches();bool found_saved=false;foreach(var item in saved)if(item.name=="Saved document"+suffix){found_saved=true;assert(item.location.equal(folder)&&item.query==original_query);}assert(found_saved);
        window.lookup_action("close-tab").activate(null);yield pause_layout();assert(window.current==browser);
        browser.search_entry.text="";yield pause_layout();window.update_commands();assert(!window.lookup_action("save-search").enabled);
        var empty_operations=FileOperationsPresentation.get_window(operations);empty_operations.present();yield screenshot("operations-no-recovery"+suffix);empty_operations.close();yield pause_layout();
        var recovery_root=File.new_for_path(DirUtils.make_tmp("majoris-recovery-presentation-XXXXXX"));var target=recovery_root.get_child("target.txt");var backup=recovery_root.get_child(".majoris-backup-presentation");FileUtils.set_contents(target.get_path(),"old");var replacement=yield operations.replacements.prepare(target,backup);yield target.move_async(backup,FileCopyFlags.NONE,Priority.DEFAULT,null,null);FileUtils.set_contents(target.get_path(),"new");yield operations.replacements.committed(replacement);
        var sources=new Gee.ArrayList<File>();sources.add(folder.get_child("document.txt"));var temporary=new Gee.ArrayList<File>();temporary.add(folder.get_child(".majoris-rename-menu-fixture"));var names=new Gee.ArrayList<string>();names.add("renamed.txt");
        yield operations.rename_recovery.prepare(sources,temporary,names);assert(operations.has_rename_recovery);var progress=FileOperationsPresentation.get_window(operations);assert(progress!=null);progress.present();yield screenshot("recovery"+suffix);progress.close();yield pause_layout();
        window.lookup_action("recover-rename").activate(null);yield pause_layout();var review=window.visible_dialog as Adw.AlertDialog;assert(review!=null);review.response("cancel");review.close();yield pause_layout();assert(operations.rename_recovery.pending&&operations.has_rename_recovery);
        window.lookup_action("recover-rename").activate(null);yield pause_layout();review=window.visible_dialog as Adw.AlertDialog;assert(review!=null);review.response("apply");review.close();
        for(int wait=0;operations.has_rename_recovery&&wait<30;wait++)yield pause_layout();assert(!operations.has_rename_recovery);assert(!window.lookup_action("recover-rename").enabled);while(browser.directory.loading)yield pause_layout();
        yield operations.replacements.restore(replacement,new Cancellable());assert(!operations.has_replacement_recovery);
        window.set_default_size(1100, 740); yield pause_layout();
    }
    assert(window.visible_dialog==null);
    // Invoke the native file menu through both keyboard entry points.
    var focus = new Subprocess.newv({"xdotool", "search", "--name", "^Files$", "windowfocus", "--sync"}, SubprocessFlags.STDOUT_SILENCE); yield focus.wait_check_async(null);
    dismiss_popovers(window); browser.set_view("Grid"); yield pause_layout(); browser.select_file(folder.get_child("document.txt"));
    while(browser.directory.loading)yield pause_layout();yield pause_layout();
    var view = file_view(browser.file_surface); assert(view != null); view.grab_focus(); yield pause_layout();
    var focused_cell=file_cell(browser.file_surface,"document.txt");assert(focused_cell!=null);Graphene.Rect file_bounds;assert(focused_cell.compute_bounds(window,out file_bounds));
    var pointer_focus=new Subprocess.newv({"xdotool","search","--onlyvisible","--name","^Files$","mousemove","--window","%@",((int)file_bounds.origin.x+8).to_string(),((int)file_bounds.origin.y+8).to_string(),"click","1"},SubprocessFlags.NONE);yield pointer_focus.wait_check_async(null);yield pause_layout();
    foreach (var key in new string[] {"Menu", "shift+F10"}) {
        Test.message("Keyboard context key=%s focus=%s", key, window.get_focus() == null ? "none" : window.get_focus().get_type().name());
        var input = new Subprocess.newv({"xdotool", "key", "--clearmodifiers", key}, SubprocessFlags.NONE); yield input.wait_check_async(null); yield pause_layout();
        assert(file_popup(browser.file_surface).visible);
        var escape = new Subprocess.newv({"xdotool", "key", "Escape"}, SubprocessFlags.NONE); yield escape.wait_check_async(null); yield pause_layout(); assert(!file_popup(browser.file_surface).visible);
    }
    browser.active_selection.unselect_all();window.update_commands();window.lookup_action("select-pattern").activate(null);yield pause_layout();var pattern=window.visible_dialog as Adw.AlertDialog;assert(pattern!=null);prompt_entry(pattern).text="*.txt";
    window.new_tab(folder.get_child("Folder"));pattern.response("apply");pattern.close();yield pause_layout();assert(browser.selected().size==1&&browser.selected()[0].name=="document.txt");assert(window.current.selected().size==0);window.lookup_action("close-tab").activate(null);yield pause_layout();assert(window.current==browser);
    // Mixed favorites converge to all added, then all removed.
    browser.active_selection.select_all(); var selected = browser.selected(); assert(selected.size > 1);
    metadata.set_favorite(selected[0].file, true); window.lookup_action("favorite").activate(null);
    foreach (var item in selected) assert(metadata.favorite(item.file));
    var favorite_menu = new Menu(); window.populate_context(favorite_menu, browser); assert("Remove from Favorites" in labels(favorite_menu));
    window.lookup_action("favorite").activate(null); foreach (var item in selected) assert(!metadata.favorite(item.file));
    var compress = new SevenZipDialog(window, selected, folder, new OperationManager(metadata)); yield pause_layout();
    var archive_name = preference(compress, "Archive Filename") as Adw.EntryRow;
    var archive_format = preference(compress, "Archive Format") as Adw.ComboRow;
    var volume = preference(compress, "Volume Size (MiB; 0 for one file)") as Adw.SpinRow;
    var level = preference(compress, "Compression Level") as Adw.SpinRow;
    var encryption = preference(compress, "Encrypt Contents (ZIP filenames remain visible)") as Adw.SwitchRow;
    assert(archive_name != null && archive_format != null && volume != null && level != null && encryption != null);
    assert(encryption.sensitive && !volume.sensitive && !level.sensitive);
    archive_name.text = "My archive.zip"; archive_format.selected = 1;
    assert(archive_name.text == "My archive.7z" && volume.sensitive && level.sensitive && encryption.sensitive);
    encryption.active = true; archive_format.selected = 2;
    assert(archive_name.text == "My archive.tar" && !encryption.sensitive && !encryption.active && !volume.sensitive);
    compress.close(); yield pause_layout();
    // Provider model adaptation preserves nested targets, sections and state actions.
    var provider = new Menu(); provider.append_submenu("Empty provider submenu", new Menu()); provider.append_section(null, new Menu()); var sub = new Menu(); var icon = new MenuItem("Provider", "cloudprovider.state::yes"); icon.set_icon(new ThemedIcon("starred-symbolic")); sub.append_item(icon); provider.append_submenu("Provider actions", sub);
    var clean = MenuPresentation.text_only(provider); labels(clean); assert(clean.get_n_items() == 1);
    var target = clean.get_item_link(0, Menu.LINK_SUBMENU).get_item_attribute_value(0, "target", VariantType.STRING); assert(target.get_string() == "yes");
    // Pointer target and empty-space reset in every view.
    foreach (var mode in new string[] {"Grid", "List", "Columns", "Gallery"}) {
        browser.set_view(mode); yield pause_layout(); browser.select_file(folder.get_child("document.txt")); yield pause_layout();
        var cell = file_cell(browser.file_surface, "document.txt"); assert(cell != null);
        Graphene.Rect bounds; assert(cell.compute_bounds(browser.file_surface, out bounds));
        browser.active_selection.unselect_all(); browser.target_context(bounds.origin.x + 2, bounds.origin.y + 2);
        assert(browser.selected().size == 1 && browser.selected()[0].name == "document.txt");
        browser.active_selection.select_all(); int count = browser.selected().size;
        browser.target_context(bounds.origin.x + 2, bounds.origin.y + 2); assert(browser.selected().size == count);
        browser.target_context(browser.file_surface.get_width() - 2, browser.file_surface.get_height() - 2); assert(browser.selected().size == 0);
    }
    browser.set_view("List"); browser.select_file(folder.get_child("document.txt"));
    var cloud = CloudFiles.get_default(); cloud.register_provider(new MenuCloud(folder)); cloud.peek(folder.get_child("document.txt"));
    for (int i = 0; cloud.cached(folder.get_child("document.txt")) == null && i < 10; i++) yield pause_layout();
    var cloud_menu = new Menu(); window.populate_context(cloud_menu, browser); var cloud_labels = labels(cloud_menu);
    assert("Make Available Offline" in cloud_labels && !("Free Local Space" in cloud_labels) && !("Retry Cloud Sync" in cloud_labels));
    var readonly = folder.get_child("Read Only"); yield readonly.make_directory_async(Priority.DEFAULT, null);
    readonly.set_attribute_uint32("unix::mode", 0555, FileQueryInfoFlags.NONE); browser.navigate(readonly);
    while (browser.directory.loading) yield pause_layout(); yield pause_layout();
    var readonly_menu = new Menu(); window.populate_context(readonly_menu, browser);
    assert(!browser.accepts_destination && !("New Folder" in labels(readonly_menu)) && !("Paste" in labels(readonly_menu)));
    readonly.set_attribute_uint32("unix::mode", 0755, FileQueryInfoFlags.NONE);
    browser.directory.virtual_location(File.new_for_uri("trash:///"));
    browser.directory.items.append(selected[0]); browser.selection.select_all();
    var trash = new Menu(); window.populate_context(trash, browser); var trash_labels = labels(trash);
    assert("Restore" in trash_labels && "Delete Permanently" in trash_labels && !("Cut" in trash_labels) && !("Compress…" in trash_labels));
    browser.selection.unselect_all(); trash.remove_all(); window.populate_context(trash, browser);
    assert(!("Empty Trash" in labels(trash)) && !("New Folder" in labels(trash)));
    browser.directory.virtual_location(File.new_for_uri("recent:///")); var recent = new Menu(); window.populate_context(recent, browser); assert(!("New Folder" in labels(recent)));
    window.destroy();
}
async void recovery_state() throws Error {
    var root=File.new_for_path(DirUtils.make_tmp("majoris-menu-recovery-XXXXXX"));
    string state=root.get_child("state.db").get_path();var metadata=new MetadataStore(state);var operations=new OperationManager(metadata);
    assert(!operations.has_rename_recovery&&!operations.has_replacement_recovery&&operations.recovery_signature()=="");
    var target=root.get_child("target.txt");var backup=root.get_child(".majoris-backup-menu-fixture");FileUtils.set_contents(target.get_path(),"original");
    var record=yield operations.replacements.prepare(target,backup);yield target.move_async(backup,FileCopyFlags.NONE,Priority.DEFAULT,null,null);FileUtils.set_contents(target.get_path(),"new destination");yield operations.replacements.committed(record);
    assert(operations.has_replacement_recovery&&!operations.has_rename_recovery);
    var source=root.get_child("source.txt");FileUtils.set_contents(source.get_path(),"rename original");var sources=new Gee.ArrayList<File>();sources.add(source);var staging=new Gee.ArrayList<File>();staging.add(root.get_child(".majoris-rename-recovery-fixture"));var names=new Gee.ArrayList<string>();names.add("renamed.txt");
    yield operations.rename_recovery.prepare(sources,staging,names);assert(operations.has_rename_recovery&&operations.has_replacement_recovery);
    var restarted=new OperationManager(new MetadataStore(state));assert(restarted.has_rename_recovery&&restarted.has_replacement_recovery);assert(restarted.recovery_signature()==operations.recovery_signature());
    var hidden=root.get_child("preserved-original");yield backup.move_async(hidden,FileCopyFlags.NONE,Priority.DEFAULT,null,null);FileUtils.set_contents(backup.get_path(),"unrelated replacement");
    bool failed=false;try{yield restarted.replacements.restore(restarted.replacements.records[0],new Cancellable());}catch(Error e){failed=true;}assert(failed&&restarted.has_replacement_recovery&&restarted.replacements.records.size==1);
    yield backup.delete_async(Priority.DEFAULT,null);yield hidden.move_async(backup,FileCopyFlags.NONE,Priority.DEFAULT,null,null);
    var restored=yield restarted.replacements.restore(restarted.replacements.records[0],new Cancellable());assert(!restored.equal(target));assert(!restarted.has_replacement_recovery&&restarted.has_rename_recovery);string contents;FileUtils.get_contents(target.get_path(),out contents);assert(contents=="new destination");FileUtils.get_contents(restored.get_path(),out contents);assert(contents=="original");
    var original_source=root.get_child("preserved-rename-source");yield source.move_async(original_source,FileCopyFlags.NONE,Priority.DEFAULT,null,null);FileUtils.set_contents(source.get_path(),"unrelated rename input");failed=false;try{yield restarted.rename_recovery.recover(new Cancellable());}catch(Error e){failed=true;}assert(failed&&restarted.has_rename_recovery&&restarted.rename_recovery.pending);FileUtils.get_contents(source.get_path(),out contents);assert(contents=="unrelated rename input");yield source.delete_async(Priority.DEFAULT,null);yield original_source.move_async(source,FileCopyFlags.NONE,Priority.DEFAULT,null,null);
    yield restarted.rename_recovery.recover(new Cancellable());assert(!restarted.has_rename_recovery&&restarted.recovery_signature()=="");
    var completed=new OperationManager(new MetadataStore(state));assert(!completed.has_rename_recovery&&!completed.has_replacement_recovery);
}
int main(string[] args) {
    Test.init(ref args); Gtk.init(); Adw.init(); output = Environment.get_variable("MAJORIS_MENU_EVIDENCE") ?? "";
    if (output != "") DirUtils.create_with_parents(output, 0755);
    Test.add_func("/menus/context-and-presentation", () => { var loop = new MainLoop(); scenarios.begin((obj, res) => { try { scenarios.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); }); loop.run(); });
    Test.add_func("/menus/durable-recovery-state",()=>{var loop=new MainLoop();recovery_state.begin((o,r)=>{try{recovery_state.end(r);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});
    return Test.run();
}
