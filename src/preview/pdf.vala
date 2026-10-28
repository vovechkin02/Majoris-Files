namespace MajorisFiles {
    public class PdfPreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime == "application/pdf";
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if(item.bytes > 128 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("This PDF exceeds the preview size limit");
            var bytes = yield PreviewSandbox.run(item, "pdf-info", {}, token);
            var data = new ByteArray();
            data.append(bytes.get_data());
            data.append({0});
            int pages;
            if(!int.try_parse((string)data.data, out pages) || pages < 1 || pages > 100000)
                throw new FileError.INVALID("Invalid PDF page count");
            return new PdfView(item, pages, token);
        }
    }
    public class PdfView : Gtk.Box {
        FileItem item;
        Cancellable token;
        int pages;
        Gtk.Picture picture = new Gtk.Picture();
        Gtk.Label count = new Gtk.Label("");
        Gtk.Label failure = new Gtk.Label("");
        int index;
        double zoom = 1;
        bool busy;
        public PdfView(FileItem item, int pages, Cancellable token)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.item = item;
            this.pages = pages;
            this.token = token;
            var controls = new Majoris.Ui.Toolbar();
            controls.compact = true;
            controls.divider = true;
            var actions = controls.append_group();
            actions.append_control(Browser.button("go-previous-symbolic", _("Previous Page"), () => { if(!busy && index > 0)
                                                                                            {
                                                                                                index--;
                                                                                                render_page.begin();
                                                                                            }
                }));
            count.add_css_class("majoris-toolbar-metadata");
            actions.append_widget(count);
            actions.append_control(Browser.button("go-next-symbolic", _("Next Page"), () => { if(!busy && index + 1 < pages)
                                                                                    {
                                                                                        index++;
                                                                                        render_page.begin();
                                                                                    }
                }));
            actions.append_control(Browser.button("zoom-in-symbolic", _("Zoom In"), () => { if(!busy)
                                                                                  {
                                                                                      zoom = double.min(zoom * 1.2, 3);
                                                                                      render_page.begin();
                                                                                  }
                }));
            actions.append_control(Browser.button("zoom-out-symbolic", _("Zoom Out"), () => { if(!busy)
                                                                                    {
                                                                                        zoom = double.max(zoom / 1.2, 0.25);
                                                                                        render_page.begin();
                                                                                    }
                }));
            var toolbar_scroll = new Gtk.ScrolledWindow();
            toolbar_scroll.set_policy(Gtk.PolicyType.EXTERNAL, Gtk.PolicyType.NEVER);
            toolbar_scroll.propagate_natural_height = true;
            toolbar_scroll.child = controls;
            append(toolbar_scroll);
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            picture.can_shrink = true;
            append(Browser.scrolled(picture));
            failure.wrap = true;
            append(failure);
            render_page.begin();
        }
        async void render_page()
        {
            if(busy || token.is_cancelled())
                return;
            busy = true;
            failure.label = "";
            try {
                var bytes = yield PreviewSandbox.run(item, "pdf-page", {index.to_string(), zoom.to_string()}, token);
                token.set_error_if_cancelled();
                picture.paintable = Gdk.Texture.from_bytes(bytes);
                count.label = _("%d / %d").printf(index + 1, pages);
            }
            catch(Error e) {
                if(!token.is_cancelled())
                    failure.label = _("Preview unavailable\n") + e.message;
            }
            busy = false;
        }
    }
}
