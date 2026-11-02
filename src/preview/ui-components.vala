namespace MajorisFiles {
    public class PreviewButtons : Object {
        public static Gtk.Button connect(Gtk.Button button, owned Callback callback) {
            button.clicked.connect(() => callback());
            return button;
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/preview-text.ui")]
    public class TextPreviewWidget : Gtk.Box {
        private bool template_disposing;
        static construct { typeof(GtkSource.View).ensure(); typeof(GtkSource.Buffer).ensure(); }
        [GtkChild] public unowned GtkSource.Buffer buffer;
        [GtkChild] public unowned Gtk.DropDown encoding;
        [GtkChild] public unowned Gtk.Label status;
        public TextPreviewWidget() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(TextPreviewWidget));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/preview-media.ui")]
    public class MediaPreviewWidget : Gtk.Box {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Image icon;
        [GtkChild] public unowned Gtk.Label name_label;
        [GtkChild] public unowned Gtk.Label error_label;
        [GtkChild] public unowned Gtk.Label metadata_error;
        [GtkChild] public unowned Gtk.MediaControls controls;
        [GtkChild] public unowned Gtk.Video video;
        public MediaPreviewWidget() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(MediaPreviewWidget));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/preview-plain-text.ui")]
    public class PlainTextPreview : Gtk.Box {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.TextView view;
        [GtkChild] public unowned Gtk.Label note;
        public PlainTextPreview() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(PlainTextPreview));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/quick-preview.ui")]
    public class QuickPreviewWindow : Adw.Window {
        private bool template_disposing;
        static construct { typeof(PreviewPane).ensure(); }
        [GtkChild] public unowned PreviewPane pane;
        public QuickPreviewWindow() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                content = null;
                dispose_template(typeof(QuickPreviewWindow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/conflict-previews.ui")]
    public class ConflictPreviewPair : Gtk.Box {
        private bool template_disposing;
        [GtkChild] public unowned Gtk.Picture source;
        [GtkChild] public unowned Gtk.Picture destination;
        public ConflictPreviewPair() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(ConflictPreviewPair));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/metadata-list.ui")]
    public class MetadataList : Gtk.Box {
        private bool template_disposing;
        public MetadataList() { }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(MetadataList));
            }
            base.dispose();
        }
    }
}
