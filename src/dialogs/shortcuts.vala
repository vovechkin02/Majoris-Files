namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/shortcuts.ui")]
    public class ShortcutsDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        public ShortcutsDialog() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ShortcutsDialog));
            }
            base.dispose();
        }
    }
}
