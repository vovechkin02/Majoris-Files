namespace MajorisFiles {
    public class FilesTheme : Object {
        static Gtk.CssProvider? theme;
        static Gtk.CssProvider? layout;
        public static void ensure() {
            if (theme != null) return;
            theme = new Gtk.CssProvider();
            layout = new Gtk.CssProvider();
            var display = Gdk.Display.get_default();
            Gtk.StyleContext.add_provider_for_display(display, theme, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            Gtk.StyleContext.add_provider_for_display(display, layout, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
            layout.load_from_resource("/com/majoris/files/theme/files.css");
            update();
            Adw.StyleManager.get_default().notify["dark"].connect(update);
        }
        static void update() {
            theme.load_from_resource(Adw.StyleManager.get_default().dark
                ? "/com/majoris/files/theme/gtk-dark.css" : "/com/majoris/files/theme/gtk.css");
        }
    }
}
