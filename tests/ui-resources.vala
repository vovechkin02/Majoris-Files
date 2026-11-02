namespace MajorisFiles {
    // Instantiate through GObject, as GtkBuilder does. Constructor dependencies
    // are deliberately not invoked: this verifies templates independently of I/O.
    int main(string[] args) {
        Test.init(ref args);
        Adw.init();
        typeof(Adw.AboutDialog).ensure();
        Type[] types = {
            typeof(AclDialog),
            typeof(AnimatedImageView),
            typeof(ApplicationChoiceRow),
            typeof(ApplicationLaunchRow),
            typeof(AssociationChooser),
            typeof(AssociationsDialog),
            typeof(AssociationsPage),
            typeof(BatchRenameDialog),
            typeof(Browser),
            typeof(ChecksumDialog),
            typeof(ChooserChoiceRow),
            typeof(ChooserWindow),
            typeof(ColumnSettingsRow),
            typeof(ConflictPreviewPair),
            typeof(CopyPropertiesRow),
            typeof(DestinationRow),
            typeof(DeviceHardwarePage),
            typeof(DeviceIdentity),
            typeof(DevicePropertiesDialog),
            typeof(DeviceUsageRow),
            typeof(FileOperationsView),
            typeof(FileOperationsWindow),
            typeof(FilenameCell),
            typeof(FilesWindow),
            typeof(GridFileItem),
            typeof(ImageView),
            typeof(ListFileItem),
            typeof(MarkdownView),
            typeof(MediaPreviewWidget),
            typeof(MetadataCell),
            typeof(MetadataList),
            typeof(MetadataPage),
            typeof(MultiSelectionDetails),
            typeof(NavigationFields),
            typeof(NearbySendDialog),
            typeof(OperationJobRow),
            typeof(PasswordDialog),
            typeof(PdfView),
            typeof(PermissionsDialog),
            typeof(PermissionsPage),
            typeof(PlainTextPreview),
            typeof(PreferencesDialog),
            typeof(PreviewPane),
            typeof(PromptDialog),
            typeof(PropertiesDialog),
            typeof(PropertiesInformationRow),
            typeof(PropertiesSubpage),
            typeof(QuickPreviewWindow),
            typeof(RenamePreviewRow),
            typeof(SearchFilters),
            typeof(SevenZipDialog),
            typeof(SharedFolderRow),
            typeof(SharedFoldersDialog),
            typeof(SharingAccountRow),
            typeof(SharingDialog),
            typeof(SharingPage),
            typeof(ShortcutsDialog),
            typeof(SidebarRow),
            typeof(SmbPasswordDialog),
            typeof(SplitDialog),
            typeof(TagAssignmentDialog),
            typeof(TagAssignmentRow),
            typeof(TagManageRow),
            typeof(TagMarker),
            typeof(TagNameEditor),
            typeof(TagPalette),
            typeof(TagsDialog),
            typeof(TextPreviewWidget),
            typeof(ValueRow),
            typeof(ViewSettingsDialog)
        };
        foreach (var type in types) type.ensure();
        foreach (var type in types) {
            Test.message("Constructing %s", type.name());
            if (type == typeof(Browser)) continue; // Dependency-injected construction is covered by ui-tests.
            var widget = (Gtk.Widget)Object.new(type);
            widget.ref_sink();
            if (type == typeof(SplitDialog)) {
                var units = (Adw.ComboRow)widget.get_template_child(type, "units");
                var amount = (Gtk.SpinButton)widget.get_template_child(type, "amount");
                assert(units.selected == 2 && amount.value == 2048);
                assert(amount.numeric && amount.adjustment.page_increment == 10 && amount.adjustment.upper == 4000000000);
            }
            if (type == typeof(BatchRenameDialog)) {
                var mode = (Adw.ComboRow)widget.get_template_child(type, "mode");
                assert(mode.selected == 3);
            }
            if (type == typeof(GridFileItem)) {
                var tile = (GridFileItem)widget;
                assert(tile.filename.label.wrap && tile.filename.label.lines == 2);
            }
            if (type == typeof(ListFileItem)) {
                var row = (ListFileItem)widget;
                assert(!row.filename.label.wrap && row.filename.label.max_width_chars == 50);
            }
            var window = widget as Gtk.Window;
            if (window != null) window.destroy();
        }
        foreach (var name in resources_enumerate_children("/com/majoris/files/ui/", ResourceLookupFlags.NONE)) {
            var path = "/com/majoris/files/ui/" + name;
            var bytes = resources_lookup_data(path, ResourceLookupFlags.NONE);
            string xml = (string)bytes.get_data();
            if (!xml.contains("<template")) {
                Test.message("Parsing %s", path);
                new Gtk.Builder.from_resource(path);
            }
        }
        var menus = new Gtk.Builder.from_resource("/com/majoris/files/ui/menus.ui");
        assert(menus.get_object("application_menu") is MenuModel);
        assert(menus.get_object("tab_menu") is MenuModel);
        var controls = new Gtk.Builder.from_resource("/com/majoris/files/ui/navigation-controls.ui");
        assert(controls.get_object("address_fields") is NavigationFields);
        // Exercise the real constructor and action ancestry, including the
        // Browser dependency injection that bare GObject construction omits.
        try {
            string directory = DirUtils.make_tmp("majoris-template-actions-XXXXXX");
            var metadata = new MetadataStore(Path.build_filename(directory, "state.db"));
            metadata.set_state("notifications", "false");
            var app = new Adw.Application("com.majoris.files.template-tests", ApplicationFlags.NON_UNIQUE);
            app.register(null);
            var window = new FilesWindow(app, metadata, new Places(metadata), new OperationManager(metadata), File.new_for_path(directory));
            var overview = (Adw.TabOverview)window.content;
            var toggle = find_button(window, "Tab Overview");
            assert(toggle != null);
            toggle.clicked(); assert(overview.open);
            toggle.clicked(); assert(!overview.open);
            var tabs = window.tabs;
            int count = tabs.n_pages;
            assert(((Gtk.Widget)window).activate_action("win.new-tab", null));
            assert(window.tabs == tabs && tabs.n_pages == count + 1);
            window.destroy();
        } catch (Error e) { error("Template action fixture failed: %s", e.message); }
        return 0;
    }
    Gtk.Button? find_button(Gtk.Widget widget, string tooltip) {
        if (widget is Gtk.Button && widget.tooltip_text == tooltip) return (Gtk.Button)widget;
        for (var child = widget.get_first_child(); child != null; child = child.get_next_sibling()) {
            var found = find_button(child, tooltip);
            if (found != null) return found;
        }
        return null;
    }
}


