namespace MajorisFiles {
    [CCode(cname = "majoris_archive_list", cheader_filename = "src/archive/native.h")]
    extern string archive_list(string source, Cancellable token) throws Error;
    public class ArchivePreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.contains("zip") || item.mime.contains("tar") || item.mime.contains("7z") || item.mime.contains("rar") || item.mime.contains("compressed");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if(!item.file.is_native() || item.bytes > 256 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("Archive preview requires a local archive up to 256 MiB");
            string text = "";
            Error? failure = null;
            SourceFunc resume = render.callback;
            new Thread<void*>("archive-preview", () => {
                try { text = archive_list(item.file.get_path(), token);
                }
                catch(Error e) { failure = e;
                }
                Idle.add((owned)resume);
                return null;
            });
            yield;
            token.set_error_if_cancelled();
            if(failure != null)
                throw failure;
            var view = new Gtk.TextView();
            view.editable = false;
            view.monospace = true;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.buffer.text = text;
            var scroll = new Gtk.ScrolledWindow();
            scroll.set_child(view);
            return scroll;
        }
    }
    public class MarkdownPreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime == "text/markdown" || item.name.has_suffix(".md");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            var stream = yield item.file.read_async(Priority.LOW, token);
            uint8[] bytes = new uint8[256 * 1024 + 1];
            size_t count;
            yield stream.read_all_async(bytes[0 : bytes.length - 1], Priority.LOW, token, out count);
            yield stream.close_async(Priority.LOW, null);
            bytes[count] = 0;
            var view = new Gtk.TextView();
            view.editable = false;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.left_margin = 12;
            view.right_margin = 12;
            view.top_margin = 12;
            var buffer = view.buffer;
            var heading = buffer.create_tag("heading", "weight", Pango.Weight.BOLD, "scale", 1.4);
            var code = buffer.create_tag("code", "family", "monospace", "background", "#eeeeee");
            bool fenced = false;
            foreach(var line in ((string)bytes).make_valid().split("\n"))
            {
                if(line.has_prefix("```"))
                {
                    fenced = !fenced;
                    continue;
                }
                var text = line;
                bool is_heading = !fenced && line.has_prefix("#");
                if(is_heading)
                {
                    int prefix = 0;
                    while(prefix < line.length && line[prefix] == '#')
                        prefix++;
                    text = line.substring(prefix).strip();
                }
                if(!fenced && (text.has_prefix("- ") || text.has_prefix("* ")))
                    text = "• " + text.substring(2);
                Gtk.TextIter end;
                buffer.get_end_iter(out end);
                int start = end.get_offset();
                buffer.insert(ref end, text + "\n", -1);
                Gtk.TextIter begin;
                buffer.get_iter_at_offset(out begin, start);
                buffer.get_end_iter(out end);
                if(fenced)
                    buffer.apply_tag(code, begin, end);
                else if(is_heading)
                    buffer.apply_tag(heading, begin, end);
            }
            if(item.bytes > count)
            {
                Gtk.TextIter end;
                buffer.get_end_iter(out end);
                buffer.insert(ref end, "\n[Preview limited to 256 KiB]", -1);
            }
            var scroll = new Gtk.ScrolledWindow();
            scroll.set_child(view);
            return scroll;
        }
    }
}
