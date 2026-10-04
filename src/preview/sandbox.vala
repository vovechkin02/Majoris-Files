namespace MajorisFiles {
    public class PreviewSandbox : Object {
        static uint active;
        public static async Bytes run(FileItem item, string mode, string[] parameters, Cancellable token) throws Error
        {
            token.set_error_if_cancelled();
            while(active >= 4)
            {
                Timeout.add(50, () => { run.callback();
                                        return Source.REMOVE;
                    });
                yield;
                token.set_error_if_cancelled();
            }
            active++;
            try {
                return yield execute(item, mode, parameters, token);
            }
            finally {
                active--;
            }
        }
        static async Bytes execute(FileItem item, string mode, string[] parameters, Cancellable token) throws Error
        {
            token.set_error_if_cancelled();
            if(!item.file.is_native() || item.info.get_is_symlink() || item.info.get_file_type() != FileType.REGULAR)
                throw new FileError.UNSUPPORTED("This preview requires a local regular file");
            var bwrap = Environment.find_program_in_path("bwrap");
            if(bwrap == null)
                throw new FileError.UNSUPPORTED("The required preview sandbox (bubblewrap) is not installed");
            string helper = PREVIEW_HELPER_PATH;
            try {
                var sibling = Path.build_filename(Path.get_dirname(FileUtils.read_link("/proc/self/exe")), "majoris-files-preview-helper");
                if(FileUtils.test(sibling, FileTest.IS_EXECUTABLE))
                    helper = sibling;
            }
            catch(Error ignored) {}
            if(!FileUtils.test(helper, FileTest.IS_EXECUTABLE))
                throw new FileError.UNSUPPORTED("The preview helper is not installed");
            string[] args = {
                bwrap, "--unshare-all", "--die-with-parent", "--new-session", "--clearenv", "--setenv", "HOME", "/tmp", "--setenv", "LANG", "C.UTF-8", "--ro-bind", "/usr", "/usr", "--ro-bind", "/lib", "/lib", "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp", "--dir", "/etc"
            };
            if(FileUtils.test("/lib64", FileTest.IS_DIR))
                foreach(var argument in new string[] {"--ro-bind", "/lib64", "/lib64"})
                    args += argument;
            if(FileUtils.test("/etc/fonts", FileTest.IS_DIR))
                foreach(var argument in new string[] {"--ro-bind", "/etc/fonts", "/etc/fonts"})
                    args += argument;
            if(FileUtils.test("/etc/ld.so.cache", FileTest.EXISTS))
                foreach(var argument in new string[] {"--ro-bind", "/etc/ld.so.cache", "/etc/ld.so.cache"})
                    args += argument;
            foreach(var argument in new string[] {"--ro-bind", helper, "/helper", "--ro-bind", item.file.get_path(), "/input", "--", "/helper", mode, "/input"})
                args += argument;
            foreach(var parameter in parameters)
                args += parameter;
            var process = new Subprocess.newv(args, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            bool timed_out = false;
            uint timeout = Timeout.add_seconds(15, () => { timed_out = true;
                                                           process.force_exit();
                                                           return Source.REMOVE;
                });
            ulong cancellation = token.cancelled.connect(() => process.force_exit());
            Bytes? output = null, errors = null;
            try {
                token.set_error_if_cancelled();
                yield process.communicate_async(null, token, out output, out errors);
            }
            catch(Error e) {
                process.force_exit();
                if(!timed_out)
                    Source.remove(timeout);
                token.disconnect(cancellation);
                throw e;
            }
            if(!timed_out)
                Source.remove(timeout);
            token.disconnect(cancellation);
            token.set_error_if_cancelled();
            if(timed_out)
                throw new IOError.TIMED_OUT("The preview took too long");
            if(!process.get_successful())
                throw new FileError.UNSUPPORTED("The preview provider could not render this file in its sandbox");
            if(output == null || output.get_size() > 80 * 1024 * 1024)
                throw new FileError.INVALID("Invalid preview output");
            return output;
        }
    }
    public class ImageView : Gtk.Box {
        FileItem item;
        Cancellable token;
        Gdk.Texture texture;
        Gtk.Picture picture = new Gtk.Picture();
        Gtk.Label description = new Gtk.Label("");
        int angle;
        double zoom = 1;
        bool fit = true;
        bool busy;
        public ImageView(FileItem item, Gdk.Texture texture, Cancellable token)
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.item = item;
            this.texture = texture;
            this.token = token;
            var controls = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
            controls.append(Browser.button("zoom-in-symbolic", "Zoom In", () => { fit = false;
                                                                                  zoom = double.min(zoom * 1.25, 3);
                                                                                  update();
                }));
            controls.append(Browser.button("zoom-out-symbolic", "Zoom Out", () => { fit = false;
                                                                                    zoom = double.max(zoom / 1.25, 0.1);
                                                                                    update();
                }));
            controls.append(Browser.button("zoom-fit-best-symbolic", "Fit Image", () => { fit = true;
                                                                                          update();
                }));
            controls.append(Browser.button("object-rotate-right-symbolic", "Rotate Preview Clockwise", () => { if(!busy)
                                                                                                               {
                                                                                                                   angle = (angle + 90) % 360;
                                                                                                                   rotate.begin();
                                                                                                               }
                }));
            append(controls);
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            append(Browser.scrolled(picture));
            description.wrap = true;
            append(description);
            update();
        }
        void update()
        {
            picture.paintable = texture;
            picture.can_shrink = fit;
            picture.set_size_request(fit ? -1 : (int)(texture.get_width() * zoom), fit ? -1 : (int)(texture.get_height() * zoom));
            description.label = "%d × %d preview · %s".printf(texture.get_width(), texture.get_height(), Paths.size(item.bytes));
        }
        async void rotate()
        {
            busy = true;
            try {
                var bytes = yield PreviewSandbox.run(item, "image", {angle.to_string()}, token);
                token.set_error_if_cancelled();
                texture = Gdk.Texture.from_bytes(bytes);
                update();
            }
            catch(Error e) {
                if(!token.is_cancelled())
                    description.label = "Preview unavailable\n" + e.message;
            }
            busy = false;
        }
    }
    public class FontPreview : Object, PreviewProvider {
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("font/") || item.mime.contains("font") || item.name.down().has_suffix(".ttf") || item.name.down().has_suffix(".otf");
        }
        public async Gtk.Widget render(FileItem item, Cancellable token) throws Error
        {
            if(item.bytes > 32 * 1024 * 1024)
                throw new FileError.UNSUPPORTED("This font exceeds the preview size limit");
            var bytes = yield PreviewSandbox.run(item, "font", {}, token);
            var picture = new Gtk.Picture.for_paintable(Gdk.Texture.from_bytes(bytes));
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            return picture;
        }
    }
}
