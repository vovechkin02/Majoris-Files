using MajorisFiles;
string fixture;
string output;
string inventory;
TestSharing helper;
class TestSharing : Object, SharingProxy {
    public int mutations;
    public bool hidden;
    public async bool visibility_supported() throws DBusError, IOError { return true; }
    public async string firewall_backend() throws DBusError, IOError { return "firewalld"; }
    public async bool get_hidden(string share) throws DBusError, IOError { return hidden; }
    public async void set_hidden(string share, bool value) throws DBusError, IOError { mutations++; hidden = value; }
    public async void enable_services() throws DBusError, IOError { mutations++; }
    public async void provision_password(string password) throws DBusError, IOError { mutations++; }
    public async void configure_firewall(bool enabled) throws DBusError, IOError { mutations++; }
    public async void reconcile_firewall() throws DBusError, IOError { mutations++; }
    public async string get_clients(string share) throws DBusError, IOError { return "[]"; }
}
class TestCloud : Object, CloudFileProvider {
    File location;
    public File root { get { return location; } }
    public TestCloud(File root) { location = root; }
    public async CloudFileState query(File file, Cancellable token) throws Error {
        token.set_error_if_cancelled();
        if (file.get_basename().contains("error")) throw new IOError.FAILED("Fixture provider unavailable");
        var state = new CloudFileState(); state.state = "online-only"; state.quota_known = true; state.quota_used = 100; state.quota_total = 1000; return state;
    }
    public async File perform(File file, string action, uint64 maximum_bytes, Cancellable token, CloudProgress? progress = null) throws Error { throw new IOError.NOT_SUPPORTED("Fixture is read-only"); }
}
struct TestProperty { public string title; public string value; }
[DBus(name="com.majoris.Files.Extension1")]
class TestExtension : Object {
    public uint get_version() throws DBusError, IOError { return 1; }
    public HashTable<string,string> get_file_info(string uri) throws DBusError, IOError { var fields = new HashTable<string,string>(str_hash, str_equal); fields["Unrecognised Provider Field"] = "Preserved metadata"; return fields; }
    public TestProperty[] get_properties(string uri) throws DBusError, IOError { return {TestProperty() {title="Fixture Property", value="Preserved property"}}; }
}
Gtk.Widget? titled(Gtk.Widget widget, string title, bool mapped = false) {
    if ((!mapped || widget.get_mapped()) && widget is Adw.PreferencesRow && ((Adw.PreferencesRow)widget).title == title) return widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) { var found = titled(child, title, mapped); if (found != null) return found; }
    return null;
}
Gtk.Widget? typed(Gtk.Widget widget, Type type) {
    if (widget.get_type().is_a(type) && widget.get_mapped()) return widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) { var found = typed(child, type); if (found != null) return found; }
    return null;
}
Gtk.Button? button_label(Gtk.Widget widget, string text) {
    if (widget is Gtk.Button && ((Gtk.Button)widget).label == text) return (Gtk.Button)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) { var found = button_label(child, text); if (found != null) return found; } return null;
}
FileItem item(File file, string? mime = null) throws Error {
    var info = file.query_info(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
    if (mime != null) info.set_content_type(mime); return new FileItem(file, info);
}
Gee.ArrayList<FileItem> selection(FileItem a, FileItem? b = null) { var items = new Gee.ArrayList<FileItem>(); items.add(a); if (b != null) items.add(b); return items; }
string information_value(PropertiesDialog dialog, string title) {
    var row = titled(dialog.general, title) as PropertiesInformationRow; assert(row != null);
    assert(row.value_label.xalign == 1 && row.value_label.selectable && !row.value_label.wrap);
    assert(row.subtitle == "" || row.subtitle == null);
    return row.value;
}
void assert_identity(PropertiesDialog dialog, string name) {
    assert(dialog.identity_name.label == name && dialog.identity_name.wrap && dialog.identity_name.selectable);
    assert(dialog.identity.get_first_child() is Gtk.Image);
    assert(((Gtk.Image)dialog.identity.get_first_child()).pixel_size == 48);
    assert(dialog.identity.get_first_child().get_next_sibling() == dialog.identity_name);
    if (dialog.items.size == 1) {
        var icons = dialog.identity_name.get_next_sibling() as Gtk.MenuButton;
        assert(icons != null && icons.label == "Icon…" && !icons.popover.has_arrow);
        assert(icons.menu_model.get_n_items() == 2 && icons.get_next_sibling() == null);
    } else assert(dialog.identity_name.get_next_sibling() == null);
    assert(titled(dialog.general, name) == null);
}
void collect_information(Gtk.Widget widget, Gee.ArrayList<string> titles) {
    if (widget is PropertiesInformationRow) titles.add(((PropertiesInformationRow)widget).title);
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) collect_information(child, titles);
}
void assert_information_order(PropertiesDialog dialog, string[] expected) {
    var titles = new Gee.ArrayList<string>(); collect_information(dialog.general, titles);
    assert(titles.size == expected.length);
    for (int i = 0; i < expected.length; i++) assert(titles[i] == expected[i]);
}
async void wait_scan(PropertiesDialog dialog) {
    for (int i = 0; information_value(dialog, "Size").contains("Calculating") && i < 40; i++) yield pause_layout();
    assert(!information_value(dialog, "Size").contains("Calculating"));
}
void restore_fixture(File folder) { try { folder.set_attribute_uint32("unix::mode", 0700, FileQueryInfoFlags.NONE); } catch (Error e) { warning("%s", e.message); } }
async void counting_cases(Adw.ApplicationWindow window, MetadataStore metadata, FileItem document) throws Error {
    var empty = File.new_for_path(fixture + "/Empty"); empty.make_directory();
    var dialog = new PropertiesDialog(window, selection(item(empty)), metadata);
    var name_widget = dialog.identity_name; var icon_widget = dialog.identity.get_first_child();
    assert(information_value(dialog, "Size") == "Calculating…");
    dialog.present(window); yield wait_scan(dialog);
    assert(information_value(dialog, "Size") == Paths.size(0)); assert(information_value(dialog, "Contents") == "0 items");
    assert(dialog.identity_name == name_widget && dialog.identity.get_first_child() == icon_widget); assert_identity(dialog, "Empty");
    dialog.close(); yield pause_layout();
    var large = File.new_for_path(fixture + "/Large"); large.make_directory();
    for (int i = 0; i < 1500; i++) FileUtils.set_contents(large.get_child("file-%04d.txt".printf(i)).get_path(), "abc");
    dialog = new PropertiesDialog(window, selection(item(large)), metadata); name_widget = dialog.identity_name; icon_widget = dialog.identity.get_first_child();
    dialog.present(window); yield wait_scan(dialog);
    assert(information_value(dialog, "Size") == Paths.size(4500)); assert(information_value(dialog, "Contents") == "1500 items");
    assert(dialog.identity_name == name_widget && dialog.identity.get_first_child() == icon_widget); assert_identity(dialog, "Large");
    dialog.close(); yield pause_layout();
    dialog = new PropertiesDialog(window, selection(item(large)), metadata); dialog.present(window); dialog.token.cancel(); dialog.close(); yield pause_layout();
    assert(dialog.token.is_cancelled()); string cancelled = information_value(dialog, "Size"); yield pause_layout(); assert(information_value(dialog, "Size") == cancelled);
    var partial = File.new_for_path(fixture + "/Partial"); partial.make_directory();
    FileUtils.set_contents(partial.get_child("visible.txt").get_path(), "visible"); var locked = partial.get_child("Locked"); locked.make_directory();
    FileUtils.set_contents(locked.get_child("secret.txt").get_path(), "secret"); locked.set_attribute_uint32("unix::mode", 0000, FileQueryInfoFlags.NONE);
    try {
        dialog = new PropertiesDialog(window, selection(item(partial)), metadata); dialog.present(window); yield wait_scan(dialog);
        assert(information_value(dialog, "Size").contains("Partial total")); assert(information_value(dialog, "Contents").contains("unreadable")); assert_identity(dialog, "Partial");
        dialog.close(); yield pause_layout();
    } finally { restore_fixture(locked); }
    var other = empty.get_child("other.txt"); FileUtils.set_contents(other.get_path(), "other");
    dialog = new PropertiesDialog(window, selection(document, item(other)), metadata); dialog.present(window); yield wait_scan(dialog);
    assert(information_value(dialog, "Location") == "Multiple locations" && find_copy(dialog.general) == null);
    assert(titled(dialog.general, "Modified") == null && titled(dialog.general, "Total Size") == null);
    dialog.close(); yield pause_layout();
    other.set_attribute_uint32("unix::mode", 0444, FileQueryInfoFlags.NONE);
    dialog = new PropertiesDialog(window, selection(item(other)), metadata); dialog.present(window); yield pause_layout();
    assert(information_value(dialog, "Size") == Paths.size(5)); assert_identity(dialog, "other.txt"); dialog.close(); yield pause_layout();
}
async void shot(Gtk.Window window, string name) throws Error {
    Test.message("stage: %s", name);
    foreach (bool dark in new bool[] {false, true}) {
        Adw.StyleManager.get_default().color_scheme = dark ? Adw.ColorScheme.FORCE_DARK : Adw.ColorScheme.FORCE_LIGHT;
        if (output != "") { DirUtils.create_with_parents(output, 0755); yield capture(window, output, name + (dark ? "-dark" : "-light")); }
    }
}
async void keyboard_back(Adw.ApplicationWindow window) throws Error {
    string? previous = window.title; window.title = "Majoris Properties Regression";
    var focus = new Subprocess.newv({"xdotool", "search", "--onlyvisible", "--name", "^Majoris Properties Regression$", "windowfocus", "--sync"}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE); yield focus.wait_check_async(null);
    var key = new Subprocess.newv({"xdotool", "key", "--clearmodifiers", "alt+Left"}, SubprocessFlags.STDOUT_SILENCE | SubprocessFlags.STDERR_PIPE); yield key.wait_check_async(null); yield pause_layout(); window.title = previous;
}
async void scenarios() throws Error {
    var bus = yield Bus.get(BusType.SYSTEM); helper = new TestSharing(); bus.register_object<SharingProxy>("/com/majoris/Files/Sharing", helper);
    bool owned = false; Bus.own_name_on_connection(bus, "com.majoris.Files.Sharing", BusNameOwnerFlags.NONE, () => owned = true);
    while (!owned) yield pause_layout();
    var app = new Adw.Application("com.majoris.files.propertiescheck", ApplicationFlags.NON_UNIQUE); app.register(null);
    var window = new Adw.ApplicationWindow(app); window.set_default_size(900, 760); window.content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0); window.present();
    var metadata = new MetadataStore(Path.build_filename(fixture, "metadata.db"));
    var session = yield Bus.get(BusType.SESSION); var extension_service = new TestExtension(); session.register_object<TestExtension>("/com/majoris/Files/PropertiesFixture", extension_service);
    bool extension_owned = false; Bus.own_name_on_connection(session, "com.majoris.Files.PropertiesFixture", BusNameOwnerFlags.NONE, () => extension_owned = true); while (!extension_owned) yield pause_layout();
    string manifest = fixture + "/fixture.extension";
    FileUtils.set_contents(manifest, "[Extension]\nId=properties-fixture\nName=Properties & Fixture\nVersion=1\nBusName=com.majoris.Files.PropertiesFixture\nObjectPath=/com/majoris/Files/PropertiesFixture\nCapabilities=metadata;properties;\n");
    ExtensionManager.get_default(metadata).extensions.add(new ExternalExtension(manifest, true, metadata));

    var document = item(File.new_for_path(Path.build_filename(fixture, "Annual Report — 年次.txt")), "application/x-majoris-properties-test");
    var folder = item(File.new_for_path(Path.build_filename(fixture, "Projects")));
    var image = item(File.new_for_path(Path.build_filename(fixture, "image.png")));
    var video = item(File.new_for_path(Path.build_filename(fixture, "video.ogv")));
    var audio = item(File.new_for_path(Path.build_filename(fixture, "audio.wav")));
    var selected = selection(document);
    var properties = new PropertiesDialog(window, selected, metadata); properties.present(window); yield pause_layout();
    assert(properties.get_visible_page() == properties.general);
    assert_identity(properties, document.name);
    assert_information_order(properties, {"Type", "Size", "Location", "Modified"});
    assert(information_value(properties, "Type") == "File" && information_value(properties, "Size") == Paths.size(6));
    assert(titled(properties.general, "Items") == null && titled(properties.general, "Contents") == null);
    assert(titled(properties.general, "Owner") == null && titled(properties.general, "Sharing") == null);
    selected.clear(); assert(properties.items.size == 1);
    var favorite = (Adw.SwitchRow)titled(properties.general, "Favorite"); favorite.active = true; assert(metadata.favorite(document.file));
    ((Adw.ActionRow)titled(properties.general, "Tags")).activated(); yield pause_layout();
    var prompt = typed(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(prompt != null);
    ((Gtk.Entry)prompt.extra_child).text = "Work, Reports"; prompt.response("apply"); prompt.close(); yield pause_layout(); assert(metadata.tags(document.file).contains("Work"));
    var copy = find_copy(properties.general); assert(copy != null); copy.clicked();
    string? clipboard = yield window.get_clipboard().read_text_async(null); assert(clipboard == document.file.get_path());
    yield shot(window, "general-document");
    var long_name = "Annual_Report_gjpqy_" + string.nfill(150, 'x') + " 年次.txt";
    var long_file = File.new_for_path(fixture + "/" + long_name); FileUtils.set_contents(long_file.get_path(), "long"); var long_item = item(long_file);
    var long_properties = new PropertiesDialog(window, selection(long_item), metadata); long_properties.present(window); yield pause_layout();
    assert_identity(long_properties, long_name); assert(long_properties.content_width == 560);
    yield shot(window, "general-long-name"); long_properties.close(); yield pause_layout();
    window.visible = false;
    var larger_text = new Gtk.CssProvider(); larger_text.load_from_string("* { font-size: 20px; }");
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), larger_text, Gtk.STYLE_PROVIDER_PRIORITY_USER + 10);
    var narrow = new Adw.ApplicationWindow(app); narrow.set_default_size(620, 720); narrow.content = new Gtk.Box(Gtk.Orientation.VERTICAL, 0); narrow.present();
    var large_properties = new PropertiesDialog(narrow, selection(long_item), metadata); large_properties.present(narrow);
    yield pause_layout(); yield shot(narrow, "general-large-text-narrow"); large_properties.close(); yield pause_layout(); narrow.destroy();
    Gtk.StyleContext.remove_provider_for_display(Gdk.Display.get_default(), larger_text); window.present(); yield pause_layout();

    ((Adw.ActionRow)titled(properties.general, "Permissions")).activated(); yield pause_layout();
    var permissions = typed(window, typeof(PermissionsPage)) as PermissionsPage; assert(permissions != null && !permissions.advanced.expanded && !permissions.apply.sensitive);
    yield shot(window, "permissions-basic"); permissions.advanced.expanded = true; yield pause_layout(); yield shot(window, "permissions-advanced");
    permissions.files.text = "0751"; assert(permissions.apply.sensitive); permissions.apply.clicked(); yield pause_layout();
    assert((document.file.query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 07777) == 0751);
    assert(!permissions.apply.sensitive);
    var owner_access = typed(permissions, typeof(Adw.ComboRow)) as Adw.ComboRow;
    if (owner_access.sensitive) { owner_access.selected = 1; assert(permissions.files.text == "0551"); permissions.apply.clicked(); yield pause_layout(); assert((document.file.query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 07777) == 0551); }
    assert(properties.pop_subpage()); yield pause_layout();
    ((Adw.ActionRow)titled(properties.general, "Permissions")).activated(); yield pause_layout(); assert(typed(window, typeof(PermissionsPage)) == permissions); assert(permissions.files.text == "0551" || permissions.files.text == "0751");
    yield keyboard_back(window); assert(!permissions.get_mapped() && !properties.token.is_cancelled());
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout();
    var current_details = typed(window, typeof(MetadataPage)) as MetadataPage;
    var current_mode = document.file.query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 07777;
    assert(((Adw.ActionRow)titled(current_details, "Mode")).subtitle == "%04o".printf(current_mode));
    assert(properties.pop_subpage()); yield pause_layout();
    var first = new DesktopAppInfo("majoris-test-a.desktop"); var second = new DesktopAppInfo("majoris-test-b.desktop"); assert(first != null && second != null);
    first.set_as_default_for_type(document.mime);
    var change = button_label(properties.general, "Change…"); assert(change != null); change.clicked(); yield pause_layout();
    var chooser = typed(window, typeof(AssociationChooser)) as AssociationChooser; assert(chooser != null);
    var default_button = button_label(chooser, "Set Default"); var reset_button = button_label(chooser, "Reset to System Default");
    assert(default_button.get_mapped() && reset_button.get_mapped());
    yield pause_layout();
    Graphene.Rect before_scroll, after_scroll, reset_bounds;
    assert(default_button.compute_bounds(chooser, out before_scroll));
    assert(reset_button.compute_bounds(chooser, out reset_bounds));
    assert(before_scroll.origin.y >= 0 && before_scroll.origin.y + before_scroll.size.height <= chooser.get_height());
    assert(reset_bounds.origin.x >= 0 && reset_bounds.origin.x + reset_bounds.size.width <= chooser.get_width());
    var app_scroll = typed(chooser, typeof(Gtk.ScrolledWindow)) as Gtk.ScrolledWindow; assert(app_scroll != null);
    app_scroll.vadjustment.value = app_scroll.vadjustment.upper;
    yield pause_layout(); assert(default_button.get_mapped() && reset_button.get_mapped());
    assert(default_button.compute_bounds(chooser, out after_scroll) && Math.fabs(after_scroll.origin.y - before_scroll.origin.y) <= 1);
    app_scroll.vadjustment.value = 0; yield pause_layout();
    yield shot(window, "application-chooser");
    ((Gtk.CheckButton)((Adw.ActionRow)titled(chooser, first.get_display_name())).activatable_widget).active = false; assert(chooser.selected == null && !button_label(chooser, "Set Default").sensitive);
    ((Gtk.CheckButton)((Adw.ActionRow)titled(chooser, second.get_display_name())).activatable_widget).active = true; assert(chooser.selected.equal(second)); chooser.apply_selected(); yield pause_layout();
    assert(AppInfo.get_default_for_type(document.mime, false).equal(second)); assert(titled(properties.general, second.get_display_name()) != null);
    assert(!FileUtils.test(Path.build_filename(fixture, "launched"), FileTest.EXISTS));
    change.clicked(); yield pause_layout(); chooser = typed(window, typeof(AssociationChooser)) as AssociationChooser;
    button_label(chooser, "Reset to System Default").clicked(); yield pause_layout();
    assert(!FileUtils.test(Path.build_filename(fixture, "launched"), FileTest.EXISTS));
    properties.close(); yield pause_layout(); assert(properties.token.is_cancelled());
    properties = new PropertiesDialog(window, selection(folder), metadata); properties.present(window); yield pause_layout();
    assert(button_label(properties.general, "Change…") == null && titled(properties.general, "Sharing") != null);
    yield wait_scan(properties); assert_identity(properties, folder.name);
    assert_information_order(properties, {"Type", "Size", "Contents", "Location", "Modified"});
    assert(information_value(properties, "Type") == "File folder" && information_value(properties, "Size") == Paths.size(5));
    assert(information_value(properties, "Contents") == "1 item");
    yield shot(window, "general-folder");
    ((Adw.ActionRow)titled(properties.general, "Sharing")).activated(); yield pause_layout();
    var sharing = typed(window, typeof(SharingPage)) as SharingPage; assert(sharing != null);
    var enabled = (Adw.SwitchRow)titled(sharing, "Share this folder"); assert(enabled.sensitive && !enabled.active);
    yield shot(window, "sharing-disabled"); int mutations = helper.mutations; enabled.active = true; yield pause_layout(); assert(helper.mutations == mutations);
    var allowed = (Adw.ExpanderRow)titled(sharing, "Allowed Users"); allowed.expanded = true; yield pause_layout();
    var authenticated = (Adw.SwitchRow)titled(sharing, "All Authenticated Users"); var guest = (Adw.SwitchRow)titled(sharing, "Allow Guest Access");
    guest.active = true; authenticated.active = false; assert(!guest.active && !guest.sensitive);
    var assignment = typed(sharing, typeof(Gtk.CheckButton)) as Gtk.CheckButton; assert(assignment != null); assignment.active = true;
    var level = typed(sharing, typeof(Gtk.DropDown)) as Gtk.DropDown; assert(level != null); level.selected = 1;
    authenticated.active = true;
    assert(((Adw.SwitchRow)titled(sharing, "Read and Write")).subtitle == "Custom Access");
    allowed.expanded = false;
    assert(button_label(sharing, "Share Folder").get_mapped()); button_label(sharing, "Share Folder").clicked(); yield pause_layout();
    assert(helper.mutations > mutations); yield shot(window, "sharing-enabled");
    var advanced_sharing = (Adw.ExpanderRow)titled(sharing, "Advanced Sharing Settings"); advanced_sharing.expanded = true; yield pause_layout();
    assert(button_label(sharing, "Allow SMB on Home and Work Networks…") != null && button_label(sharing, "Inspect Connected Clients…") != null);
    yield shot(window, "sharing-advanced");
    button_label(sharing, "Stop Sharing").clicked(); yield pause_layout(); prompt = typed(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(prompt != null); prompt.response("cancel"); prompt.close(); yield pause_layout(); assert(enabled.active);
    FileUtils.set_contents(inventory, "[Projects]\npath=" + folder.file.get_path() + "\nusershare_acl=Everyone:F\nguest_ok=n\n");
    var reload = button_label(sharing, "Reload Sharing State");
    for (int attempt = 0; !reload.get_mapped() && attempt < 24; attempt++) yield pause_layout();
    assert(reload.get_mapped() && !button_label(sharing, "Apply Changes").sensitive && !enabled.sensitive);
    reload.clicked(); yield pause_layout(); assert(enabled.sensitive);
    button_label(sharing, "Stop Sharing").clicked(); yield pause_layout(); prompt = typed(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(prompt != null);
    prompt.response("apply"); prompt.close(); yield pause_layout(); assert(!enabled.active);
    string remaining; FileUtils.get_contents(inventory, out remaining); assert(remaining == "");
    assert(properties.pop_subpage()); yield pause_layout(); properties.close(); yield pause_layout();
    assert(!PropertiesDialog.shareable(item(File.new_for_path("/"))));
    properties = new PropertiesDialog(window, selection(image), metadata); properties.present(window); yield pause_layout(); yield shot(window, "general-image");
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout(); yield pause_layout();
    var details = typed(window, typeof(MetadataPage)) as MetadataPage; assert(details != null && titled(details, "Dimensions") != null && titled(details, "Video Codec") == null);
    assert(titled(details, "Unrecognised Provider Field") != null && titled(details, "Fixture Property") != null);
    yield shot(window, "details-image"); assert(properties.pop_subpage()); yield pause_layout(); properties.close(); yield pause_layout();
    properties = new PropertiesDialog(window, selection(audio), metadata); properties.present(window); yield pause_layout();
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout(); yield pause_layout(); yield shot(window, "details-multimedia"); properties.close(); yield pause_layout();
    properties = new PropertiesDialog(window, selection(video), metadata); properties.present(window); yield pause_layout();
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout(); yield pause_layout();
    details = typed(window, typeof(MetadataPage)) as MetadataPage; assert(titled(details, "Video Codec") != null && titled(details, "Audio Codec") == null);
    yield shot(window, "details-video"); properties.close(); yield pause_layout();
    properties = new PropertiesDialog(window, selection(document, folder), metadata); properties.present(window); yield pause_layout();
    assert(titled(properties.general, "Sharing") == null && button_label(properties.general, "Change…") == null);
    var all = (Adw.SwitchRow)titled(properties.general, "Favorite All Selected Items"); all.active = true; assert(metadata.favorite(document.file) && metadata.favorite(folder.file));
    yield wait_scan(properties); assert_identity(properties, "2 selected items");
    assert_information_order(properties, {"Type", "Size", "Location"});
    assert(information_value(properties, "Type") == "Mixed files and folders"); assert(information_value(properties, "Size") == Paths.size(11));
    assert(titled(properties.general, "Total Size") == null && titled(properties.general, "Types") == null);
    yield shot(window, "general-multiple");
    ((Adw.ActionRow)titled(properties.general, "Tags")).activated(); yield pause_layout(); prompt = typed(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(prompt != null);
    ((Gtk.Entry)prompt.extra_child).text = "Shared"; prompt.response("apply"); prompt.close(); yield pause_layout(); assert(metadata.tags(document.file) == "Shared" && metadata.tags(folder.file) == "Shared");
    ((Adw.ActionRow)titled(properties.general, "Permissions")).activated(); yield pause_layout(); permissions = typed(window, typeof(PermissionsPage)) as PermissionsPage;
    assert(!permissions.apply.sensitive);
    permissions.files.text = "0640"; permissions.folders.text = "0750"; permissions.apply.clicked(); yield pause_layout();
    assert((document.file.query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 07777) == 0640);
    assert((folder.file.query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 07777) == 0750);
    ((Adw.ActionRow)titled(permissions, "Apply to enclosed files…")).activated();
    assert((folder.file.get_child("notes.txt").query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 0777) == 0644);
    permissions.apply.clicked(); yield pause_layout(); prompt = typed(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(prompt != null); prompt.response("cancel"); prompt.close(); yield pause_layout();
    assert((folder.file.get_child("notes.txt").query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 0777) == 0644);
    permissions.apply.clicked(); yield pause_layout(); prompt = typed(window, typeof(Adw.AlertDialog)) as Adw.AlertDialog; assert(prompt != null); prompt.response("apply"); prompt.close(); yield pause_layout();
    assert((folder.file.get_child("notes.txt").query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 0777) == 0640);
    properties.close(); yield pause_layout();
    // Masked basic changes preserve executable and special bits, including mixed selections.
    var executable = File.new_for_path(Path.build_filename(fixture, "executable")); FileUtils.set_contents(executable.get_path(), "fixture"); executable.set_attribute_uint32("unix::mode", 02751, FileQueryInfoFlags.NONE);
    var roots = new Gee.ArrayList<File>(); roots.add(executable);
    yield PermissionService.apply(roots, 0020, 0, false, null, null, new Cancellable(), 0060, 0);
    assert((executable.query_info("unix::mode", FileQueryInfoFlags.NONE).get_attribute_uint32("unix::mode") & 07777) == 02731);
    assert(PermissionService.mode("4755") == 04755);
    if (Environment.find_program_in_path("getfacl") != null && Environment.find_program_in_path("setfacl") != null) {
        string acl = "user::rwx\nuser:65534:r--\ngroup::r-x\nmask::r-x\nother::--x\n";
        yield PermissionService.write_acl(executable, acl);
        string loaded = yield PermissionService.read_acl(executable); assert(loaded.contains("user:nobody:r--") || loaded.contains("user:65534:r--"));
        properties = new PropertiesDialog(window, selection(item(executable)), metadata); properties.present(window); yield pause_layout();
        ((Adw.ActionRow)titled(properties.general, "Permissions")).activated(); yield pause_layout();
        permissions = typed(window, typeof(PermissionsPage)) as PermissionsPage;
        assert(!((Adw.ComboRow)titled(permissions, "Others")).sensitive);
        properties.close(); yield pause_layout();
        yield PermissionService.apply(roots, 0600, 0, false, null, null, new Cancellable(), 0600, 0);
        loaded = yield PermissionService.read_acl(executable); assert(loaded.contains("user:nobody:r--") || loaded.contains("user:65534:r--"));
    }
    assert(MetadataPage.classify("Unrecognised Provider Field", "image/png") == "Additional Metadata");
    Test.message("stage: remote");
    var remote_file = File.new_for_uri("sftp://example.invalid/Reports/very-long-location-very-long-location-very-long-location-very-long-location-very-long-location-very-long-location-very-long-location-very-long-location-/年度.txt");
    var remote_info = new FileInfo(); remote_info.set_display_name("年度.txt"); remote_info.set_file_type(FileType.REGULAR); remote_info.set_content_type(document.mime); remote_info.set_size(100);
    var remote = new FileItem(remote_file, remote_info);
    properties = new PropertiesDialog(window, selection(remote), metadata); properties.present(window); yield pause_layout();
    assert(titled(properties.general, "Sharing") == null); find_copy(properties.general).clicked(); clipboard = yield window.get_clipboard().read_text_async(null); assert(clipboard == remote_file.get_uri());
    button_label(properties.general, "Change…").clicked(); yield pause_layout(); chooser = typed(window, typeof(AssociationChooser)) as AssociationChooser;
    assert(!titled(chooser, second.get_display_name()).sensitive); chooser.close(); yield pause_layout();
    ((Adw.ActionRow)titled(properties.general, "Permissions")).activated(); yield pause_layout();
    assert(titled(properties, "Permissions unavailable") != null); properties.close(); yield pause_layout();
    remote_info.remove_attribute("standard::size");
    properties = new PropertiesDialog(window, selection(new FileItem(remote_file, remote_info)), metadata); properties.present(window); yield pause_layout();
    assert_identity(properties, remote.name); assert(information_value(properties, "Type") == "File" && information_value(properties, "Size") == "Unavailable");
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout();
    assert(((Adw.ActionRow)titled(properties, "Exact Size")).subtitle == "Unavailable"); properties.close(); yield pause_layout();
    var mount_info = folder.info.dup(); mount_info.set_attribute_boolean("unix::is-mountpoint", true); assert(!PropertiesDialog.shareable(new FileItem(folder.file, mount_info)));
    var link = File.new_for_path(fixture + "/Project Link"); link.make_symbolic_link(folder.file.get_path());
    var link_item = item(link); link_item.resolved_directory = true;
    properties = new PropertiesDialog(window, selection(link_item), metadata); properties.present(window); yield pause_layout();
    assert_identity(properties, link_item.name); assert(information_value(properties, "Type") == "Symbolic link");
    assert(titled(properties.general, "Contents") == null && titled(properties.general, "Sharing") == null);
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout(); assert(titled(properties, "Link Target") != null);
    properties.close(); yield pause_layout();
    Test.message("stage: cloud");
    var cloud_root = File.new_for_path(fixture + "/cloud"); cloud_root.make_directory();
    var cloud_file = cloud_root.get_child("cloud.txt"); FileUtils.set_contents(cloud_file.get_path(), "cloud fixture");
    var failed = cloud_root.get_child("error.png"); image.file.copy(failed, FileCopyFlags.NONE);
    CloudFiles.get_default().register_provider(new TestCloud(cloud_root));
    properties = new PropertiesDialog(window, selection(item(cloud_file)), metadata); properties.present(window); yield pause_layout();
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout();
    details = typed(window, typeof(MetadataPage)) as MetadataPage;
    assert(titled(details, "Sync State") != null && titled(details, "Account Storage") != null && titled(details, "Online Only") != null);
    properties.close(); yield pause_layout();
    properties = new PropertiesDialog(window, selection(item(failed)), metadata); properties.present(window); yield pause_layout();
    ((Adw.ActionRow)titled(properties.general, "Details")).activated(); yield pause_layout(); yield pause_layout();
    details = typed(window, typeof(MetadataPage)) as MetadataPage;
    assert(titled(details, "Unavailable") != null && titled(details, "Dimensions") != null && titled(details, "Fixture Property") != null);
    properties.close(); yield pause_layout();
    yield counting_cases(window, metadata, document);
    var previous_default = AppInfo.get_default_for_type(document.mime, false);
    var standalone = new AssociationsDialog(window, document); yield pause_layout();
    var open_row = titled(standalone, first.get_display_name()); assert(open_row != null);
    var open_once = button_label(open_row, "Open"); assert(open_once != null); open_once.clicked();
    for (int attempt = 0; !FileUtils.test(fixture + "/launched", FileTest.EXISTS) && attempt < 10; attempt++) yield pause_layout();
    assert(FileUtils.test(fixture + "/launched", FileTest.EXISTS));
    var after_open = AppInfo.get_default_for_type(document.mime, false);
    assert(previous_default == null ? after_open == null : after_open != null && previous_default.equal(after_open));
    window.destroy();
}
Gtk.Button? find_copy(Gtk.Widget widget) {
    if (widget is Gtk.Button && widget.tooltip_text == "Copy Location") return (Gtk.Button)widget;
    for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) { var found = find_copy(child); if (found != null) return found; } return null;
}
int main(string[] args) {
    try {
        fixture = DirUtils.make_tmp("majoris-properties-XXXXXX");
        Environment.set_variable("HOME", fixture, true); Environment.set_variable("XDG_CONFIG_HOME", fixture + "/config", true); Environment.set_variable("XDG_DATA_HOME", fixture + "/data", true); Environment.set_variable("XDG_CACHE_HOME", fixture + "/cache", true);
        Environment.set_variable("DBUS_SYSTEM_BUS_ADDRESS", Environment.get_variable("DBUS_SESSION_BUS_ADDRESS"), true);
        DirUtils.create_with_parents(fixture + "/data/applications", 0700); DirUtils.create_with_parents(fixture + "/bin", 0700); DirUtils.create(fixture + "/Projects", 0700);
        FileUtils.set_contents(fixture + "/Annual Report — 年次.txt", "report"); FileUtils.set_contents(fixture + "/Projects/notes.txt", "notes");
        FileUtils.set_contents(fixture + "/launch", "#!/bin/sh\ntouch '" + fixture + "/launched'\n"); File.new_for_path(fixture + "/launch").set_attribute_uint32("unix::mode", 0700, FileQueryInfoFlags.NONE);
        foreach (var letter in new string[] {"a", "b"}) FileUtils.set_contents(fixture + "/data/applications/majoris-test-" + letter + ".desktop", "[Desktop Entry]\nType=Application\nName=Majoris Test Viewer " + letter + "\nExec=" + fixture + "/launch " + (letter == "a" ? "%U" : "%F") + "\nMimeType=application/x-majoris-properties-test;\n");
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 640, 360); var context = new Cairo.Context(surface); context.set_source_rgb(0.2, 0.5, 0.7); context.paint(); surface.write_to_png(fixture + "/image.png");
        var media = new Subprocess.newv({"python3", "-c", "import wave; w=wave.open(__import__('sys').argv[1], 'wb'); w.setparams((1,2,8000,0,'NONE','')); w.writeframes(bytes(16000)); w.close()", fixture + "/audio.wav"}, SubprocessFlags.NONE); media.wait_check();
        var video_fixture = new Subprocess.newv({"gst-launch-1.0", "-q", "videotestsrc", "num-buffers=30", "!", "video/x-raw,width=160,height=90", "!", "theoraenc", "!", "oggmux", "!", "filesink", "location=" + fixture + "/video.ogv"}, SubprocessFlags.STDERR_PIPE); video_fixture.wait_check();
        inventory = fixture + "/shares"; FileUtils.set_contents(inventory, ""); Environment.set_variable("MAJORIS_TEST_SHARES", inventory, true);
        FileUtils.set_contents(fixture + "/bin/net", "#!/usr/bin/python3\nimport os,sys\np=os.environ['MAJORIS_TEST_SHARES']\nif sys.argv[2]=='info': print(open(p).read())\nelif sys.argv[2]=='add': open(p,'w').write('[%s]\\npath=%s\\nusershare_acl=%s\\nguest_ok=%s\\n'%(sys.argv[3],sys.argv[4],sys.argv[6],sys.argv[7].split('=')[1]))\nelif sys.argv[2]=='delete': open(p,'w').write('')\n"); File.new_for_path(fixture + "/bin/net").set_attribute_uint32("unix::mode", 0700, FileQueryInfoFlags.NONE);
        Environment.set_variable("PATH", fixture + "/bin:" + Environment.get_variable("PATH"), true);
        var update = new Subprocess.newv({"update-desktop-database", fixture + "/data/applications"}, SubprocessFlags.NONE); update.wait_check();
    } catch (Error e) { error("%s", e.message); }
    output = Environment.get_variable("MAJORIS_PROPERTIES_EVIDENCE") ?? "";
    Test.init(ref args); Gtk.init(); Adw.init();
    Test.add_func("/properties/redesign", () => { var loop = new MainLoop(); scenarios.begin((obj, res) => { try { scenarios.end(res); } catch (Error e) { error("%s", e.message); } loop.quit(); }); loop.run(); });
    return Test.run();
}
