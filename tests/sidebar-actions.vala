using MajorisFiles;
bool only_cloud;
Gtk.ListBoxRow? sidebar_row(Gtk.Widget widget,string uri) {
    if(widget is Gtk.ListBoxRow){var place=widget.get_data<Place>("majoris-place");if(place!=null&&place.file.get_uri()==uri)return (Gtk.ListBoxRow)widget;}
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var row=sidebar_row(child,uri);if(row!=null)return row;}return null;
}
Gtk.PopoverMenu? sidebar_popup(Gtk.Widget widget) {
    if(widget is Gtk.PopoverMenu && widget.visible)return (Gtk.PopoverMenu)widget;
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var popup=sidebar_popup(child);if(popup!=null)return popup;}return null;
}
Gtk.Widget? rendered_item(Gtk.Widget widget,string text) {
    if(widget is Gtk.Label&&((Gtk.Label)widget).label==text&&widget.get_mapped())return widget.get_parent();
    for(var child=widget.get_first_child();child!=null;child=child.get_next_sibling()){var item=rendered_item(child,text);if(item!=null)return item;}return null;
}
async void popup_for(FilesWindow window,string uri) throws Error {
    var row=sidebar_row(window.current,uri);assert(row!=null);yield popup_at(window,row);
}
async void popup_at(FilesWindow window,Gtk.Widget row) throws Error {
    for(var parent=row.get_parent();parent!=null;parent=parent.get_parent())if(parent is Gtk.ScrolledWindow){
        var scroll=(Gtk.ScrolledWindow)parent;Graphene.Rect content;assert(row.compute_bounds(scroll.child,out content));
        scroll.vadjustment.value=((double)content.origin.y).clamp(scroll.vadjustment.lower,double.max(scroll.vadjustment.lower,scroll.vadjustment.upper-scroll.vadjustment.page_size));break;
    }
    yield pause_layout();Graphene.Rect bounds;assert(row.compute_bounds(window,out bounds));
    var search=new Subprocess.newv({"xdotool","search","--onlyvisible","--name","^"+Regex.escape_string(window.title)+"$"},SubprocessFlags.STDOUT_PIPE);
    string? ids;yield search.communicate_utf8_async(null,null,out ids,null);assert(search.get_successful());
    var click=new Subprocess.newv({"xdotool","windowfocus","--sync",ids.strip().split("\n")[0],"mousemove","--window",ids.strip().split("\n")[0],((int)bounds.get_center().x).to_string(),((int)bounds.get_center().y).to_string(),"click","3"},SubprocessFlags.NONE);
    yield click.wait_check_async(null);yield pause_layout();assert(sidebar_popup(window)!=null);
}
async void exercise(bool diagnose) throws Error {
    var root=File.new_for_path(DirUtils.make_tmp("majoris-sidebar-actions-XXXXXX"));
    var metadata=new MetadataStore(root.get_child("state.db").get_path());metadata.set_state("notifications","false");
    var app=new Adw.Application("com.majoris.sidebar.actions",ApplicationFlags.NON_UNIQUE);app.register(null);
    var places=new Places(metadata);var window=new FilesWindow(app,metadata,places,new OperationManager(metadata),root);window.present();yield pause_layout();
    if(only_cloud){yield cloud_case(window,places,root);window.destroy();yield OperationManager.remove_tree(root,new Cancellable());return;}
    int commands=0;window.current.sidebar_command_started.connect((command,place)=>{commands++;stdout.printf("dispatch %s target=%s\n",command,place.file.get_uri());});
    yield popup_for(window,"file:///");var popup=sidebar_popup(window);popup.closed.connect(()=>stdout.printf("popover closed parent=%s\n",popup.get_parent()==null?"none":"present"));popup.notify["parent"].connect(()=>stdout.printf("popover parent changed: %s\n",popup.get_parent()==null?"none":"present"));
    var item=rendered_item(popup,"Open");assert(item!=null);stdout.printf("GTK activation item=%s sensitive=%s\n",item.get_type().name(),item.get_sensitive().to_string());assert(item.activate());yield pause_layout();
    bool opened=window.current.location.equal(File.new_for_path("/"));stdout.printf("result commands=%d navigated=%s\n",commands,opened.to_string());
    if(!diagnose){assert(commands==1);assert(opened);}
    if (!diagnose) yield extended_cases(window, places, metadata, root);
    window.destroy();yield OperationManager.remove_tree(root,new Cancellable());
}
async void key(FilesWindow window,string value) throws Error {
    var process=new Subprocess.newv({"xdotool","key",value},SubprocessFlags.NONE);yield process.wait_check_async(null);yield pause_layout();
}
async void keyboard_item(FilesWindow window,string uri,string label) throws Error {
    var row=sidebar_row(window.current,uri);assert(row!=null);((Gtk.ListBox)row.get_parent()).select_row(row);row.grab_focus();yield key(window,"Menu");
    var popup=sidebar_popup(window);assert(popup!=null);var item=rendered_item(popup,label);assert(item!=null);
    var browser=window.current;int calls=0;ulong handler=browser.sidebar_command_started.connect((command,target)=>{calls++;assert(target.file.get_uri()==uri);});
    stdout.printf("keyboard activate %s target=%s\n",label,uri);stdout.flush();item.grab_focus();yield key(window,"Return");browser.disconnect(handler);assert(calls==1);
}
async void activate_item(FilesWindow window,string uri,string label) throws Error {
    yield popup_for(window,uri);var item=rendered_item(sidebar_popup(window),label);assert(item!=null&&item.is_sensitive());
    var browser=window.current;int calls=0;ulong handler=browser.sidebar_command_started.connect((command,target)=>{calls++;assert(target.file.get_uri()==uri);});
    stdout.printf("activate %s target=%s\n",label,uri);stdout.flush();assert(item.activate());yield pause_layout();browser.disconnect(handler);
    if(label in new string[]{"Open","Open in New Tab","Mount","Unmount","Eject","Properties"})assert(calls==1);else assert(calls==0);
}
async void dismiss_dialog(FilesWindow window) {
    assert(window.visible_dialog!=null);window.visible_dialog.close();yield pause_layout();
}
async void extended_cases(FilesWindow window,Places places,MetadataStore metadata,File root) throws Error {
    window.title="Sidebar Fixture A";
    var folder=root.get_child("folder");yield folder.make_directory_async();
    places.entries.clear();
    var system=new Place("System Drive",File.new_for_path("/"));system.system=true;system.section="Devices";
    places.entries.add(system);places.entries.add(new Place("Fixture Folder",folder));
    var network=new Place("Network",File.new_for_uri("network:///"));places.entries.add(network);
    var trash=new Place("Trash",File.new_for_uri("trash:///"));places.entries.add(trash);
    var tag=Places.tag_places(metadata.tag_definitions())[0];places.entries.add(tag);
    var volume=new SidebarVolume();volume.root=root.get_child("volume-root");yield volume.root.make_directory_async();volume.display_name="Test Volume";
    var device=new Place("Test Volume",File.new_for_uri("majoris:///device/sidebar-test"));device.section="Devices";device.volume=volume;places.entries.add(device);
    volume.mounted_changed.connect(()=>{
        places.entries.remove(device);
        if(volume.mounted==null){device=new Place("Test Volume",File.new_for_uri("majoris:///device/sidebar-test"));device.volume=volume;}
        else device=new Place("Test Volume",volume.root,volume.mounted);
        device.section="Devices";places.entries.add(device);places.changed();
    });
    var drive=new SidebarDrive();var optical=new Place("Empty Optical",File.new_for_uri("majoris:///device/optical-test"));optical.section="Devices";optical.drive=drive;places.entries.add(optical);
    var tape=new Place("Tape",File.new_for_uri("majoris:///device/tape-test"));tape.section="Devices";tape.drive=new SidebarDrive();tape.device_info=new DeviceInfo();tape.device_info.category=DeviceCategory.TAPE_DRIVE;places.entries.add(tape);
    places.changed();yield pause_layout();
    window.current.navigate(folder);yield pause_layout();
    var original=window.current;int before=window.tabs.n_pages;
    yield activate_item(window,"file:///","Open in New Tab");assert(window.tabs.n_pages==before+1);assert(window.current!=original);assert(window.current.location.equal(system.file));
    assert(original.location.equal(folder));
    yield activate_item(window,folder.get_uri(),"Open");assert(window.current.location.equal(folder));
    yield activate_item(window,"file:///","Properties");assert(window.visible_dialog is DevicePropertiesDialog);yield dismiss_dialog(window);
    var row=sidebar_row(window.current,"file:///");((Gtk.ListBox)row.get_parent()).select_row(row);row.grab_focus();yield key(window,"Menu");
    var popup=sidebar_popup(window);assert(popup!=null);var properties=rendered_item(popup,"Properties");assert(properties!=null);properties.grab_focus();yield key(window,"Return");assert(window.visible_dialog is DevicePropertiesDialog);yield dismiss_dialog(window);
    row=sidebar_row(window.current,"file:///");row.grab_focus();yield key(window,"shift+F10");assert(sidebar_popup(window)!=null);yield key(window,"Escape");assert(sidebar_popup(window)==null);assert(window.get_focus()!=null&&(window.get_focus()==row||window.get_focus().is_ancestor(row)));
    yield keyboard_item(window,"file:///","Open");assert(window.current.location.equal(system.file));
    var keyboard_source=window.current;before=window.tabs.n_pages;yield keyboard_item(window,folder.get_uri(),"Open in New Tab");assert(window.tabs.n_pages==before+1&&window.current.location.equal(folder)&&keyboard_source.location.equal(system.file));
    yield activate_item(window,device.file.get_uri(),"Properties");assert(window.visible_dialog is DevicePropertiesDialog&&volume.mutations==0);yield dismiss_dialog(window);
    yield activate_item(window,device.file.get_uri(),"Mount");assert(volume.mutations==1&&volume.mounted!=null);assert(window.current.location.equal(folder));
    assert(!volume.can_mount());yield activate_item(window,device.file.get_uri(),"Open");assert(window.current.location.equal(volume.root));
    var mounted=volume.mounted;yield activate_item(window,device.file.get_uri(),"Unmount");assert(mounted.mutations==1&&volume.mounted==null);
    before=window.tabs.n_pages;yield activate_item(window,device.file.get_uri(),"Open in New Tab");assert(window.tabs.n_pages==before+1&&volume.mounted!=null&&volume.mutations==2);assert(window.current.location.equal(volume.root));
    yield activate_item(window,device.file.get_uri(),"Properties");assert(window.visible_dialog is DevicePropertiesDialog);assert(volume.mutations==2);yield dismiss_dialog(window);
    var ejecting=volume.mounted;ejecting.ejectable=true;yield activate_item(window,device.file.get_uri(),"Eject");assert(ejecting.mutations==1&&volume.mutations==2);ejecting.ejectable=false;
    yield popup_for(window,optical.file.get_uri());assert(rendered_item(sidebar_popup(window),"Open")==null);assert(rendered_item(sidebar_popup(window),"Properties")!=null);sidebar_popup(window).popdown();yield pause_layout();
    yield activate_item(window,optical.file.get_uri(),"Eject");assert(drive.mutations==1);
    yield popup_for(window,tape.file.get_uri());assert(rendered_item(sidebar_popup(window),"Open")==null&&rendered_item(sidebar_popup(window),"Eject")==null);sidebar_popup(window).popdown();yield pause_layout();
    yield activate_item(window,tape.file.get_uri(),"Properties");assert(window.visible_dialog is DevicePropertiesDialog);assert(((SidebarDrive)tape.drive).mutations==0);yield dismiss_dialog(window);
    foreach(var category in new DeviceCategory[]{DeviceCategory.INTERNAL_VOLUME,DeviceCategory.REMOVABLE_VOLUME,DeviceCategory.MEMORY_CARD,DeviceCategory.FLOPPY_DRIVE,DeviceCategory.OPTICAL_DRIVE}) {
        var fixture=new SidebarVolume();fixture.root=folder;
        var entry=new Place(category.to_string(),File.new_for_uri("majoris:///device/"+category.to_string()));entry.section="Devices";entry.volume=fixture;entry.device_info=new DeviceInfo();entry.device_info.category=category;places.entries.add(entry);places.changed();yield pause_layout();
        yield activate_item(window,entry.file.get_uri(),"Properties");assert(window.visible_dialog is DevicePropertiesDialog&&fixture.mutations==0);yield dismiss_dialog(window);
    }
    var disc=new SidebarVolume();disc.root=volume.root;disc.mounted=new SidebarMount(disc);drive.volume=disc;places.changed();yield pause_layout();
    before=window.tabs.n_pages;yield activate_item(window,optical.file.get_uri(),"Open in New Tab");assert(window.tabs.n_pages==before+1&&window.current.location.equal(disc.root));assert(disc.mutations==0&&drive.mutations==1);
    disc.mounted.ejectable=true;var disc_mount=disc.mounted;yield activate_item(window,optical.file.get_uri(),"Eject");assert(disc_mount.mutations==0&&drive.mutations==2);
    yield activate_item(window,network.file.get_uri(),"Connect to Server…");assert(window.visible_dialog is Adw.AlertDialog);yield dismiss_dialog(window);
    yield activate_item(window,tag.file.get_uri(),"Open");assert(window.current.location.equal(tag.file));
    yield activate_item(window,tag.file.get_uri(),"Manage Tags…");assert(window.visible_dialog is TagsDialog);yield dismiss_dialog(window);
    var tagrow=sidebar_row(window.current,tag.file.get_uri());var heading=tagrow.get_header();assert(heading!=null);heading.grab_focus();yield key(window,"Menu");popup=sidebar_popup(window);assert(popup!=null);assert(rendered_item(popup,"Manage Tags…").activate());yield pause_layout();assert(window.visible_dialog is TagsDialog);yield dismiss_dialog(window);
    yield popup_at(window,heading);assert(sidebar_popup(window).menu_model.get_n_items()==1);assert(rendered_item(sidebar_popup(window),"Manage Tags…").activate());yield pause_layout();assert(window.visible_dialog is TagsDialog);yield dismiss_dialog(window);
    // Only cancel this command: automated tests never empty the user's Trash.
    yield activate_item(window,trash.file.get_uri(),"Empty Trash…");assert(window.visible_dialog is Adw.AlertDialog);var confirmation=(Adw.AlertDialog)window.visible_dialog;
    assert(confirmation.heading=="Empty Trash?"||confirmation.heading=="Trash is Empty");confirmation.close();yield pause_layout();
    Gtk.PopoverMenu? reused=null;for(int i=0;i<3;i++){yield activate_item(window,folder.get_uri(),"Open");yield popup_for(window,"file:///");if(reused==null)reused=sidebar_popup(window);else assert(reused==sidebar_popup(window));sidebar_popup(window).popdown();yield pause_layout();}
    yield popup_for(window,device.file.get_uri());places.entries.remove(device);places.changed();yield pause_layout();assert(sidebar_popup(window)==null);assert(volume.mutations==2);places.entries.add(device);places.changed();yield pause_layout();
    var second=new FilesWindow((Gtk.Application)window.application,metadata,places,new OperationManager(metadata),root);second.title="Sidebar Fixture B";second.present();yield pause_layout();
    yield activate_item(second,folder.get_uri(),"Open");assert(second.current.location.equal(folder));assert(window.current.location.equal(folder));second.destroy();
    volume.mounted=null;volume.fail_mount=true;before=window.tabs.n_pages;yield activate_item(window,device.file.get_uri(),"Open in New Tab");assert(window.tabs.n_pages==before);assert(window.visible_dialog is Adw.AlertDialog);yield dismiss_dialog(window);volume.fail_mount=false;
    var first_volume=new SidebarVolume();first_volume.root=folder;first_volume.display_name="First";
    var second_volume=new SidebarVolume();second_volume.root=volume.root;second_volume.display_name="Second";
    var multi_drive=new SidebarDrive();multi_drive.volume=first_volume;multi_drive.additional.add(second_volume);
    var multi=new Place("Multi-volume media",File.new_for_uri("majoris:///device/multi"));multi.drive=multi_drive;multi.section="Devices";places.entries.add(multi);places.changed();yield pause_layout();
    yield activate_item(window,multi.file.get_uri(),"Open");var chooser=window.visible_dialog as Adw.AlertDialog;assert(chooser!=null&&chooser.heading=="Choose a Volume");assert(first_volume.mutations==0&&second_volume.mutations==0);chooser.response("1");chooser.close();yield pause_layout();assert(window.current.location.equal(second_volume.root));assert(first_volume.mutations==0&&second_volume.mutations==1);
    // Async work must not emit open_in_tab into a different tab/window after close.
    volume.delayed=true;window.new_tab(root);yield pause_layout();var closing=window.current;int emitted=0;closing.open_in_tab.connect(()=>emitted++);
    yield popup_for(window,device.file.get_uri());assert(rendered_item(sidebar_popup(window),"Open in New Tab").activate());window.lookup_action("close-tab").activate(null);yield pause_layout();yield pause_layout();assert(emitted==0);
    yield cloud_case(window,places,root);
    var recent=new Place("Recent",File.new_for_uri("recent:///"));var favorites=new Place("Favorites",File.new_for_uri("majoris:///favorites"));places.entries.add(recent);places.entries.add(favorites);places.changed();yield pause_layout();
    foreach(var uri in new string[]{"recent:///","majoris:///favorites","network:///","trash:///"}){yield activate_item(window,uri,"Open");assert(window.current.location.get_uri()==uri);}
    before=window.tabs.n_pages;yield activate_item(window,tag.file.get_uri(),"Open in New Tab");assert(window.tabs.n_pages==before+1&&window.current.location.equal(tag.file));
    stdout.printf("PASS sidebar navigation, properties, device mutations, window actions, keyboard, lifecycle\n");
}
async void cloud_case(FilesWindow window,Places places,File root) throws Error {
    var connection=yield Bus.get(BusType.SESSION);
    string object_path="/com/majoris/SidebarCloudFixture";
    var actions=new SimpleActionGroup();int activated=0;string received="";
    var pick=new SimpleAction("pick",VariantType.STRING);pick.activate.connect((value)=>{activated++;received=value.get_string();});actions.add_action(pick);
    var disabled=new SimpleAction("disabled",null);disabled.set_enabled(false);actions.add_action(disabled);
    var model=new Menu();var item=new MenuItem("Cloud Choose",null);item.set_action_and_target_value("cloudprovider.pick",new Variant.string("account-A"));item.set_icon(new ThemedIcon("starred-symbolic"));model.append_item(item);
    model.append("Cloud Disabled","cloudprovider.disabled");var nested=new Menu();var nested_item=new MenuItem("Cloud Nested",null);nested_item.set_action_and_target_value("cloudprovider.pick",new Variant.string("nested-B"));nested.append_item(nested_item);model.append_submenu("Cloud Options",nested);
    string bus_name="com.majoris.SidebarCloudFixture";
    var exporter=new CloudProviders.ProviderExporter(connection,bus_name,object_path);exporter.set_name("Sidebar Fixture");
    var exported_account=new CloudProviders.AccountExporter(exporter,"account");exported_account.set_name("Sidebar Cloud");exported_account.set_path(root.get_path());exported_account.set_icon(new ThemedIcon("folder-symbolic"));exported_account.set_status(CloudProviders.AccountStatus.IDLE);exported_account.set_status_details("Fixture");exported_account.set_action_group(actions);exported_account.set_menu_model(model);
    var consumer=new CloudProviders.Provider(connection.unique_name,object_path);
    for(int i=0;i<20&&consumer.get_accounts().length()==0;i++)yield pause_layout();
    assert(consumer.get_accounts().length()==1);CloudProviders.Account account=consumer.get_accounts().data;
    for(int i=0;i<20&&(account.get_menu_model()==null||account.get_menu_model().get_n_items()==0||account.get_action_group().list_actions().length==0);i++)yield pause_layout();
    assert(account.get_menu_model()!=null&&account.get_menu_model().get_n_items()>0);
    var cloud=new Place("Cloud Fixture",root);cloud.cloud=account;places.entries.add(cloud);places.changed();yield pause_layout();
    yield activate_item(window,cloud.file.get_uri(),"Cloud Choose");assert(activated==1&&received=="account-A");
    yield popup_for(window,cloud.file.get_uri());var popup=sidebar_popup(window);var blocked=rendered_item(popup,"Cloud Disabled");assert(blocked!=null&&!blocked.is_sensitive());var options=rendered_item(popup,"Cloud Options");assert(options!=null);assert(options.activate());yield pause_layout();var child=rendered_item(popup,"Cloud Nested");assert(child!=null);assert(child.activate());yield pause_layout();assert(activated==2&&received=="nested-B");
    var second_actions=new SimpleActionGroup();int second_activated=0;var second_pick=new SimpleAction("pick",VariantType.STRING);second_pick.activate.connect((value)=>{assert(value.get_string()=="account-B");second_activated++;});second_actions.add_action(second_pick);
    var second_model=new Menu();var second_item=new MenuItem("Cloud Choose",null);second_item.set_action_and_target_value("cloudprovider.pick",new Variant.string("account-B"));second_model.append_item(second_item);
    var second_folder=root.get_child("cloud-B");yield second_folder.make_directory_async();
    var second_exported=new CloudProviders.AccountExporter(exporter,"second_account");second_exported.set_name("Second Account");second_exported.set_path(second_folder.get_path());second_exported.set_icon(new ThemedIcon("folder-symbolic"));second_exported.set_status(CloudProviders.AccountStatus.IDLE);second_exported.set_action_group(second_actions);second_exported.set_menu_model(second_model);
    for(int i=0;i<20&&consumer.get_accounts().length()<2;i++)yield pause_layout();CloudProviders.Account? second_account=null;foreach(var candidate in consumer.get_accounts())if(candidate.get_name()=="Second Account")second_account=candidate;assert(second_account!=null);
    var second_cloud=new Place("Second Cloud",second_folder);second_cloud.cloud=second_account;places.entries.add(second_cloud);places.changed();yield pause_layout();
    yield activate_item(window,second_cloud.file.get_uri(),"Cloud Choose");assert(second_activated==1&&activated==2);
    places.entries.remove(second_cloud);places.changed();yield pause_layout();
    yield popup_for(window,cloud.file.get_uri());places.entries.remove(cloud);places.changed();yield pause_layout();assert(sidebar_popup(window)==null&&activated==2);
    // Release the private exporter and consumer through normal scope teardown.
    stdout.printf("PASS cloud provider parameters, disabled command, submenu, disconnection\n");stdout.flush();
}
int main(string[] args){only_cloud=args.length>1&&args[1]=="--cloud-only";Log.set_always_fatal(LogLevelFlags.LEVEL_ERROR | LogLevelFlags.LEVEL_CRITICAL);Gtk.init();Adw.init();var loop=new MainLoop();int status=0;exercise.begin(args.length>1&&args[1]=="--diagnose",(o,r)=>{try{exercise.end(r);}catch(Error e){stderr.printf("%s\n",e.message);status=1;}loop.quit();});loop.run();return status;}
