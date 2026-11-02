namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/tags-assignment-row.ui")]
    public class TagAssignmentRow : Adw.ActionRow {
        private bool template_disposing;
        static construct { typeof(TagMarker).ensure(); }
        [GtkChild] public unowned Gtk.CheckButton check;
        [GtkChild] public unowned TagMarker marker;
        public TagAssignmentRow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(TagAssignmentRow));
            }
            base.dispose();
        }
    }
}
