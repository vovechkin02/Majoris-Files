namespace MajorisFiles {
    // This chooser changes an association; the existing Open Once workflow is separate.
    public class AssociationChooser : Adw.Dialog {
        public signal void changed();
        public AppInfo? selected;
        FileItem item;
        Gtk.Widget owner;
        Gtk.CheckButton? first;
        Gtk.Button apply = new Gtk.Button.with_label(_("Set Default"));
        Gee.HashSet<string> seen = new Gee.HashSet<string>();
        Gee.ArrayList<Adw.ActionRow> rows = new Gee.ArrayList<Adw.ActionRow>();
        public AssociationChooser(Gtk.Widget owner, FileItem item) {
            title = _("Choose Application"); content_width = 480; content_height = 540;
            this.owner = owner; this.item = item;
            var layout = new Adw.ToolbarView();
            layout.add_top_bar(new Adw.HeaderBar());
            var page = new Adw.PreferencesPage(); layout.content = page; child = layout;
            var search_group = new Adw.PreferencesGroup(); page.add(search_group);
            var search = new Gtk.SearchEntry(); search.placeholder_text = _("Search applications"); search_group.add(search);
            search.search_changed.connect(() => { foreach (var row in rows) row.visible = row.title.casefold().contains(search.text.casefold()); });
            var current = AppInfo.get_default_for_type(item.mime, !item.file.is_native());
            if (current != null) { var group = new Adw.PreferencesGroup(); group.title = _("Current Default"); page.add(group); add_app(group, current, true); }
            var recommended = new Adw.PreferencesGroup(); recommended.title = _("Recommended Applications"); page.add(recommended);
            foreach (var app in AppInfo.get_all_for_type(item.mime)) add_app(recommended, app, false);
            var other = new Adw.PreferencesGroup(); other.title = _("Other Applications"); page.add(other);
            foreach (var app in AppInfo.get_all()) if (app.should_show()) add_app(other, app, false);
            var actions = new Adw.HeaderBar();
            actions.show_title = false; actions.show_back_button = false;
            actions.show_start_title_buttons = false; actions.show_end_title_buttons = false;
            layout.add_bottom_bar(actions);
            apply.sensitive = false; apply.add_css_class("suggested-action"); actions.pack_end(apply); apply.clicked.connect(apply_selected);
            var reset = new Gtk.Button.with_label(_("Reset to System Default")); actions.pack_start(reset);
            reset.clicked.connect(() => { AppInfo.reset_type_associations(item.mime); changed(); close(); });
            recommended.visible = recommended.get_first_child() != null;
        }
        void add_app(Adw.PreferencesGroup group, AppInfo app, bool current) {
            string key = app.get_id() ?? app.get_commandline() ?? app.get_display_name();
            if (!seen.add(key)) return;
            var row = PropertiesDialog.value_row(app.get_display_name(), current ? _("Current default") : app.get_description() ?? "");
            row.subtitle_lines = 2;
            if (app.get_icon() != null) { var image = new Gtk.Image.from_gicon(app.get_icon()); image.pixel_size = 32; row.add_prefix(image); }
            var choice = new Gtk.CheckButton(); choice.valign = Gtk.Align.CENTER; choice.tooltip_text = app.get_display_name();
            if (first == null) first = choice; else choice.set_group(first);
            row.add_suffix(choice); row.activatable_widget = choice;
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
    }
    public class AssociationsDialog : Adw.PreferencesDialog {
        public AssociationsDialog(Gtk.Window parent, FileItem item) {
            title = _("Open With"); var page = new AssociationsPage(parent, item);
            add(page); page.opened.connect(() => close()); present(parent);
        }
    }
    public class AssociationsPage : Adw.PreferencesPage {
        public signal void opened();
        public AssociationsPage(Gtk.Window parent, FileItem item)
        {
            title = _("Open With");
            icon_name = "application-x-executable-symbolic";
            var group = new Adw.PreferencesGroup();
            add(group);
            var current = AppInfo.get_default_for_type(item.mime, false);
            var default_row = new Adw.ActionRow();
            default_row.title = _("Default Application");
            default_row.subtitle = current == null ? "None" : current.get_display_name();
            group.add(default_row);
            var reset = new Gtk.Button.with_label(_("Reset Association"));
            group.add(reset);
            reset.clicked.connect(() => { AppInfo.reset_type_associations(item.mime);
                                          default_row.subtitle = _("System default restored");
                });
            foreach(var app in AppInfo.get_all_for_type(item.mime))
            {
                var row = new Adw.ActionRow();
                row.title = app.get_display_name();
                if(app.get_icon() != null)
                    row.add_prefix(new Gtk.Image.from_gicon(app.get_icon()));
                var open = new Gtk.Button.with_label(_("Open"));
                row.add_suffix(open);
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
                var set_default = new Gtk.Button.with_label(_("Set Default"));
                row.add_suffix(set_default);
                set_default.clicked.connect(() => { try { app.set_as_default_for_type(item.mime);
                                                          default_row.subtitle = app.get_display_name();
                                                    }
                                                    catch(Error e) { Dialogs.error(parent, e.message);
                                                    }
                    });
                group.add(row);
            }
            var choose = new Gtk.Button.with_label(_("Choose Another Application…"));
            group.add(choose);
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
    }
}
