namespace MajorisFiles {
    public class SearchFilters : Adw.PreferencesDialog {
        public signal void applied(SearchQuery query);
        public SearchFilters(SearchQuery current)
        {
            title = "Search Filters";
            var page = new Adw.PreferencesPage();
            var group = new Adw.PreferencesGroup();
            page.add(group);
            add(page);
            string[] kinds = {
                "Any", "Folder", "Image", "Video", "Audio", "PDF", "Document", "Spreadsheet", "Archive", "Text"
            };
            var type_row = new Adw.ComboRow();
            type_row.title = _("Type");
            type_row.model = new Gtk.StringList(kinds);
            for(uint i = 0; i < kinds.length; i++)
                if(kinds[i] == current.kind)
                    type_row.selected = i;
            group.add(type_row);
            var mime = entry(group, "MIME Type", current.mime);
            var content = entry(group, "Containing Text", current.content);
            var explanation = new Adw.ActionRow();
            explanation.title = _("Content search");
            explanation.subtitle = _("Indexed document content, including PDFs and Office files, when indexed by the system. Filesystem fallback searches local text, JSON and XML up to 4 MiB.");
            group.add(explanation);
            var minimum = entry(group, "Minimum Size (bytes)", current.minimum == 0 ? "" : current.minimum.to_string());
            var maximum = entry(group, "Maximum Size (bytes)", current.maximum == uint64.MAX ? "" : current.maximum.to_string());
            string[] fields = {
                "Modified", "Created", "Accessed"
            };
            string[] attributes = {
                "modified", "created", "access"
            };
            var date_row = new Adw.ComboRow();
            date_row.title = _("Date Field");
            date_row.model = new Gtk.StringList(fields);
            for(uint i = 0; i < attributes.length; i++)
                if(attributes[i] == current.date_field)
                    date_row.selected = i;
            group.add(date_row);
            var after = entry(group, "From (YYYY-MM-DD)", date_text(current.after));
            var before = entry(group, "Through (YYYY-MM-DD)", date_text(current.before));
            var ranges = new Adw.ComboRow();
            ranges.title = _("Date Range");
            ranges.model = new Gtk.StringList({"Custom / Any", "Today", "Yesterday", "Past Week", "Past Month", "Past Year"});
            group.add(ranges);
            ranges.notify["selected"].connect(() => {
                if(ranges.selected == 0)
                    return;
                var now = new DateTime.now_local();
                DateTime start = now;
                switch(ranges.selected) {
                    case 2: start = now.add_days(-1);
                        break;
                    case 3: start = now.add_days(-7);
                        break;
                    case 4: start = now.add_months(-1);
                        break;
                    case 5: start = now.add_years(-1);
                        break;
                }
                after.text = start.format("%Y-%m-%d");
                before.text = (ranges.selected == 2 ? start : now).format("%Y-%m-%d");
            });
            var tag = entry(group, "Tag", current.tag);
            var owner = entry(group, "Owner", current.owner);
            var favorites = new Adw.SwitchRow();
            favorites.title = _("Favorites Only");
            favorites.active = current.favorites_only;
            group.add(favorites);
            var actions = new Adw.PreferencesGroup();
            page.add(actions);
            var buttons = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 8);
            var clear = new Gtk.Button.with_label(_("Clear Filters"));
            buttons.append(clear);
            clear.clicked.connect(() => { var query = new SearchQuery();
                                          query.text = current.text;
                                          applied(query);
                                          close();
                });
            var apply = new Gtk.Button.with_label(_("Apply"));
            apply.add_css_class("suggested-action");
            buttons.append(apply);
            actions.add(buttons);
            apply.clicked.connect(() => {
                try {
                    var query = new SearchQuery();
                    query.text = current.text;
                    query.kind = kinds[type_row.selected];
                    query.mime = mime.text.strip();
                    query.content = content.text;
                    query.minimum = size(minimum.text, 0);
                    query.maximum = size(maximum.text, uint64.MAX);
                    query.date_field = attributes[date_row.selected];
                    query.after = date(after.text, false);
                    query.before = date(before.text, true);
                    query.tag = tag.text.strip();
                    query.owner = owner.text.strip();
                    query.favorites_only = favorites.active;
                    if(query.minimum > query.maximum || query.after > query.before)
                        throw new FileError.INVALID("The range starts after it ends");
                    applied(query);
                    close();
                }
                catch(Error e) { Dialogs.error(get_root() as Gtk.Window, e.message);
                }
            });
        }
        static Adw.EntryRow entry(Adw.PreferencesGroup group, string title, string value)
        {
            var row = new Adw.EntryRow();
            row.title = title;
            row.text = value;
            group.add(row);
            return row;
        }
        static uint64 size(string text, uint64 fallback) throws Error
        {
            if(text.strip() == "")
                return fallback;
            uint64 value;
            if(!uint64.try_parse(text.strip(), out value) || text.strip().has_prefix("-"))
                throw new FileError.INVALID("Sizes must be non-negative whole bytes");
            return value;
        }
        static string date_text(uint64 time)
        {
            return time == 0 || time == uint64.MAX ? "" : new DateTime.from_unix_local((int64)time).format("%Y-%m-%d");
        }
        static uint64 date(owned string text, bool end) throws Error
        {
            text = text.strip();
            if(text == "")
                return end ? uint64.MAX : 0;
            if(text.length != 10)
                throw new FileError.INVALID("Dates must use YYYY-MM-DD");
            var parsed = new DateTime.from_iso8601(text + "T00:00:00", new TimeZone.local());
            if(parsed == null || parsed.format("%Y-%m-%d") != text)
                throw new FileError.INVALID("Invalid calendar date");
            return (uint64)(end ? parsed.add_days(1).to_unix() - 1 : parsed.to_unix());
        }
    }
}
