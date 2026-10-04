namespace MajorisFiles {
    public class ArchivePreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.contains("zip") || item.mime.contains("tar") || item.mime.contains("7z") || item.mime.contains("rar") || item.mime.contains("compressed");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if(!item.file.is_native() || item.bytes > 256 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("Archive preview requires a local archive up to 256 MiB");
            var bytes = yield PreviewSandbox.run(item, "archive", {}, token);
            var data = new ByteArray();
            data.append(bytes.get_data());
            data.append({0});
            string text = ((string)data.data).make_valid();
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
            return item.mime == "text/markdown" || item.name.down().has_suffix(".md");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            var source = yield new TextPreview().render(item, token);
            Gtk.TextView? rendered = null;
            string failure = "";
            try {
                var bytes = yield PreviewSandbox.run(item, "markdown", {}, token);
                rendered = render_document(bytes);
                if(item.bytes > 256 * 1024)
                {
                    Gtk.TextIter end;
                    rendered.buffer.get_end_iter(out end);
                    rendered.buffer.insert(ref end, "\n[Preview limited to 256 KiB]", -1);
                }
            }
            catch(IOError.CANCELLED e) {
                throw e;
            }
            catch(Error e) {
                failure = e.message;
            }
            return new MarkdownView(source, rendered, failure);
        }
        static Gtk.TextView render_document(Bytes bytes) throws Error
        {
            if(bytes.get_size() > 4 * 1024 * 1024)
                throw new FileError.INVALID("Markdown preview exceeds its output limit");
            var parser = new Json.Parser();
            var data = new ByteArray();
            data.append(bytes.get_data());
            data.append({0});
            parser.load_from_data((string)data.data, (ssize_t)bytes.get_size());
            var root = parser.get_root();
            if(root == null || root.get_node_type() != Json.NodeType.ARRAY)
                throw new FileError.INVALID("Invalid Markdown output");
            var segments = root.get_array();
            if(segments.get_length() > 20000)
                throw new FileError.INVALID("Too many Markdown segments");
            var view = new Gtk.TextView();
            view.editable = false;
            view.wrap_mode = Gtk.WrapMode.WORD_CHAR;
            view.left_margin = 12;
            view.right_margin = 12;
            view.top_margin = 12;
            var buffer = view.buffer;
            Gtk.TextTag[] tags = {
                buffer.create_tag("strong", "weight", Pango.Weight.BOLD),
                buffer.create_tag("emphasis", "style", Pango.Style.ITALIC),
                buffer.create_tag("code", "family", "monospace"),
                buffer.create_tag("heading", "scale", 1.4),
                buffer.create_tag("quote", "style", Pango.Style.ITALIC),
                buffer.create_tag("link", "underline", Pango.Underline.SINGLE)
            };
            uint total = 0;
            for(uint i = 0; i < segments.get_length(); i++)
            {
                var node = segments.get_element(i);
                if(node.get_node_type() != Json.NodeType.OBJECT)
                    throw new FileError.INVALID("Invalid Markdown segment");
                var segment = node.get_object();
                if(!segment.has_member("text") || !segment.has_member("style"))
                    throw new FileError.INVALID("Incomplete Markdown segment");
                var text_node = segment.get_member("text"), style_node = segment.get_member("style");
                if(text_node.get_value_type() != typeof(string) || style_node.get_value_type() != typeof(int64))
                    throw new FileError.INVALID("Invalid Markdown segment types");
                string text = text_node.get_string();
                int64 style = style_node.get_int();
                total += text.length;
                if(style < 0 || style > 63 || total > 2 * 1024 * 1024)
                    throw new FileError.INVALID("Invalid Markdown style or text budget");
                Gtk.TextIter begin, end;
                buffer.get_end_iter(out end);
                int offset = end.get_offset();
                buffer.insert(ref end, text, -1);
                buffer.get_iter_at_offset(out begin, offset);
                for(int bit = 0; bit < tags.length; bit++)
                    if((style & ((int64)1 << bit)) != 0)
                        buffer.apply_tag(tags[bit], begin, end);
            }
            return view;
        }
    }
    public class MarkdownView : Gtk.Box {
        public Gtk.Widget source {
            get;
            private set;
        }
        public Gtk.TextView? rendered {
            get;
            private set;
        }
        public MarkdownView(Gtk.Widget source, Gtk.TextView? rendered, string failure)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.source = source;
            this.rendered = rendered;
            var views = new Gtk.Stack();
            views.vexpand = true;
            views.add_titled(source, "source", "Source");
            if(rendered != null)
                views.add_titled(Browser.scrolled(rendered), "rendered", "Rendered");
            var switcher = new Gtk.StackSwitcher();
            switcher.stack = views;
            append(switcher);
            append(views);
            views.visible_child_name = rendered != null ? "rendered" : "source";
            if(failure != "")
            {
                var message = new Gtk.Label("Rendered preview unavailable\n" + failure);
                message.wrap = true;
                append(message);
            }
        }
    }
}