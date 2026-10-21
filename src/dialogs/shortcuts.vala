namespace MajorisFiles {
    public class ShortcutsDialog : Adw.PreferencesDialog {
        public ShortcutsDialog()
        {
            title = "Keyboard Shortcuts";
            var page = new Adw.PreferencesPage();
            add(page);
            var browsing = new Adw.PreferencesGroup();
            browsing.title = _("Browsing");
            page.add(browsing);
            foreach(var entry in new string[] {
                "New Window|<Control>n", "New Tab|<Control>t", "Close Tab|<Control>w", "Reopen Closed Tab|<Control><Shift>t",
                "Back|<Alt>Left", "Forward|<Alt>Right", "Parent Folder|<Alt>Up", "Edit Location|<Control>l", "Search|<Control>f", "Show Hidden Files|<Control>h"
            })
                add_shortcut(browsing, entry);
            var files = new Adw.PreferencesGroup();
            files.title = _("Files and Selection");
            page.add(files);
            foreach(var entry in new string[] {
                "New Folder|<Control><Shift>n", "Select All|<Control>a", "Rename|F2", "Move to Trash|Delete", "Permanently Delete|<Shift>Delete",
                "Copy|<Control>c", "Cut|<Control>x", "Paste|<Control>v", "Undo|<Control>z", "Redo|<Control><Shift>z", "Properties|<Alt>Return", "Quick Preview|space", "Close Preview|Escape"
            })
                add_shortcut(files, entry);
        }
        void add_shortcut(Adw.PreferencesGroup group, string entry)
        {
            var parts = entry.split("|", 2);
            var row = new Adw.ActionRow();
            row.title = parts[0];
            var shortcut = new Gtk.ShortcutLabel(parts[1]);
            shortcut.valign = Gtk.Align.CENTER;
            row.add_suffix(shortcut);
            group.add(row);
        }
    }
}
