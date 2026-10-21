namespace MajorisFiles {
    public class OfficePreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("application/vnd.openxmlformats-officedocument.") || item.mime.has_prefix("application/vnd.oasis.opendocument.") || item.mime in new string[] {"application/msword", "application/vnd.ms-excel", "application/vnd.ms-powerpoint"};
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if(item.bytes > 64 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("This document exceeds the text preview size limit");
            string? rendering_error = null;
            File? temporary = null;
            try {
                var pdf = yield PreviewSandbox.run(item, "office-pdf", {}, token);
                token.set_error_if_cancelled();
                if (pdf.get_size() > 64 * 1024 * 1024)
                    throw new FileError.UNSUPPORTED("Rendered document exceeds the preview limit");
                temporary = File.new_for_path(DirUtils.make_tmp("majoris-office-XXXXXX"));
                var document = temporary.get_child("rendered.pdf");
                yield document.replace_contents_async(pdf.get_data(), null, false, FileCreateFlags.PRIVATE, token, null);
                var info = yield document.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                var view = yield new PdfPreview().render(new FileItem(document, info), token);
                token.set_error_if_cancelled();
                var retained = temporary;
                token.cancelled.connect(() => OperationManager.remove_tree.begin(retained, new Cancellable()));
                return view;
            }
            catch (Error e) {
                if (temporary != null)
                    try { yield OperationManager.remove_tree(temporary, new Cancellable()); } catch (Error ignored) {}
                token.set_error_if_cancelled();
                rendering_error = e.message;
            }
            var bytes = yield PreviewSandbox.run(item, "office", {}, token);
            var view = new Gtk.TextView();
            view.editable = false;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.buffer.text = ((string)bytes.get_data()).make_valid((ssize_t)bytes.get_size());
            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
            var note = new Gtk.Label(_("Formatted preview unavailable: ") + rendering_error + "\nExtracted text only · Formatting and images are omitted");
            note.wrap = true;
            note.add_css_class("dim-label");
            box.append(note);
            box.append(Browser.scrolled(view));
            return box;
        }
    }
}
