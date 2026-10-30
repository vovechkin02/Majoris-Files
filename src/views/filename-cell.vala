namespace MajorisFiles {
    // The transaction outlives factory bindings; a cell is only its presentation.
    public class InlineRename : Object {
        public FileItem item;
        public Gtk.SelectionModel context;
        public string proposed;
        public string message = "";
        public bool pending;
        public bool focus_ready;
        public bool cancelled;
        public InlineRename(FileItem item, Gtk.SelectionModel context) {
            this.item = item; this.context = context; proposed = item.name;
        }
        public static int stem_length(string name, bool folder) {
            int dot = name.last_index_of(".");
            return !folder && dot > 0 ? name.substring(0, dot).char_count() : name.char_count();
        }
        public static string extension(string name) {
            int dot = name.last_index_of(".");
            return dot > 0 ? name.substring(dot) : "";
        }
    }
    public class FilenameCell : Gtk.Box {
        Gtk.Stack stack = new Gtk.Stack();
        public Gtk.Label label = new Gtk.Label("");
        public Gtk.Entry entry = new Gtk.Entry();
        public FileItem? item;
        public Gtk.SelectionModel? context;
        public InlineRename? transaction;
        public signal void edited(string text);
        public signal void commit_requested();
        public signal void cancel_requested();
        bool updating;
        bool whole;
        uint binding;
        public FilenameCell() {
            stack.hhomogeneous = true; stack.vhomogeneous = true;
            stack.hexpand = true; append(stack);
            entry.width_chars = 1; entry.max_width_chars = 1;
            entry.hexpand = true;
            stack.add_named(label, "label"); stack.add_named(entry, "entry");
            stack.visible_child_name = "label";
            entry.changed.connect(() => { if (!updating && transaction != null) edited(entry.text); });
            entry.activate.connect(() => commit_requested());
            var focus = new Gtk.EventControllerFocus();
            focus.leave.connect(() => {
                // Wait until after unbind/navigation have detached this presentation.
                var expected = transaction;
                if (expected == null || !expected.focus_ready) return;
                uint epoch = binding;
                Idle.add(() => {
                    if (expected != null && transaction == expected && epoch == binding && get_mapped() && !expected.pending && expected.focus_ready && !expected.cancelled && !focus.contains_focus)
                        commit_requested();
                    return Source.REMOVE;
                });
            });
            entry.add_controller(focus);
            var keys = new Gtk.EventControllerKey();
            keys.key_pressed.connect((key, code, mods) => {
                if (key == Gdk.Key.Escape) { cancel_requested(); return true; }
                if (key == Gdk.Key.F2) { toggle_selection(); return true; }
                return false;
            });
            entry.add_controller(keys);
        }
        public void toggle_selection() {
            if (transaction == null) return;
            whole = !whole;
            entry.select_region(0, whole ? -1 : InlineRename.stem_length(entry.text, transaction.item.directory));
        }
        public void render(InlineRename? state, bool focus = false) {
            bool starting = transaction != state;
            transaction = state;
            updating = true;
            if (state != null) {
                if (entry.text != state.proposed) entry.text = state.proposed;
                entry.editable = !state.pending;
                entry.tooltip_text = state.message == "" ? null : state.message;
                if (state.message == "") entry.remove_css_class("error"); else entry.add_css_class("error");
                stack.visible_child_name = "entry";
                if (focus) {
                    entry.grab_focus();
                    if (starting || !state.focus_ready) { whole = false; entry.select_region(0, InlineRename.stem_length(entry.text, state.item.directory)); }
                }
            } else {
                var root = get_root();
                if (root != null) for (var widget = root.get_focus(); widget != null; widget = widget.get_parent())
                    if (widget == entry) { root.set_focus(null); break; }
                stack.visible_child_name = "label";
            }
            updating = false;
        }
        public void detach() { binding++; render(null); item = null; context = null; }
    }
}
