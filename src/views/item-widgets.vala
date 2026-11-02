namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/grid-item.ui")]
    public class GridFileItem : Gtk.Box {
        private bool template_disposing;
        static construct { typeof(FilenameCell).ensure(); }
        [GtkChild] public unowned Gtk.Image icon;
        [GtkChild] public unowned Gtk.Overlay icon_area;
        [GtkChild] public unowned Gtk.Image cloud_badge;
        [GtkChild] public unowned FilenameCell filename;
        [GtkChild] public unowned Gtk.Label caption;
        [GtkChild] public unowned Gtk.CheckButton checkbox;
        public GridFileItem() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(GridFileItem));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/list-item.ui")]
    public class ListFileItem : Gtk.Box {
        private bool template_disposing;
        static construct { typeof(FilenameCell).ensure(); }
        [GtkChild] public unowned Gtk.Image icon;
        [GtkChild] public unowned Gtk.Overlay icon_area;
        [GtkChild] public unowned Gtk.Image cloud_badge;
        [GtkChild] public unowned FilenameCell filename;
        [GtkChild] public unowned Gtk.Label caption;
        [GtkChild] public unowned Gtk.CheckButton checkbox;
        public ListFileItem() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ListFileItem));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/metadata-cell.ui")]
    public class MetadataCell : Gtk.Box {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Label label;
        public MetadataCell() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(MetadataCell));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/sidebar-row.ui")]
    public class SidebarRow : Gtk.ListBoxRow {
        private bool template_disposing;
        static construct { typeof(TagMarker).ensure(); }
        [GtkChild] public unowned Gtk.Image icon;
        [GtkChild] public unowned Gtk.Label label;
        [GtkChild] public unowned TagMarker marker;
        public SidebarRow(Place place) {
            label.label = place.label;
            label.tooltip_text = place.cloud == null ? place.label : place.cloud.get_status_details();
            marker.visible = place.tag != null; icon.visible = place.tag == null;
            if (place.tag != null) marker.color = place.tag.color;
            else icon.set_from_gicon(place.device_icon(Gtk.IconTheme.get_for_display(get_display())));
            set_data<Place>("majoris-place", place);
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                child = null;
                dispose_template(typeof(SidebarRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/navigation-fields.ui")]
    public class NavigationFields : Gtk.Grid {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Stack location_bar;
        [GtkChild] public unowned Gtk.Entry path;
        [GtkChild] public unowned Gtk.Box breadcrumbs;
        [GtkChild] public unowned Gtk.SearchEntry search_entry;
        public NavigationFields() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(NavigationFields));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/view-settings.ui")]
    public class ViewSettingsDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        [GtkChild] public unowned Adw.ComboRow caption;
        [GtkChild] public unowned Adw.SwitchRow checkboxes;
        [GtkChild] public unowned Adw.PreferencesGroup columns_group;
        [GtkChild] public unowned Adw.SwitchRow direction;
        [GtkChild] public unowned Adw.SwitchRow folders;
        [GtkChild] public unowned Adw.PreferencesGroup group;
        [GtkChild] public unowned Adw.ComboRow grouping;
        [GtkChild] public unowned Adw.SwitchRow hidden_row;
        [GtkChild] public unowned Adw.PreferencesPage page;
        [GtkChild] public unowned Adw.ComboRow size;
        [GtkChild] public unowned Adw.ComboRow sort;
        [GtkChild] public unowned Adw.ComboRow view;
        public ViewSettingsDialog() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ViewSettingsDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/column-settings-row.ui")]
    public class ColumnSettingsRow : Adw.ActionRow {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Switch toggle;
        [GtkChild] public unowned Gtk.SpinButton width;
        [GtkChild] public unowned Gtk.Button up;
        public ColumnSettingsRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ColumnSettingsRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/chooser-choice.ui")]
    public class ChooserChoiceRow : Gtk.Box {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Label label;
        [GtkChild] public unowned Gtk.DropDown combo;
        public ChooserChoiceRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ChooserChoiceRow));
            }
            base.dispose();
        }
    }
}
