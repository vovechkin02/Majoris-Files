namespace MajorisFiles {
    public class Dialogs : Object {
        public static void error(Gtk.Widget parent, string message)
        {
            var dialog = new Adw.AlertDialog(_("Could not complete the action"), message);
            dialog.add_response("close", _("Close"));
            dialog.present(parent);
        }
        public static async string? prompt(Gtk.Widget parent, string title, string initial = "", string? body = null)
        {
            var dialog = new Adw.AlertDialog(title, body);
            var entry = new Gtk.Entry();
            entry.text = initial;
            entry.activates_default = true;
            dialog.extra_child = entry;
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("apply", _("Apply"));
            dialog.default_response = "apply";
            dialog.close_response = "cancel";
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED);
            entry.grab_focus();
            return (yield dialog.choose(parent, null)) == "apply" ? entry.text : null;
        }
        public static async bool confirm(Gtk.Widget parent, string title, string body, string action)
        {
            var dialog = new Adw.AlertDialog(title, body);
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("apply", action);
            dialog.close_response = "cancel";
            dialog.set_response_appearance("apply", Adw.ResponseAppearance.DESTRUCTIVE);
            return (yield dialog.choose(parent, null)) == "apply";
        }
        public static async string? password(Gtk.Widget parent, string title, bool confirmation = false, string note = "")
        {
            string message = "The password is used for this operation and is not saved." + (note == "" ? "" : "\n" + note);
            while(true)
            {
                var dialog = new Adw.AlertDialog(title, message);
                var fields = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
                var entry = new Adw.PasswordEntryRow();
                entry.title = _("Password");
                fields.append(entry);
                var repeat = new Adw.PasswordEntryRow();
                repeat.title = _("Confirm Password");
                if(confirmation)
                    fields.append(repeat);
                dialog.extra_child = fields;
                dialog.add_response("cancel", _("Cancel"));
                dialog.add_response("apply", _("Continue"));
                dialog.close_response = "cancel";
                dialog.default_response = "apply";
                dialog.set_response_appearance("apply", Adw.ResponseAppearance.SUGGESTED);
                if((yield dialog.choose(parent, null)) != "apply")
                    return null;
                if(entry.text != "" && entry.text.length <= 4096 && (!confirmation || entry.text == repeat.text))
                {
                    string result = entry.text;
                    entry.text = "";
                    repeat.text = "";
                    return result;
                }
                entry.text = "";
                repeat.text = "";
                message = "Enter a non-empty password up to 4096 bytes. Confirmation must match.";
            }
        }
    }
}
