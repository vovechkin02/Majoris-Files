namespace MajorisFiles {
    public class ChooserFilter : Object {
        public string name;
        public Variant serialized;
        public Gee.ArrayList<string> patterns = new Gee.ArrayList<string>();
        public Gee.ArrayList<string> mimes = new Gee.ArrayList<string>();
        public ChooserFilter(Variant value) throws Error
        {
            if (!value.is_of_type(new VariantType("(sa(us))")))
                throw new FileError.INVALID("Invalid filter");
            serialized = value;
            name = value.get_child_value(0).get_string();
            if(name.length > 4096)
                throw new FileError.INVALID("Filter name is too long");
            var rules = value.get_child_value(1);
            if (rules.n_children() > 256)
                throw new FileError.INVALID("Too many filter rules");
            for (size_t i = 0; i < rules.n_children(); i++)
            {
                var rule = rules.get_child_value(i);
                uint kind = rule.get_child_value(0).get_uint32();
                var text = rule.get_child_value(1).get_string();
                if(text.length > 4096)
                    throw new FileError.INVALID("Filter rule is too long");
                if (kind == 0)
                    patterns.add(text);
                else if (kind == 1)
                    mimes.add(text);
                else throw new FileError.INVALID("Unknown filter rule");
            }
        }
        public bool matches(FileItem item)
        {
            if (item.navigable)
                return true;
            foreach (var pattern in patterns)
                if (PatternSpec.match_simple(pattern, item.info.get_name()))
                    return true;
            foreach (var mime in mimes)
                if (ContentType.is_a(item.mime, mime))
                    return true;
            return patterns.size == 0 && mimes.size == 0;
        }
        public string filename(string input)
        {
            // An explicit suffix is preserved. Only simple application-supplied extensions are inferred.
            if (input.last_index_of(".") > 0)
                return input;
            foreach (var pattern in patterns)
                if (pattern.has_prefix("*.") && !pattern.substring(2).contains("*") && !pattern.contains("?") && !pattern.contains("[") && !pattern.contains("/"))
                    return input + pattern.substring(1);
            return input;
        }
    }
    public class ChooserOptions : Object {
        public bool save;
        public bool multiple;
        public bool directory;
        public bool modal = true;
        public bool initial_provided;
        public string current_name = "";
        public File initial = File.new_for_path(Environment.get_home_dir());
        public File? current_file;
        public string accept_label = "";
        public Gee.ArrayList<ChooserFilter> filters = new Gee.ArrayList<ChooserFilter>();
        public uint selected_filter;
        public Variant? choices;
        public ChooserOptions(bool save, Variant options) throws Error
        {
            this.save = save;
            if (!options.is_of_type(VariantType.VARDICT))
                throw new FileError.INVALID("Options must be a dictionary");
            multiple = boolean(options, "multiple", false) && !save;
            directory = boolean(options, "directory", false) && !save;
            modal = boolean(options, "modal", true);
            current_name = text(options, "current_name", "");
            accept_label = text(options, "accept_label", "");
            var folder = bytes_path(options, "current_folder");
            initial_provided = folder != null;
            if (folder != null)
                initial = File.new_for_path(folder);
            var file = bytes_path(options, "current_file");
            if (file != null)
            {
                initial_provided = true;
                current_file = File.new_for_path(file);
                initial = current_file.get_parent() ?? initial;
                current_name = current_file.get_basename();
            }
            var value = typed(options, "filters", "a(sa(us))");
            if (value != null)
            {
                if (value.n_children() > 64)
                    throw new FileError.INVALID("Too many filters");
                for (size_t i = 0; i < value.n_children(); i++)
                    filters.add(new ChooserFilter(value.get_child_value(i)));
            }
            var current = typed(options, "current_filter", "(sa(us))");
            if (current != null)
            {
                var filter = new ChooserFilter(current);
                bool found = false;
                for (int i = 0; i < filters.size; i++)
                    if (filters[i].serialized.equal(current))
                    {
                        selected_filter = i;
                        found = true;
                    }
                if (!found)
                {
                    filters.add(filter);
                    selected_filter = filters.size - 1;
                }
            }
            choices = typed(options, "choices", "a(ssa(ss)s)");
            if (choices != null && choices.n_children() > 64)
                throw new FileError.INVALID("Too many choices");
            if(choices != null)
            {
                var ids = new Gee.HashSet<string>();
                for(size_t i = 0; i < choices.n_children(); i++)
                {
                    var choice = choices.get_child_value(i);
                    string id = choice.get_child_value(0).get_string();
                    var values = choice.get_child_value(2);
                    if(id.length == 0 || id.length > 256 || !ids.add(id) || choice.get_child_value(1).get_string().length > 4096 || values.n_children() > 256)
                        throw new FileError.INVALID("Invalid caller choice");
                    var value_ids = new Gee.HashSet<string>();
                    for(size_t j = 0; j < values.n_children(); j++)
                    {
                        var pair = values.get_child_value(j);
                        string choice_value = pair.get_child_value(0).get_string();
                        if(choice_value.length == 0 || choice_value.length > 256 || !value_ids.add(choice_value) || pair.get_child_value(1).get_string().length > 4096)
                            throw new FileError.INVALID("Invalid choice value");
                    }
                }
            }
        }
        public static Variant? typed(Variant options, string key, string signature) throws Error
        {
            var v = options.lookup_value(key, null);
            if (v != null && !v.is_of_type(new VariantType(signature)))
                throw new FileError.INVALID("Invalid option: " + key);
            return v;
        }
        static bool boolean(Variant options, string key, bool fallback) throws Error
        {
            var v = typed(options, key, "b");
            return v == null ? fallback : v.get_boolean();
        }
        static string text(Variant options, string key, string fallback) throws Error
        {
            var v = typed(options, key, "s");
            return v == null ? fallback : v.get_string();
        }
        static string? bytes_path(Variant options, string key) throws Error
        {
            var v = typed(options, key, "ay");
            if (v == null)
                return null;
            if (v.n_children() == 0 || v.n_children() > 65536 || v.get_child_value(v.n_children() - 1).get_byte() != 0)
                throw new FileError.INVALID("Path must be NUL terminated");
            var result = new StringBuilder();
            for (size_t i = 0; i + 1 < v.n_children(); i++)
            {
                uint8 b = v.get_child_value(i).get_byte();
                if (b == 0)
                    throw new FileError.INVALID("Embedded NUL in path");
                result.append_c((char)b);
            }
            if (!Path.is_absolute(result.str))
                throw new FileError.INVALID("Path must be absolute");
            return result.str;
        }
        public static Variant response(string[] uris, ChooserFilter? filter = null, Variant? choices = null) throws Error
        {
            foreach (var uri in uris)
                if (!uri.has_prefix("file:///"))
                    throw new FileError.INVALID("Portal results must be file URIs");
            var result = new VariantBuilder(VariantType.VARDICT);
            result.add("{sv}", "uris", new Variant.strv(uris));
            if (filter != null)
                result.add("{sv}", "current_filter", filter.serialized);
            if (choices != null)
                result.add("{sv}", "choices", choices);
            return result.end();
        }
    }
}
