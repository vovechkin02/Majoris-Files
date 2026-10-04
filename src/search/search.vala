namespace MajorisFiles {
    public class SearchQuery : Object {
        public string text = "";
        public string mime = "";
        public uint64 minimum;
        public uint64 maximum = uint64.MAX;
        public string kind = "Any";
        public string date_field = "modified";
        public uint64 after;
        public uint64 before = uint64.MAX;
        public string tag = "";
        public bool favorites_only;
        public string owner = "";
        public bool active { get { return text != "" || mime != "" || kind != "Any" || minimum != 0 || maximum != uint64.MAX || after != 0 || before != uint64.MAX || tag != "" || favorites_only || owner != ""; } }
        public bool matches(FileItem item, MetadataStore? metadata = null)
        {
            if(!item.name.casefold().contains(text.casefold()) || item.bytes < minimum || item.bytes > maximum) return false;
            if(mime != "" && !ContentType.is_a(item.mime, mime)) return false;
            if(kind == "Folder" && !item.directory) return false;
            if(kind == "Image" && !item.mime.has_prefix("image/")) return false;
            if(kind == "Video" && !item.mime.has_prefix("video/")) return false;
            if(kind == "Audio" && !item.mime.has_prefix("audio/")) return false;
            if(kind == "Text" && !ContentType.is_a(item.mime, "text/plain")) return false;
            if(kind == "PDF" && item.mime != "application/pdf") return false;
            if(kind == "Document" && !(item.mime.contains("wordprocessing") || item.mime.contains("opendocument.text") || item.mime == "application/msword" || item.mime == "application/pdf")) return false;
            if(kind == "Spreadsheet" && !(item.mime.contains("spreadsheet") || item.mime.contains("excel") || item.mime == "text/csv")) return false;
            if(kind == "Archive" && !(item.mime.contains("zip") || item.mime.contains("tar") || item.mime.contains("compressed") || item.mime.contains("7z") || item.mime.contains("rar"))) return false;
            if(after != 0 || before != uint64.MAX) {
                string attribute = "time::" + date_field;
                if(!item.info.has_attribute(attribute)) return false;
                uint64 time = item.info.get_attribute_uint64(attribute);
                if(time < after || time > before) return false;
            }
            if(owner != "" && item.info.get_attribute_string("owner::user") != owner) return false;
            if(favorites_only && (metadata == null || !metadata.favorite(item.file))) return false;
            if(tag != "") {
                if(metadata == null) return false;
                bool tagged = false;
                foreach(var stored in metadata.tags(item.file).split(","))
                    if(stored.strip().casefold() == tag.strip().casefold()) tagged = true;
                if(!tagged) return false;
            }
            return true;
        }
        public string serialize() {
            return "majoris-search-v1:" + new Variant("(ssttssttbs)", text, mime, minimum, maximum, kind, date_field, after, before, favorites_only, tag + "\n" + owner).print(true);
        }
        public static SearchQuery deserialize(string saved) throws Error {
            var result = new SearchQuery();
            if(!saved.has_prefix("majoris-search-v1:")) { result.text = saved; return result; }
            var value = Variant.parse(new VariantType("(ssttssttbs)"), saved.substring(18));
            result.text = value.get_child_value(0).get_string();
            result.mime = value.get_child_value(1).get_string();
            result.minimum = value.get_child_value(2).get_uint64();
            result.maximum = value.get_child_value(3).get_uint64();
            result.kind = value.get_child_value(4).get_string();
            result.date_field = value.get_child_value(5).get_string();
            result.after = value.get_child_value(6).get_uint64();
            result.before = value.get_child_value(7).get_uint64();
            result.favorites_only = value.get_child_value(8).get_boolean();
            var extra = value.get_child_value(9).get_string().split("\n", 2);
            result.tag = extra[0]; result.owner = extra.length > 1 ? extra[1] : "";
            if(result.minimum > result.maximum || result.after > result.before || !(result.date_field in new string[]{"modified", "created", "access"}))
                throw new FileError.INVALID("Invalid saved search range");
            return result;
        }
    }
    public class SearchController : Object {
        public Cancellable cancellable = new Cancellable();
        public signal void found(FileItem item);
        public async void search(File root, SearchQuery query, MetadataStore? metadata = null) throws Error
        {
            cancellable.cancel();
            cancellable = new Cancellable();
            var token = cancellable;
            var queue = new Gee.ArrayQueue<File>();
            queue.offer(root);
            while (!queue.is_empty && !token.is_cancelled())
            {
                var folder = queue.poll();
                FileEnumerator enumerator;
                try {
                    enumerator = yield folder.enumerate_children_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                }
                catch (IOError.CANCELLED e) {
                    throw e;
                }
                catch (Error e) {
                    continue;
                }
                while (true)
                {
                    var batch = yield enumerator.next_files_async(128, Priority.LOW, token);
                    if (batch == null)
                        break;
                    foreach (var info in batch)
                    {
                        var item = new FileItem(folder.get_child(info.get_name()), info);
                        if (query.matches(item, metadata))
                            found(item);
                        if (item.directory && !info.get_is_symlink() && !info.get_is_hidden())
                            queue.offer(item.file);
                    }
                }
                yield enumerator.close_async(Priority.LOW, null);
            }
        }
    }
}
