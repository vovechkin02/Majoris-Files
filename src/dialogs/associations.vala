namespace MajorisFiles {
    public class AssociationsDialog : Adw.PreferencesDialog {
        public AssociationsDialog(Gtk.Window parent, FileItem item)
        {
            title = "Applications for " + ContentType.get_description(item.mime);
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            page.add(group);
            add(page);
            var current = AppInfo.get_default_for_type(item.mime, false);
            var default_row = new Adw.ActionRow();
            default_row.title = "Default Application";
            default_row.subtitle = current == null ? "None" : current.get_display_name();
            group.add(default_row);
            var reset = new Gtk.Button.with_label("Reset Association");
            group.add(reset);
            reset.clicked.connect(() => { AppInfo.reset_type_associations(item.mime);
                                          default_row.subtitle = "System default restored";
                });
            foreach(var app in AppInfo.get_all_for_type(item.mime))
            {
                var row = new Adw.ActionRow();
                row.title = app.get_display_name();
                if(app.get_icon() != null)
                    row.add_prefix(new Gtk.Image.from_gicon(app.get_icon()));
                var open = new Gtk.Button.with_label("Open");
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
                        close();
                    }
                    catch(Error e) { Dialogs.error(parent, e.message);
                    }
                });
                var set_default = new Gtk.Button.with_label("Set Default");
                row.add_suffix(set_default);
                set_default.clicked.connect(() => { try { app.set_as_default_for_type(item.mime);
                                                          default_row.subtitle = app.get_display_name();
                                                    }
                                                    catch(Error e) { Dialogs.error(parent, e.message);
                                                    }
                    });
                group.add(row);
            }
            var choose = new Gtk.Button.with_label("Choose Another Application…");
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
            present(parent);
        }
    }
}
