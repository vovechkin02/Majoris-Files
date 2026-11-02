namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/prompt.ui")]
    public class PromptDialog : Adw.AlertDialog {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Entry entry;
        public PromptDialog() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                extra_child = null;
                dispose_template(typeof(PromptDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/password.ui")]
    public class PasswordDialog : Adw.AlertDialog {
        private bool template_disposing;
        [GtkChild] public unowned Adw.PasswordEntryRow entry;
        [GtkChild] public unowned Adw.PasswordEntryRow repeat;
        public PasswordDialog() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                extra_child = null;
                dispose_template(typeof(PasswordDialog));
            }
            base.dispose();
        }
    }
}
