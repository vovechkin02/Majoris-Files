namespace MajorisFiles {
    public class AnimatedImageView : Gtk.Box {
        Gee.ArrayList<Gdk.Texture> frames = new Gee.ArrayList<Gdk.Texture>();
        Gee.ArrayList<int> delays = new Gee.ArrayList<int>();
        Gtk.Picture picture = new Gtk.Picture();
        Cancellable token;
        uint timer;
        int frame;
        double zoom = 1;
        bool fit = true;
        bool playing = true;
        public AnimatedImageView(Bytes bytes, Cancellable token) throws Error
        {
            Object(orientation: Gtk.Orientation.VERTICAL, spacing: 6);
            this.token = token;
            playing = Gtk.Settings.get_default().gtk_enable_animations;
            var parser = new Json.Parser(); parser.load_from_data((string)bytes.get_data(), (ssize_t)bytes.get_size());
            if (parser.get_root().get_node_type() != Json.NodeType.ARRAY) throw new FileError.INVALID("Invalid animation");
            var array = parser.get_root().get_array();
            if (array.get_length() < 1 || array.get_length() > 240) throw new FileError.INVALID("Invalid animation frame count");
            uint64 pixels = 0;
            foreach (var node in array.get_elements()) {
                var object = node.get_object();
                var png = Base64.decode(object.get_string_member("png"));
                var texture = Gdk.Texture.from_bytes(new Bytes(png));
                if (texture.get_width() > 800 || texture.get_height() > 800) throw new FileError.INVALID("Oversized animation frame");
                pixels += (uint64)texture.get_width() * texture.get_height();
                if (pixels > 16 * 1024 * 1024) throw new FileError.INVALID("Animation exceeds the decoded memory limit");
                frames.add(texture);
                delays.add(((int)object.get_int_member("delay")).clamp(20, 10000));
            }
            var controls = new Majoris.Ui.Toolbar();
            controls.compact = true;
            controls.divider = true;
            var actions = controls.append_group();
            actions.append_control(Browser.button("media-playback-pause-symbolic", _("Play or Pause Animation"), () => playing = !playing));
            actions.append_control(Browser.button("zoom-in-symbolic", _("Zoom In"), () => { fit = false; zoom = double.min(3, zoom * 1.25); update(); }));
            actions.append_control(Browser.button("zoom-out-symbolic", _("Zoom Out"), () => { fit = false; zoom = double.max(0.1, zoom / 1.25); update(); }));
            actions.append_control(Browser.button("zoom-fit-best-symbolic", _("Fit Image"), () => { fit = true; update(); }));
            var toolbar_scroll = new Gtk.ScrolledWindow();
            toolbar_scroll.set_policy(Gtk.PolicyType.EXTERNAL, Gtk.PolicyType.NEVER);
            toolbar_scroll.propagate_natural_height = true;
            toolbar_scroll.child = controls;
            append(toolbar_scroll);
            picture.content_fit = Gtk.ContentFit.CONTAIN;
            append(Browser.scrolled(picture));
            var note = new Gtk.Label(_("Animated preview · bounded to 240 frames / 24 MiB of encoded frames"));
            note.wrap = true; append(note);
            token.cancelled.connect(stop);
            update(); schedule();
        }
        void update()
        {
            picture.paintable = frames[frame];
            picture.can_shrink = fit;
            picture.set_size_request(fit ? -1 : (int)(frames[frame].get_width() * zoom), fit ? -1 : (int)(frames[frame].get_height() * zoom));
        }
        void schedule()
        {
            if (token.is_cancelled()) return;
            timer = Timeout.add((uint)delays[frame], () => {
                timer = 0;
                if (!token.is_cancelled()) { if (playing) { frame = (frame + 1) % frames.size; update(); } schedule(); }
                return Source.REMOVE;
            });
        }
        void stop() { if (timer != 0) { Source.remove(timer); timer = 0; } }
        public override void unroot() { stop(); base.unroot(); }
    }
}
