namespace MajorisFiles {
    public class LocationSuggestions : Object {
        MetadataStore metadata;
        public LocationSuggestions(MetadataStore metadata)
        {
            this.metadata = metadata;
        }
        public Gee.ArrayList<File> history()
        {
            var result = new Gee.ArrayList<File>();
            try {
                var saved = Variant.parse(new VariantType("as"), metadata.state("location-history", "@as []"));
                for(size_t i = 0; i < size_t.min(saved.n_children(), 25); i++)
                {
                    string uri = saved.get_child_value(i).get_string();
                    if(Uri.parse_scheme(uri) != null)
                        result.add(File.new_for_uri(uri));
                }
            }
            catch(Error ignored) {}
            return result;
        }
        public void remember(File file)
        {
            if(file.has_uri_scheme("majoris") || file.has_uri_scheme("recent") || file.has_uri_scheme("trash"))
                return;
            try {
                // Credential-bearing locations belong to the platform credential store.
                if(Uri.parse(file.get_uri(), UriFlags.NONE).get_userinfo() != null)
                    return;
            }
            catch(Error e) {
                return;
            }
            var saved = new VariantBuilder(new VariantType("as"));
            saved.add("s", file.get_uri());
            uint count = 1;
            foreach(var previous in history())
            {
                if(!previous.equal(file) && count < 25)
                {
                    saved.add("s", previous.get_uri());
                    count++;
                }
            }
            metadata.set_state("location-history", saved.end().print(true));
        }
        public async Gee.ArrayList<File> suggest(string text, File base_folder, Cancellable token) throws Error
        {
            var result = new Gee.ArrayList<File>();
            var seen = new Gee.HashSet<string>();
            string needle = text.casefold();
            foreach(var file in history())
                if((text == "" || file.get_parse_name().casefold().has_prefix(needle) || file.get_uri().casefold().has_prefix(needle)) && seen.add(file.get_uri()))
                    result.add(file);
            if(text == "")
                return result;
            var typed = Uri.parse_scheme(text) != null || Path.is_absolute(text) || text.has_prefix("~") ? Paths.parse(text) : base_folder.resolve_relative_path(text);
            File? folder = text.has_suffix("/") ? typed : typed.get_parent();
            string prefix = text.has_suffix("/") ? "" : typed.get_basename() ?? "";
            if(folder == null || folder.has_uri_scheme("majoris"))
                return result;
            FileEnumerator? enumerator = null;
            var matching = new Gee.ArrayList<File>();
            try {
                enumerator = yield folder.enumerate_children_async("standard::name,standard::type,standard::is-hidden,standard::is-symlink", FileQueryInfoFlags.NONE, Priority.LOW, token);
                uint scanned = 0;
                while(scanned < 4096)
                {
                    var batch = yield enumerator.next_files_async(128, Priority.LOW, token);
                    if(batch == null)
                        break;
                    foreach(var info in batch)
                    {
                        token.set_error_if_cancelled();
                        scanned++;
                        if(info.get_file_type() == FileType.DIRECTORY && info.get_name().casefold().has_prefix(prefix.casefold()) && (!Paths.is_hidden(info) || prefix.has_prefix(".")))
                            matching.add(folder.get_child(info.get_name()));
                    }
                }
            }
            catch(Error e) {
                if(enumerator != null)
                {
                    try {
                        yield enumerator.close_async(Priority.LOW, null);
                    }
                    catch(Error ignored) {}
                    enumerator = null;
                }
                if(e is IOError.CANCELLED)
                    throw e;
            }
            if(enumerator != null)
                yield enumerator.close_async(Priority.LOW, null);
            token.set_error_if_cancelled();
            matching.sort((a, b) => Paths.natural_compare(a.get_basename(), b.get_basename()));
            foreach(var file in matching)
            {
                if(result.size >= 25)
                    break;
                if(seen.add(file.get_uri()))
                    result.add(file);
            }
            return result;
        }
    }
}
