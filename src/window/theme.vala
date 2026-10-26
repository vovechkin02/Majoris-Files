namespace MajorisFiles {
    // GNOME supplies the theme; this provider owns only Files layout.
    public class FilesTheme : Object {
        static Gtk.CssProvider? layout;
        public static void ensure() {
            if (layout != null) return;
            var display = Gdk.Display.get_default();
            if (display == null) return;
            layout = new Gtk.CssProvider();
            layout.load_from_resource("/com/majoris/files/theme/files.css");
            Gtk.StyleContext.add_provider_for_display(display, layout, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
    }
}
