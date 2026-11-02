namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/sharing-account-row.ui")]
    public class SharingAccountRow : Adw.ActionRow {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.CheckButton check;
        [GtkChild] public unowned Gtk.DropDown access;
        public SharingAccountRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(SharingAccountRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/shared-folder-row.ui")]
    public class SharedFolderRow : Adw.ActionRow {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Button open;
        [GtkChild] public unowned Gtk.Button copy;
        [GtkChild] public unowned Gtk.Button edit;
        [GtkChild] public unowned Gtk.Button stop;
        public SharedFolderRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(SharedFolderRow));
            }
            base.dispose();
        }
    }
}
