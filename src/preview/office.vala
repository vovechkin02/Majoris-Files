namespace MajorisFiles {
    public class OfficePreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("application/vnd.openxmlformats-officedocument.") || item.mime.has_prefix("application/vnd.oasis.opendocument.");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if(item.bytes > 64 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("This document exceeds the text preview size limit");
            var bytes = yield PreviewSandbox.run(item, "office", {}, token);
            var view = new Gtk.TextView();
            view.editable = false;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.buffer.text = ((string)bytes.get_data()).make_valid((ssize_t)bytes.get_size());
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            var note = new Gtk.Label("Text preview · Formatting, images and spreadsheet formulas are omitted");
            note.wrap = true;
            note.add_css_class("dim-label");
            box.append(note);
            box.append(Browser.scrolled(view));
            return box;
        }
    }
}
