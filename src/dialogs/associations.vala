namespace MajorisFiles {
    // This chooser changes an association; the existing Open Once workflow is separate.
    [GtkTemplate (ui = "/com/majoris/files/ui/association-chooser.ui")]
    public class AssociationChooser : Adw.Dialog {
        private bool template_disposing;
        public signal void changed();
        public AppInfo? selected;
        FileItem item;
        Gtk.Widget owner;
        Gtk.CheckButton? first;
        [GtkChild]
        private unowned Gtk.Button apply;
        Gee.HashSet<string> seen = new Gee.HashSet<string>();
        Gee.ArrayList<Adw.ActionRow> rows = new Gee.ArrayList<Adw.ActionRow>();

        [GtkChild] private unowned Adw.HeaderBar actions;
        [GtkChild] private unowned Adw.HeaderBar header;
        [GtkChild] private unowned Adw.ToolbarView layout;
        [GtkChild] private unowned Adw.PreferencesGroup other;
        [GtkChild] private unowned Adw.PreferencesPage page;
        [GtkChild] private unowned Adw.PreferencesGroup recommended;
        [GtkChild] private unowned Gtk.Button reset;
        [GtkChild] private unowned Gtk.SearchEntry search;
        [GtkChild] private unowned Adw.PreferencesGroup search_group;
        [GtkChild] private unowned Adw.PreferencesGroup current_group;
        public AssociationChooser(Gtk.Widget owner, FileItem item) {
            this.owner = owner; this.item = item;

            search.search_changed.connect(() => { foreach (var row in rows) row.visible = row.title.casefold().contains(search.text.casefold()); });
            var current = AppInfo.get_default_for_type(item.mime, !item.file.is_native());
            current_group.visible = current != null;
            if (current != null) add_app(current_group, current, true);

            foreach (var app in AppInfo.get_all_for_type(item.mime)) add_app(recommended, app, false);

            foreach (var app in AppInfo.get_all()) if (app.should_show()) add_app(other, app, false);

               apply.clicked.connect(apply_selected);

            reset.clicked.connect(() => { AppInfo.reset_type_associations(item.mime); changed(); close(); });
            recommended.visible = recommended.get_first_child() != null;
        }
        void add_app(Adw.PreferencesGroup group, AppInfo app, bool current) {
            string key = app.get_id() ?? app.get_commandline() ?? app.get_display_name();
            if (!seen.add(key)) return;
            var row = new ApplicationChoiceRow(); row.title = app.get_display_name();
            row.subtitle = current ? _("Current default") : app.get_description() ?? "";
            row.icon.visible = app.get_icon() != null;
            if (app.get_icon() != null) row.icon.set_from_gicon(app.get_icon());
            var choice = row.choice; choice.tooltip_text = app.get_display_name();
            if (first == null) first = choice; else choice.set_group(first);
            choice.toggled.connect(() => { if (choice.active) { selected = app; apply.sensitive = true; } else if (selected != null && selected.equal(app)) { selected = null; apply.sensitive = false; } });
            if (!item.file.is_native() && !app.supports_uris()) { row.sensitive = false; row.subtitle = _("This application requires a local file"); }
            if (current) choice.active = true;
            rows.add(row); group.add(row);
        }
        public void apply_selected() {
            if (selected == null) return;
            try {
                bool available = false;
                foreach (var app in AppInfo.get_all()) if (app.equal(selected)) { available = true; break; }
                if (!available) throw new FileError.UNSUPPORTED("The selected application is no longer installed");
                if (!item.file.is_native() && !selected.supports_uris()) throw new FileError.UNSUPPORTED("This application requires a local file");
                string? executable = selected.get_executable();
                if (executable == null || Environment.find_program_in_path(executable) == null) throw new FileError.UNSUPPORTED("The selected application executable is unavailable");
                if (!selected.set_as_default_for_type(item.mime)) throw new FileError.INVALID("The default application could not be changed");
                changed(); close();
            } catch (Error e) { Dialogs.error(this, e.message); }
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                child = null;
                dispose_template(typeof(AssociationChooser));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/associations-dialog.ui")]
    public class AssociationsDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        public AssociationsDialog(Gtk.Window parent, FileItem item) {
            var page = new AssociationsPage(parent, item);
            add(page); page.opened.connect(() => close()); present(parent);
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(AssociationsDialog));
            }
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/associations.ui")]
    public class AssociationsPage : Adw.PreferencesPage {
        private bool template_disposing;
        public signal void opened();

        [GtkChild] private unowned Gtk.Button choose;
        [GtkChild] private unowned Adw.ActionRow default_row;
        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Gtk.Button reset;
        public AssociationsPage(Gtk.Window parent, FileItem item)
        {
            var current = AppInfo.get_default_for_type(item.mime, false);

            default_row.subtitle = current == null ? "None" : current.get_display_name();

            reset.clicked.connect(() => { AppInfo.reset_type_associations(item.mime);
                                          default_row.subtitle = _("System default restored");
                });
            foreach(var app in AppInfo.get_all_for_type(item.mime))
            {
                var row = new ApplicationLaunchRow(); row.title = app.get_display_name();
                row.icon.visible = app.get_icon() != null;
                if (app.get_icon() != null) row.icon.set_from_gicon(app.get_icon());
                var open = row.open;
                open.clicked.connect(() => {
                    try {
                        var context = parent.get_display().get_app_launch_context();
                        if(app.supports_uris())
                        {
                            var uris = new GLib.List<string>();
                            uris.append(item.file.get_uri());
                            app.launch_uris(uris, context);
                        }
                        else { if(!item.file.is_native())
                                   throw new FileError.UNSUPPORTED("This application needs a local file");
                               var files = new GLib.List<File>();
                               files.append(item.file);
                               app.launch(files, context);
                        }
                        opened();
                    }
                    catch(Error e) { Dialogs.error(parent, e.message);
                    }
                });
                var set_default = row.set_default;
                set_default.clicked.connect(() => { try { app.set_as_default_for_type(item.mime);
                                                          default_row.subtitle = app.get_display_name();
                                                    }
                                                    catch(Error e) { Dialogs.error(parent, e.message);
                                                    }
                    });
                group.add(row);
            }

            group.remove(choose); group.add(choose);
            choose.clicked.connect(() => { var launcher = new Gtk.FileLauncher(item.file);
                                           launcher.always_ask = true;
                                           launcher.launch.begin(parent, null, (obj, res) => { try { launcher.launch.end(res);
                                                                                               }
                                                                                               catch(Error e) { if(!(e is Gtk.DialogError.DISMISSED))
                                                                                                                    Dialogs.error(parent, e.message);
                                                                                               }
                                               });
                });

        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(AssociationsPage));
            }
            base.dispose();
        }
    }
}
