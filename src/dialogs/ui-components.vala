namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/value-row.ui")]
    public class ValueRow : Adw.ActionRow {
        private bool template_disposing;
        public ValueRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ValueRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/application-choice-row.ui")]
    public class ApplicationChoiceRow : Adw.ActionRow {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Image icon;
        [GtkChild] public unowned Gtk.CheckButton choice;
        public ApplicationChoiceRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ApplicationChoiceRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/application-launch-row.ui")]
    public class ApplicationLaunchRow : Adw.ActionRow {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Image icon;
        [GtkChild] public unowned Gtk.Button open;
        [GtkChild] public unowned Gtk.Button set_default;
        public ApplicationLaunchRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ApplicationLaunchRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/device-identity.ui")]
    public class DeviceIdentity : Gtk.Box {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Image icon;
        [GtkChild] public unowned Gtk.Label label;
        public DeviceIdentity() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(DeviceIdentity));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/device-usage.ui")]
    public class DeviceUsageRow : Adw.PreferencesRow {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.ProgressBar bar;
        public DeviceUsageRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                child = null;
                dispose_template(typeof(DeviceUsageRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/device-hardware.ui")]
    public class DeviceHardwarePage : Adw.NavigationPage {
        static construct { typeof(DeviceSection).ensure(); }
        [GtkChild] public unowned DeviceSection device_section;
        [GtkChild] public unowned DeviceSection storage_section;
        [GtkChild] public unowned DeviceSection filesystem_section;
        private bool template_disposing;
        [GtkChild] public unowned Adw.PreferencesPage hardware;
        public DeviceHardwarePage() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                child = null;
                dispose_template(typeof(DeviceHardwarePage));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/permissions-acl.ui")]
    public class AclDialog : Adw.AlertDialog {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.TextView view;
        public AclDialog() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                extra_child = null;
                dispose_template(typeof(AclDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/smb-password.ui")]
    public class SmbPasswordDialog : Adw.AlertDialog {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.PasswordEntry password;
        public SmbPasswordDialog() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                extra_child = null;
                dispose_template(typeof(SmbPasswordDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/rename-preview-row.ui")]
    public class RenamePreviewRow : Adw.ActionRow {
        private bool template_disposing;
        public RenamePreviewRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(RenamePreviewRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/destination-row.ui")]
    public class DestinationRow : Adw.ActionRow {
        private bool template_disposing;
        public DestinationRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(DestinationRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/properties-subpage.ui")]
    public class PropertiesSubpage : Adw.NavigationPage {
        private bool template_disposing;
        [GtkChild] public unowned Adw.ToolbarView view;
        public PropertiesSubpage() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                child = null;
                dispose_template(typeof(PropertiesSubpage));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/multi-selection-details.ui")]
    public class MultiSelectionDetails : Adw.PreferencesPage {
        private bool template_disposing;
        [GtkChild] public unowned Adw.ActionRow selected;
        [GtkChild] public unowned Adw.ActionRow exact_size;
        [GtkChild] public unowned Adw.ActionRow allocated;
        public MultiSelectionDetails() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(MultiSelectionDetails));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/nearby-send.ui")]
    public class NearbySendDialog : Adw.AlertDialog {
        private bool template_disposing;
        [GtkChild] public unowned Adw.ComboRow target;
        public NearbySendDialog() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                extra_child = null;
                dispose_template(typeof(NearbySendDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/copy-properties-row.ui")]
    public class CopyPropertiesRow : PropertiesInformationRow {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Button copy_button;
        public CopyPropertiesRow(string title, string value) { base(title, value); }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(CopyPropertiesRow));
            }
            base.dispose();
        }
    }
    public class DeviceSection : Adw.PreferencesGroup {
        private Gee.ArrayList<Gtk.Widget> data_rows = new Gee.ArrayList<Gtk.Widget>();
        public void append(Gtk.Widget row) { data_rows.add(row); add(row); }
        public void clear_rows() {
            foreach (var row in data_rows) remove(row);
            data_rows.clear(); visible = false;
        }
        protected override void dispose() { clear_rows(); base.dispose(); }
    }
}
