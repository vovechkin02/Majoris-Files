namespace MajorisFiles {
    // User colour data is drawn directly; all control styling stays in the theme.
    [GtkTemplate (ui = "/com/majoris/files/ui/tag-marker.ui")]
    public class TagMarker : Gtk.DrawingArea {
        private bool template_disposing;
        public string color { get; set; default = ""; }
        public TagMarker(string color = "") {
            this.color = color;
        }
        construct {
            notify["color"].connect(queue_draw);
            set_draw_func(draw_marker);
        }
        static void draw_marker(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
            var marker = (TagMarker)area;
            var rgba = Gdk.RGBA(); if (!rgba.parse(marker.color)) rgba.parse("#9CA3AF");
            cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, 1); cr.arc(width / 2.0, height / 2.0, 5, 0, Math.PI * 2);
            if (marker.color == "") { cr.set_line_width(1.5); cr.stroke(); } else cr.fill();
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(TagMarker));
            }
            base.dispose();
        }
    }

    [GtkTemplate (ui = "/com/majoris/files/ui/tags-palette.ui")]
    public class TagPalette : Gtk.Popover {
        private bool template_disposing;
        static construct { typeof(TagMarker).ensure(); }
        [GtkChild] private unowned Gtk.FlowBox palette;
        [GtkChild] private unowned Gtk.Button custom;
        public signal void chosen(string color);
        public signal void failed(string message);
        public TagPalette(string current) {
            build_palette(this, current);
        }
        static void build_palette(TagPalette palette_owner, string current) {
            weak TagPalette owner = palette_owner;
            string[] colors = {"#EF4444", "#F97316", "#F59E0B", "#22C55E", "#3B82F6", "#A855F7", "#9CA3AF", ""};
            string normalized = current; try { normalized = MetadataStore.validate_tag_color(current); } catch (Error e) {}
            for (int i = 0; i < colors.length; i++) {
                string color = colors[i];
                var button = (Gtk.ToggleButton)palette_owner.palette.get_child_at_index(i).child;
                button.active = normalized == color;
                button.clicked.connect(() => { if (owner != null) { owner.chosen(color); owner.popdown(); } });
            }
            bool custom_selected = normalized != "" && !(normalized in colors);
            var custom = palette_owner.custom;
            custom.label = custom_selected ? _("Custom Colour… (Selected)") : _("Custom Colour…");
            custom.clicked.connect(() => {
                if (owner == null) return;
                // Keep the palette alive only for the native chooser's bounded task.
                TagPalette retained = owner;
                var dialog = new Gtk.ColorDialog(); dialog.title = _("Tag Colour"); dialog.with_alpha = false;
                var rgba = Gdk.RGBA(); if (!rgba.parse(current)) rgba.parse("#9CA3AF");
                dialog.choose_rgba.begin(retained.get_root() as Gtk.Window, rgba, null, (obj, res) => {
                    try { var result = dialog.choose_rgba.end(res); retained.chosen(result.to_string()); if (retained.get_root() != null) retained.popdown(); }
                    catch (Error e) { if (!(e is Gtk.DialogError.DISMISSED) && !(e is IOError.CANCELLED)) retained.failed(e.message); }
                });
            });
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                child = null;
                dispose_template(typeof(TagPalette));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/tag-name-editor.ui")]
    public class TagNameEditor : Gtk.Box {
        private bool template_disposing;
        [GtkChild]
        public unowned Gtk.Entry entry;
        [GtkChild]
        public unowned Gtk.Label error_label;
        public signal void submitted(string name);
        public signal void cancelled();

        public TagNameEditor() { }
        construct {
              entry.update_property(Gtk.AccessibleProperty.LABEL, _("Tag name"), -1);

            entry.activate.connect(() => submitted(entry.text));
            var keys = new Gtk.EventControllerKey(); keys.propagation_phase = Gtk.PropagationPhase.CAPTURE; keys.key_pressed.connect((key, code, mods) => { if (key == Gdk.Key.Escape) { cancelled(); return true; } return false; }); entry.add_controller(keys);
        }
        public void show_error(string message) { error_label.label = message; error_label.visible = true; entry.add_css_class("error"); entry.grab_focus(); }
        public void reset(string name = "") { error_label.visible = false; entry.remove_css_class("error"); entry.text = name; }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(TagNameEditor));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/tags-manager-row.ui")]
    public class TagManageRow : Gtk.ListBoxRow {
        private bool template_disposing;
        static construct { typeof(TagNameEditor).ensure(); typeof(TagMarker).ensure(); }
        public TagDefinition? tag;
        [GtkChild]
        public unowned TagNameEditor editor;
        [GtkChild]
        public unowned Gtk.Label label;
        [GtkChild]
        public unowned Gtk.Switch sidebar_switch;
        [GtkChild]
        public unowned Gtk.MenuButton color_button;
        [GtkChild]
        public unowned TagMarker marker;
        [GtkChild]
        private unowned Gtk.Stack name_stack;
        MetadataStore metadata;
        public bool editing { get; private set; }
        bool updating;
        Gtk.EventControllerFocus focus = new Gtk.EventControllerFocus();
        public signal void draft_cancelled();

        [GtkChild] private unowned Gtk.Box box;
        public TagManageRow(MetadataStore store, TagDefinition? tag = null) {
            this.metadata = store; this.tag = tag;

              MenuPresentation.button(color_button);
            color_button.set_create_popup_func(create_palette);

            editor.submitted.connect(commit);
            editor.cancelled.connect(() => { editing = false; if (this.tag == null) draft_cancelled(); else name_stack.visible_child_name = "label"; });
            focus.leave.connect(on_focus_leave); editor.entry.add_controller(focus);
            sidebar_switch.notify["active"].connect(() => {
                if (template_disposing || updating || this.tag == null) return;
                try { var latest = metadata.tag_by_id(this.tag.id); if (latest != null) metadata.update_tag(latest.id, latest.name, latest.color, sidebar_switch.active); }
                catch (Error e) { begin_edit(); editor.show_error(e.message); }
            });
            var drag = new Gtk.DragSource(); drag.actions = Gdk.DragAction.MOVE;
            drag.prepare.connect(() => this.tag == null || editing ? null : new Gdk.ContentProvider.for_value("majoris-tag:" + this.tag.id.to_string())); add_controller(drag);
            var drop = new Gtk.DropTarget(typeof(string), Gdk.DragAction.MOVE); drop.drop.connect(accept_reorder); add_controller(drop);
            update(tag); if (tag == null) begin_edit();
        }
        static void create_palette(Gtk.MenuButton button) {
            var owner = button.get_ancestor(typeof(TagManageRow)) as TagManageRow; if (owner == null || owner.tag == null) return;
            button.popover = palette_for(owner);
        }
        static TagPalette palette_for(TagManageRow row) {
            var palette = new TagPalette(row.tag.color);
            palette.failed.connect(row.palette_error); palette.chosen.connect(row.apply_color); return palette;
        }
        void palette_error(string message) { var dialog = get_ancestor(typeof(Adw.PreferencesDialog)) as Adw.PreferencesDialog; if (dialog != null) dialog.add_toast(new Adw.Toast(message)); }
        void apply_color(string color) {
            if (tag == null) return;
            try { var latest = metadata.tag_by_id(tag.id); if (latest != null) metadata.update_tag(latest.id, latest.name, color, latest.sidebar_visible); }
            catch (Error e) { begin_edit(); editor.show_error(e.message); }
        }
        void on_focus_leave() { Idle.add(() => { if (!template_disposing && editing && !focus.contains_focus && get_root() != null) commit(editor.entry.text); return Source.REMOVE; }); }
        bool accept_reorder(Value value, double x, double y) {
            string? text = value.get_string(); int64 id = 0;
            if (text == null || !text.has_prefix("majoris-tag:") || !int64.try_parse(text.substring(12), out id) || tag == null) return false;
            try { metadata.move_tag(id, get_index()); return true; }
            catch (Error e) { var owner = get_ancestor(typeof(Adw.PreferencesDialog)) as Adw.PreferencesDialog; if (owner != null) owner.add_toast(new Adw.Toast(e.message)); return false; }
        }
        public void update(TagDefinition? tag) {
            this.tag = tag; updating = true;
            label.label = tag == null ? "" : tag.name;
            marker.color = tag == null ? "" : tag.color;
            sidebar_switch.sensitive = tag != null; sidebar_switch.active = tag == null || tag.sidebar_visible;
            sidebar_switch.update_property(Gtk.AccessibleProperty.LABEL, tag == null ? _("Show in Sidebar") : _("Show %s in Sidebar").printf(tag.name), -1);
            color_button.sensitive = tag != null;
            if (tag != null) {
                color_button.update_property(Gtk.AccessibleProperty.LABEL, _("Colour for %s").printf(tag.name), -1);
                if (color_button.popover == null || !color_button.popover.visible) color_button.popover = null;
            }
            if (!editing) name_stack.visible_child_name = "label"; updating = false;
        }
        public void begin_edit() { editing = true; editor.reset(tag == null ? "" : tag.name); name_stack.visible_child_name = "editor"; editor.entry.grab_focus(); editor.entry.select_region(0, -1); }
        public void commit(string name) {
            if (!editing) return;
            try {
                if (tag == null) tag = metadata.create_tag(name);
                else { var latest = metadata.tag_by_id(tag.id); if (latest == null) throw new FileError.INVALID(_("This tag no longer exists.")); metadata.update_tag(tag.id, name, latest.color, latest.sidebar_visible); tag = metadata.tag_by_id(tag.id); }
                editing = false; update(tag);
            } catch (Error e) { editor.show_error(e.message); }
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                child = null;
                dispose_template(typeof(TagManageRow));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/tags-manager.ui")]
    public class TagsDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        MetadataStore metadata;
        [GtkChild]
        public unowned Gtk.ListBox list;
        [GtkChild]
        public unowned Gtk.Button new_button;
        [GtkChild]
        public unowned Gtk.Button rename_button;
        [GtkChild]
        public unowned Gtk.Button delete_button;
        Gee.ArrayList<TagManageRow> rows = new Gee.ArrayList<TagManageRow>();
        ulong handler;
        uint refresh_source;

        [GtkChild] private unowned Gtk.Box controls;
        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Adw.PreferencesPage page;
        public TagsDialog(MetadataStore store) {
            this.metadata = store;

            list.set_sort_func(compare_rows);

            new_button.clicked.connect(() => {
                foreach (var row in rows) if (row.tag == null) { row.begin_edit(); return; }
                var row = make_row(null); rows.add(row); list.append(row); list.select_row(row); row.begin_edit();
            });
            rename_button.clicked.connect(() => { var row = list.get_selected_row() as TagManageRow; if (row != null) row.begin_edit(); });
            delete_button.clicked.connect(() => delete_selected.begin());
            list.row_selected.connect(() => { if (template_disposing || list == null) return; var row = list.get_selected_row() as TagManageRow; rename_button.sensitive = row != null && row.tag != null; delete_button.sensitive = rename_button.sensitive; });
            var keys = new Gtk.EventControllerKey(); keys.propagation_phase = Gtk.PropagationPhase.CAPTURE; keys.key_pressed.connect((key, code, mods) => {
                var row = list.get_selected_row() as TagManageRow; if (row == null || row.editing) return false;
                if (key == Gdk.Key.F2) { row.begin_edit(); return true; }
                if (key == Gdk.Key.Delete) { delete_selected.begin(); return true; }
                if ((mods & Gdk.ModifierType.ALT_MASK) != 0 && (key == Gdk.Key.Up || key == Gdk.Key.Down)) { move(row, key == Gdk.Key.Up ? -1 : 1); return true; }
                return false;
            }); list.add_controller(keys);
            handler = observe_metadata(metadata, this);
            closed.connect(disconnect_metadata);
            refresh();
        }
        static ulong observe_metadata(MetadataStore store, TagsDialog dialog) {
            weak TagsDialog owner = dialog;
            return store.tag_definitions_changed.connect(() => { if (owner != null) owner.schedule_refresh(); });
        }
        static int compare_rows(Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
            var first = (TagManageRow)a; var second = (TagManageRow)b;
            int x = first.tag == null ? int.MAX : first.tag.position, y = second.tag == null ? int.MAX : second.tag.position;
            return x < y ? -1 : x > y ? 1 : first.tag == null || second.tag == null ? 0 : first.tag.id < second.tag.id ? -1 : first.tag.id > second.tag.id ? 1 : 0;
        }
        void disconnect_metadata() {
            if (handler != 0) { metadata.disconnect(handler); handler = 0; }
            if (refresh_source != 0) { Source.remove(refresh_source); refresh_source = 0; }
        }
        protected override void dispose() {
            if (template_disposing) { base.dispose(); return; }
            template_disposing = true;
            disconnect_metadata();
            dispose_template(typeof(TagsDialog));
            base.dispose();
        }
        void schedule_refresh() { if (refresh_source == 0) refresh_source = Idle.add(() => { refresh_source = 0; refresh(); return Source.REMOVE; }); }
        TagManageRow make_row(TagDefinition? tag) { var row = new TagManageRow(metadata, tag); row.draft_cancelled.connect(remove_drafts); return row; }
        void remove_drafts() {
            TagManageRow? draft = null; foreach (var row in rows) if (row.tag == null) { draft = row; break; }
            if (draft != null) { rows.remove(draft); list.remove(draft); }
        }
        public void refresh() {
            var selected = list.get_selected_row() as TagManageRow; int64 selected_id = selected == null || selected.tag == null ? 0 : selected.tag.id;
            var next = new Gee.ArrayList<TagManageRow>();
            foreach (var tag in metadata.tag_definitions()) {
                TagManageRow? row = null; foreach (var existing in rows) if (existing.tag != null && existing.tag.id == tag.id) { row = existing; break; }
                if (row == null) row = make_row(tag); else row.update(tag); next.add(row);
            }
            foreach (var row in rows) if (row.tag == null && row.editing) next.add(row);
            foreach (var row in rows) if (!next.contains(row)) list.remove(row);
            foreach (var row in next) if (row.get_parent() == null) list.append(row);
            list.invalidate_sort();
            foreach (var row in next) if (row.tag != null && row.tag.id == selected_id) list.select_row(row);
            rows = next; rename_button.sensitive = selected_id != 0; delete_button.sensitive = selected_id != 0;
        }
        void move(TagManageRow row, int direction) { if (row.tag != null) try { metadata.move_tag(row.tag.id, rows.index_of(row) + direction); } catch (Error e) { add_toast(new Adw.Toast(e.message)); } }
        async void delete_selected() {
            var row = list.get_selected_row() as TagManageRow; if (row == null || row.tag == null) return;
            int64 id = row.tag.id; var confirm = new Adw.AlertDialog(_("Delete “%s”?").printf(row.tag.name), _("This tag will be removed from all assigned files and folders. Your files and folders will not be deleted."));
            confirm.add_response("cancel", _("Cancel")); confirm.add_response("delete", _("Delete Tag")); confirm.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE); confirm.default_response = "cancel"; confirm.close_response = "cancel";
            if ((yield confirm.choose(this, null)) == "delete") try { metadata.remove_tag(id); } catch (Error e) { add_toast(new Adw.Toast(e.message)); }
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/tags-assignment.ui")]
    public class TagAssignmentDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        static construct { typeof(TagNameEditor).ensure(); }
        MetadataStore metadata;
        public Gee.ArrayList<File> files = new Gee.ArrayList<File>();
        [GtkChild]
        public unowned Gtk.SearchEntry search;
        [GtkChild]
        public unowned Gtk.ListBox list;
        [GtkChild] public unowned TagNameEditor creator;
        [GtkChild]
        public unowned Gtk.Button new_button;
        [GtkChild]
        public unowned Gtk.Button manage_button;
        Gee.HashMap<string, Gtk.CheckButton> checks = new Gee.HashMap<string, Gtk.CheckButton>();
        Gee.HashMap<string, Adw.ActionRow> rows = new Gee.HashMap<string, Adw.ActionRow>();
        bool updating;
        ulong definitions_handler;
        ulong assignments_handler;
        Gee.HashMap<string, ulong?> toggled_handlers = new Gee.HashMap<string, ulong?>();

        [GtkChild] private unowned Gtk.Box controls;
        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Adw.PreferencesPage page;
        public TagAssignmentDialog(MetadataStore store, Gee.List<FileItem> selection) {
            this.metadata = store;
            foreach (var item in selection) files.add(item.file);

            list.set_sort_func(compare_rows);
            list.set_filter_func(filter_for(search));
            search.search_changed.connect(() => { if (!template_disposing && list != null) list.invalidate_filter(); });


            new_button.clicked.connect(() => { creator.visible = true; creator.reset(search.text); creator.entry.grab_focus(); });
            creator.cancelled.connect(() => creator.visible = false);
            creator.submitted.connect((name) => {
                try { metadata.create_tag(name, "", files); creator.visible = false; search.text = ""; }
                catch (Error e) { creator.show_error(e.message); }
            });
            manage_button.clicked.connect(() => new TagsDialog(metadata).present(this));
            definitions_handler = observe_metadata(metadata, this, true);
            assignments_handler = observe_metadata(metadata, this, false);
            closed.connect(disconnect_metadata); refresh();
        }
        static Gtk.ListBoxFilterFunc filter_for(Gtk.SearchEntry entry) {
            weak Gtk.SearchEntry search = entry;
            return (row) => { var tag = row.get_data<TagDefinition>("tag"); return search != null && tag != null && tag.name.casefold().contains(search.text.casefold()); };
        }
        static ulong observe_metadata(MetadataStore store, TagAssignmentDialog dialog, bool definitions) {
            weak TagAssignmentDialog owner = dialog;
            if (definitions) return store.tag_definitions_changed.connect(() => { if (owner != null) owner.refresh(); });
            return store.tag_assignments_changed.connect(() => { if (owner != null) owner.refresh_states(); });
        }
        static ulong bind_toggle(Gtk.CheckButton check, TagAssignmentDialog dialog, int64 id) {
            weak TagAssignmentDialog owner = dialog; weak Gtk.CheckButton toggle = check;
            return check.toggled.connect(() => {
                if (owner == null || toggle == null || owner.template_disposing || owner.updating) return;
                bool assigned = toggle.active || toggle.inconsistent;
                try { owner.metadata.set_tag_for_files(owner.files, id, assigned); }
                catch (Error e) { owner.add_toast(new Adw.Toast(e.message)); owner.refresh_states(); }
            });
        }
        static int compare_rows(Gtk.ListBoxRow a, Gtk.ListBoxRow b) {
            var first = a.get_data<TagDefinition>("tag"); var second = b.get_data<TagDefinition>("tag");
            if (first == null || second == null) return 0;
            return first.position < second.position ? -1 : first.position > second.position ? 1 : first.id < second.id ? -1 : first.id > second.id ? 1 : 0;
        }
        void disconnect_metadata() {
            if (definitions_handler != 0) { metadata.disconnect(definitions_handler); definitions_handler = 0; }
            if (assignments_handler != 0) { metadata.disconnect(assignments_handler); assignments_handler = 0; }
            foreach (var id in toggled_handlers.keys) if (checks.has_key(id)) checks[id].disconnect(toggled_handlers[id]); toggled_handlers.clear();
        }
        protected override void dispose() {
            if (template_disposing) { base.dispose(); return; }
            template_disposing = true;
            disconnect_metadata();
            dispose_template(typeof(TagAssignmentDialog));
            base.dispose();
        }
        public Gtk.CheckButton? checkbox(int64 id) { return checks[id.to_string()]; }
        public void refresh() {
            updating = true;
            var tags = metadata.tag_definitions(); var ids = new Gee.HashSet<string>(); foreach (var tag in tags) ids.add(tag.id.to_string());
            var obsolete = new Gee.ArrayList<string>(); foreach (var id in rows.keys) if (!ids.contains(id)) obsolete.add(id);
            foreach (var id in obsolete) { if (toggled_handlers.has_key(id)) checks[id].disconnect(toggled_handlers[id]); toggled_handlers.unset(id); list.remove(rows[id]); rows.unset(id); checks.unset(id); }
            for (int i = 0; i < tags.size; i++) {
                var tag = tags[i]; var row = rows[tag.id.to_string()];
                if (row == null) {
                    var presentation = new TagAssignmentRow(); row = presentation;
                    var check = presentation.check;
                    row.set_data<TagMarker>("marker", presentation.marker);
                    int64 id = tag.id; toggled_handlers[id.to_string()] = bind_toggle(check, this, id);
                    checks[id.to_string()] = check; rows[id.to_string()] = row; list.append(row);
                }
                row.title = tag.name; row.set_data<TagDefinition>("tag", tag); row.get_data<TagMarker>("marker").color = tag.color;
                checks[tag.id.to_string()].update_property(Gtk.AccessibleProperty.LABEL, _("Assign %s").printf(tag.name), -1);
            }
            list.invalidate_sort(); updating = false; refresh_states(); list.invalidate_filter();
        }
        public void refresh_states() {
            updating = true; var counts = new Gee.HashMap<string, int>();
            foreach (var file in files) foreach (var tag in metadata.tags_for(file)) counts[tag.id.to_string()] = (counts[tag.id.to_string()]) + 1;
            foreach (var id in checks.keys) { int count = counts[id]; checks[id].inconsistent = count > 0 && count < files.size; checks[id].active = files.size > 0 && count == files.size; checks[id].sensitive = files.size > 0 && metadata.available; }
            updating = false;
        }
    }
}
