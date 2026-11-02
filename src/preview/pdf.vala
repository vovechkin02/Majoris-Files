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
    [GtkTemplate (ui = "/com/majoris/files/ui/preview-pdf.ui")]
    public class PdfView : Gtk.Box {
        private bool template_disposing;
        FileItem item;
        Cancellable token;
        int pages;
        [GtkChild]
        private unowned Gtk.Picture picture;
        Gtk.Label count;
        [GtkChild]
        private unowned Gtk.Label failure;
        int index;
        double zoom = 1;
        bool busy;

        [GtkChild] private unowned Gtk.ScrolledWindow picture_scroll;
        [GtkChild] private unowned Gtk.ScrolledWindow toolbar_scroll;
        public PdfView(FileItem item, int pages, Cancellable token)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.item = item;
            this.pages = pages;
            this.token = token;
            var ui_controls = new Gtk.Builder.from_resource("/com/majoris/files/ui/preview-controls.ui");
            count = (Gtk.Label)ui_controls.get_object("count");
            var controls = new Majoris.Ui.Toolbar();
            controls.compact = true;
            controls.divider = true;
            var actions = controls.append_group();
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_4"), () => { if(!busy && index > 0)
                                                                                            {
                                                                                                index--;
                                                                                                render_page.begin();
                                                                                            }
                }));
            actions.append_widget(count);
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_3"), () => { if(!busy && index + 1 < pages)
                                                                                    {
                                                                                        index++;
                                                                                        render_page.begin();
                                                                                    }
                }));
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_2"), () => { if(!busy)
                                                                                  {
                                                                                      zoom = double.min(zoom * 1.2, 3);
                                                                                      render_page.begin();
                                                                                  }
                }));
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_1"), () => { if(!busy)
                                                                                    {
                                                                                        zoom = double.max(zoom / 1.2, 0.25);
                                                                                        render_page.begin();
                                                                                    }
                }));


            toolbar_scroll.child = controls;

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
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                if (token != null) token.cancel();
                dispose_template(typeof(PdfView));
            }
            base.dispose();
        }
    }
}
