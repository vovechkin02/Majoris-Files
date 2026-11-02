namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/preview-animation.ui")]
    public class AnimatedImageView : Gtk.Box {
        private bool template_disposing;
        Gee.ArrayList<Gdk.Texture> frames = new Gee.ArrayList<Gdk.Texture>();
        Gee.ArrayList<int> delays = new Gee.ArrayList<int>();
        [GtkChild]
        private unowned Gtk.Picture picture;
        Cancellable token;
        uint timer;
        int frame;
        double zoom = 1;
        bool fit = true;
        bool playing = true;

        [GtkChild] private unowned Gtk.Label note;
        [GtkChild] private unowned Gtk.ScrolledWindow picture_scroll;
        [GtkChild] private unowned Gtk.ScrolledWindow toolbar_scroll;
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
            var ui_controls = new Gtk.Builder.from_resource("/com/majoris/files/ui/preview-controls.ui");
            var controls = new Majoris.Ui.Toolbar();
            controls.compact = true;
            controls.divider = true;
            var actions = controls.append_group();
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_7"), () => playing = !playing));
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_2"), () => { fit = false; zoom = double.min(3, zoom * 1.25); update(); }));
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_1"), () => { fit = false; zoom = double.max(0.1, zoom / 1.25); update(); }));
            actions.append_control(PreviewButtons.connect((Gtk.Button)ui_controls.get_object("control_6"), () => { fit = true; update(); }));


            toolbar_scroll.child = controls;

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
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                if (token != null) token.cancel();
                stop();
                dispose_template(typeof(AnimatedImageView));
            }
            base.dispose();
        }
    }
}
