namespace MajorisFiles {
    public class PdfPreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime == "application/pdf";
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if (item.bytes > 128 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("This PDF exceeds the preview size limit");
            Poppler.Document? document = null;
            Error? failure = null;
            SourceFunc resume = render.callback;
            new Thread<void*>("pdf-load", () => { try { document = new Poppler.Document.from_file(item.file.get_uri(), null);
                                                  }
                                                  catch (Error e) { failure = e;
                                                  }
                                                  Idle.add((owned)resume);
                                                  return null;
                });
            yield;
            token.set_error_if_cancelled();
            if (failure != null)
                throw failure;
            return new PdfView(document, token);
        }
    }
    public class PdfView : Gtk.Box {
        Poppler.Document document;
        Cancellable token;
        Gtk.DrawingArea drawing = new Gtk.DrawingArea();
        Gtk.Label count = new Gtk.Label("");
        Cairo.ImageSurface? surface;
        int index;
        double zoom = 1;
        bool busy;
        public PdfView(Poppler.Document document, Cancellable token)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.document = document;
            this.token = token;
            var controls = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            controls.append(Browser.button("go-previous-symbolic", "Previous Page", () => { if (!busy && index > 0)
                                                                                            {
                                                                                                index--;
                                                                                                render_page.begin();
                                                                                            }
                }));
            controls.append(count);
            controls.append(Browser.button("go-next-symbolic", "Next Page", () => { if (!busy && index + 1 < document.get_n_pages())
                                                                                    {
                                                                                        index++;
                                                                                        render_page.begin();
                                                                                    }
                }));
            controls.append(Browser.button("zoom-in-symbolic", "Zoom In", () => { if (!busy)
                                                                                  {
                                                                                      zoom = double.min(zoom * 1.2, 3);
                                                                                      render_page.begin();
                                                                                  }
                }));
            controls.append(Browser.button("zoom-out-symbolic", "Zoom Out", () => { if (!busy)
                                                                                    {
                                                                                        zoom = double.max(zoom / 1.2, 0.25);
                                                                                        render_page.begin();
                                                                                    }
                }));
            append(controls);
            drawing.set_draw_func((area, cr, w, h) => { if (surface != null)
                                                        {
                                                            cr.set_source_surface(surface, 0, 0);
                                                            cr.paint();
                                                        }
                });
            append(Browser.scrolled(drawing));
            render_page.begin();
        }
        async void render_page()
        {
            if (busy || token.is_cancelled())
                return;
            busy = true;
            Cairo.ImageSurface? image = null;
            SourceFunc resume = render_page.callback;
            new Thread<void*>("pdf-page", () => { var page = document.get_page(index);
                                                  double w, h;
                                                  page.get_size(out w, out h);
                                                  double scale = double.min(zoom, 4096 / double.max(w, h));
                                                  image = new Cairo.ImageSurface(Cairo.Format.ARGB32, (int)(w * scale), (int)(h * scale));
                                                  var cr = new Cairo.Context(image);
                                                  cr.set_source_rgb(1, 1, 1);
                                                  cr.paint();
                                                  cr.scale(scale, scale);
                                                  page.render(cr);
                                                  Idle.add((owned)resume);
                                                  return null;
                });
            yield;
            if (!token.is_cancelled())
            {
                surface = image;
                drawing.content_width = surface.get_width();
                drawing.content_height = surface.get_height();
                drawing.queue_draw();
                count.label = "%d / %d".printf(index + 1, document.get_n_pages());
            }
            busy = false;
        }
    }
}
