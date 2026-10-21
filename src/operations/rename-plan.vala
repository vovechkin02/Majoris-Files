namespace MajorisFiles {
    public class RenamePlan : Object {
        public static string name(FileItem item, uint mode, string pattern, string replacement, int number, int digits, Gee.Map<string, string>? metadata = null) throws Error
        {
            string original = item.file.get_basename();
            int dot = original.last_index_of(".");
            if (item.directory || dot <= 0) dot = original.length;
            string stem = original.substring(0, dot), extension = original.substring(dot);
            string result;
            if (mode == 0) {
                if (pattern == "") throw new FileError.INVALID("Enter text to find");
                result = original.replace(pattern, replacement);
            }
            else if (mode == 1) result = pattern + original;
            else if (mode == 2) result = stem + pattern + extension;
            else if (mode == 4) result = pattern + "%0*d".printf(digits.clamp(1, 12), number) + extension;
            else {
                var values = new Gee.HashMap<string, string>();
                values["original"] = original; values["stem"] = stem; values["extension"] = extension;
                values["counter"] = "%0*d".printf(digits.clamp(1, 12), number);
                var modified = item.info.get_modification_date_time();
                var created = item.info.get_creation_date_time();
                if (modified != null) { values["modified"] = modified.format("%Y-%m-%d"); values["date"] = values["modified"]; }
                if (created != null) values["created"] = created.format("%Y-%m-%d");
                if (metadata != null) {
                    string[] keys = {"camera", "artist", "album", "track", "title", "season", "episode"};
                    string[] labels = {"Camera Model", "Artist", "Album", "Track", "Title", "Season", "Episode"};
                    for (int i = 0; i < keys.length; i++) if (metadata.has_key(labels[i])) values[keys[i]] = metadata[labels[i]];
                }
                var placeholders = new Regex("\\{([a-z_]+)\\}");
                MatchInfo match;
                placeholders.match(pattern, 0, out match);
                while (match.matches()) {
                    string key = match.fetch(1);
                    if (!values.has_key(key) || values[key] == "") throw new FileError.INVALID("Missing or unknown metadata: {" + key + "}");
                    if (!match.next()) break;
                }
                result = placeholders.replace_eval(pattern, -1, 0, 0, (info, output) => { output.append(values[info.fetch(1)]); return false; });
            }
            if (!Paths.valid_name(result)) throw new FileError.INVALID("The result is not a valid filename");
            return result;
        }
    }
}
