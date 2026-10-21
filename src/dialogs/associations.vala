namespace MajorisFiles {
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
