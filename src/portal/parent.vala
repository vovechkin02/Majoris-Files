namespace MajorisFiles {
    [CCode(cname = "majoris_set_parent", cheader_filename = "src/portal/parent.h")]
    public extern bool set_external_parent(Gtk.Window window, string identifier);
}
