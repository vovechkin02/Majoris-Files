namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/search-filters.ui")]
    public class SearchFilters : Adw.PreferencesDialog {
        private bool template_disposing;
        public signal void applied(SearchQuery query);

        [GtkChild] private unowned Adw.PreferencesGroup actions;
        [GtkChild] private unowned Gtk.Button apply;
        [GtkChild] private unowned Gtk.Box buttons;
        [GtkChild] private unowned Gtk.Button clear;
        [GtkChild] private unowned Adw.ComboRow date_row;
        [GtkChild] private unowned Adw.ActionRow explanation;
        [GtkChild] private unowned Adw.SwitchRow favorites;
        [GtkChild] private unowned Adw.PreferencesGroup group;
        [GtkChild] private unowned Adw.PreferencesPage page;
        [GtkChild] private unowned Adw.ComboRow ranges;
        [GtkChild] private unowned Adw.ComboRow type_row;
        [GtkChild] private unowned Adw.EntryRow mime;
        [GtkChild] private unowned Adw.EntryRow content;
        [GtkChild] private unowned Adw.EntryRow minimum;
        [GtkChild] private unowned Adw.EntryRow maximum;
        [GtkChild] private unowned Adw.EntryRow after;
        [GtkChild] private unowned Adw.EntryRow before;
        [GtkChild] private unowned Adw.EntryRow tag;
        [GtkChild] private unowned Adw.EntryRow owner;
        public SearchFilters(SearchQuery current)
        {
            string[] kinds = {
                "Any", "Folder", "Image", "Video", "Audio", "PDF", "Document", "Spreadsheet", "Archive", "Text"
            };


            for(uint i = 0; i < kinds.length; i++)
                if(kinds[i] == current.kind)
                    type_row.selected = i;

            mime.text = current.mime;
            content.text = current.content;

            minimum.text = current.minimum == 0 ? "" : current.minimum.to_string();
            maximum.text = current.maximum == uint64.MAX ? "" : current.maximum.to_string();
            string[] fields = {
                "Modified", "Created", "Accessed"
            };
            string[] attributes = {
                "modified", "created", "access"
            };


            for(uint i = 0; i < attributes.length; i++)
                if(attributes[i] == current.date_field)
                    date_row.selected = i;

            after.text = date_text(current.after);
            before.text = date_text(current.before);



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
            tag.text = current.tag;
            owner.text = current.owner;

            favorites.active = current.favorites_only;

            clear.clicked.connect(() => { var query = new SearchQuery();
                                          query.text = current.text;
                                          applied(query);
                                          close();
                });

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
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                dispose_template(typeof(SearchFilters));
            }
            base.dispose();
        }
    }
}
