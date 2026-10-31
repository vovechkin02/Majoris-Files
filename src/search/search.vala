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
        string tag_name = "";
        public int64 tag_id;
        public string tag { get { return tag_name; } set { if (tag_name != value) { tag_name = value; tag_id = 0; } } }
        public void resolve_tag(MetadataStore metadata) {
            if (tag_name == "") { tag_id = 0; return; }
            if (tag_id == 0) {
                var definition = metadata.tag_by_name(tag_name.strip());
                if (definition == null) foreach (var candidate in metadata.tag_definitions()) if (candidate.name.casefold() == tag_name.strip().casefold()) { definition = candidate; break; }
                if (definition == null) definition = metadata.tag_at(File.new_for_uri("majoris:///tag/" + Uri.escape_string(tag_name.strip())));
                if (definition != null) tag_id = definition.id;
            }
            var current = metadata.tag_by_id(tag_id); if (current != null) tag_name = current.name;
        }
        public bool favorites_only;
        public string owner = "";
        public string content = "";
        public string scope = "folder";
        public bool active {
            get {
                return text != "" || content != "" || mime != "" || kind != "Any" || minimum != 0 || maximum != uint64.MAX || after != 0 || before != uint64.MAX || tag != "" || favorites_only || owner != "";
            }
        }
        public bool matches(FileItem item, MetadataStore? metadata = null)
        {
            if(!item.name.casefold().contains(text.casefold()) || item.bytes < minimum || item.bytes > maximum)
                return false;
            if(mime != "" && !ContentType.is_a(item.mime, mime))
                return false;
            if(kind == "Folder" && !item.directory)
                return false;
            if(kind == "Image" && !item.mime.has_prefix("image/"))
                return false;
            if(kind == "Video" && !item.mime.has_prefix("video/"))
                return false;
            if(kind == "Audio" && !item.mime.has_prefix("audio/"))
                return false;
            if(kind == "Text" && !ContentType.is_a(item.mime, "text/plain"))
                return false;
            if(kind == "PDF" && item.mime != "application/pdf")
                return false;
            if(kind == "Document" && !(item.mime.contains("wordprocessing") || item.mime.contains("opendocument.text") || item.mime == "application/msword" || item.mime == "application/pdf"))
                return false;
            if(kind == "Spreadsheet" && !(item.mime.contains("spreadsheet") || item.mime.contains("excel") || item.mime == "text/csv"))
                return false;
            if(kind == "Archive" && !(item.mime.contains("zip") || item.mime.contains("tar") || item.mime.contains("compressed") || item.mime.contains("7z") || item.mime.contains("rar")))
                return false;
            if(after != 0 || before != uint64.MAX)
            {
                string attribute = "time::" + date_field;
                if(!item.info.has_attribute(attribute))
                    return false;
                uint64 time = item.info.get_attribute_uint64(attribute);
                if(time < after || time > before)
                    return false;
            }
            if(owner != "" && item.info.get_attribute_string("owner::user") != owner)
                return false;
            if(favorites_only && (metadata == null || !metadata.favorite(item.file)))
                return false;
            if(tag != "")
            {
                if(metadata == null)
                    return false;
                resolve_tag(metadata);
                if (tag_id == 0 || !metadata.has_tag(item.file, tag_id)) return false;
            }
            return true;
        }
        public string serialize()
        {
            return "majoris-search-v4:" + new Variant("(ssttssttbssssx)", text, mime, minimum, maximum, kind, date_field, after, before, favorites_only, tag, owner, content, scope, tag_id).print(true);
        }
        public static SearchQuery deserialize(string saved) throws Error
        {
            var result = new SearchQuery();
            bool version_two = saved.has_prefix("majoris-search-v2:");
            bool version_four = saved.has_prefix("majoris-search-v4:");
            bool version_three = version_four || saved.has_prefix("majoris-search-v3:");
            if(!version_three && !version_two && !saved.has_prefix("majoris-search-v1:"))
            {
                result.text = saved;
                return result;
            }
            var value = Variant.parse(new VariantType(version_four ? "(ssttssttbssssx)" : version_three ? "(ssttssttbssss)" : version_two ? "(ssttssttbss)" : "(ssttssttbs)"), saved.substring(18));
            result.text = value.get_child_value(0).get_string();
            result.mime = value.get_child_value(1).get_string();
            result.minimum = value.get_child_value(2).get_uint64();
            result.maximum = value.get_child_value(3).get_uint64();
            result.kind = value.get_child_value(4).get_string();
            result.date_field = value.get_child_value(5).get_string();
            result.after = value.get_child_value(6).get_uint64();
            result.before = value.get_child_value(7).get_uint64();
            result.favorites_only = value.get_child_value(8).get_boolean();
            var extra = value.get_child_value(9).get_string().split("\n", 3);
            result.tag = version_three ? value.get_child_value(9).get_string() : extra[0];
            result.owner = version_three ? value.get_child_value(10).get_string() : extra.length > 1 ? extra[1] : "";
            result.content = version_three ? value.get_child_value(11).get_string() : extra.length > 2 ? extra[2] : "";
            result.scope = version_three ? value.get_child_value(12).get_string() : version_two ? value.get_child_value(10).get_string() : "recursive";
            if (version_four) result.tag_id = value.get_child_value(13).get_int64();
            if(!(result.scope in new string[] {"folder", "recursive", "everywhere"}))
                throw new FileError.INVALID("Invalid saved search scope");
            if(result.minimum > result.maximum || result.after > result.before || !(result.date_field in new string[] {"modified", "created", "access"}))
                throw new FileError.INVALID("Invalid saved search range");
            return result;
        }
    }
    public class SearchController : Object {
        public Cancellable cancellable = new Cancellable();
        public SearchProvider indexed = new IndexedSearchProvider();
        public bool exhaustive { get; set; default = false; }
        public string backend_status { get; private set; default = ""; }
        public signal void found(FileItem item);
        public uint unreadable {
            get;
            private set;
        }
        public uint scanned {
            get;
            private set;
        }
        public signal void progress(uint folders, uint skipped);
        public async void search(File root, SearchQuery query, MetadataStore? metadata = null, bool recursive = true) throws Error
        {
            var roots = new Gee.ArrayList<File>();
            roots.add(root);
            yield search_roots(roots, query, metadata, recursive);
        }
        public async void search_roots(Gee.List<File> roots, SearchQuery query, MetadataStore? metadata = null, bool recursive = true) throws Error
        {
            cancellable.cancel();
            cancellable = new Cancellable();
            var token = cancellable;
            // The caller can edit its query while this asynchronous scan is running.
            var criteria = SearchQuery.deserialize(query.serialize());
            unreadable = 0;
            scanned = 0;
            var queue = new Gee.ArrayQueue<File>();
            var visited = new Gee.HashSet<string>();
            var emitted = new Gee.HashSet<string>();
            var covered = new Gee.HashSet<string>();
            backend_status = "Filesystem scan";
            if (metadata == null || metadata.state("indexed-search", "true") == "true") {
                var index_token = new Cancellable();
                ulong cancel = token.cancelled.connect(() => index_token.cancel());
                uint timeout = Timeout.add_seconds(10, () => { index_token.cancel(); return Source.REMOVE; });
                // A separate one-shot flag avoids removing an already-expired source.
                Source? timer = MainContext.default().find_source_by_id(timeout);
                ulong handler = indexed.hit.connect((item) => {
                    if (!token.is_cancelled() && criteria.matches(item, metadata) && emitted.add(item.file.get_uri())) found(item);
                });
                try {
                    yield indexed.search(roots, criteria, recursive, index_token);
                    if (!exhaustive && (metadata == null || metadata.state("exhaustive-search", "false") != "true") && indexed is CoveredSearchProvider) {
                        foreach (var root in roots)
                            if (yield ((CoveredSearchProvider)indexed).covers(root, criteria, recursive, index_token)) covered.add(root.get_uri());
                    }
                    backend_status = covered.size == roots.size ? "Indexed locations; updates can lag the filesystem" : "Indexed results; scanning uncovered locations";
                }
                catch (Error e) {
                    token.set_error_if_cancelled();
                    covered.clear();
                    backend_status = "Index unavailable; searching the filesystem";
                }
                finally {
                    indexed.disconnect(handler);
                    token.disconnect(cancel);
                    if (timer != null && !timer.is_destroyed()) Source.remove(timeout);
                }
            }
            foreach(var root in roots)
                if(!covered.contains(root.get_uri()) && visited.add(root.get_uri()))
                    queue.offer(root);
            while (!queue.is_empty)
            {
                token.set_error_if_cancelled();
                var folder = queue.poll();
                FileEnumerator? enumerator = null;
                try {
                    enumerator = yield folder.enumerate_children_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                    while (true)
                    {
                        var batch = yield enumerator.next_files_async(128, Priority.LOW, token);
                        if (batch == null)
                            break;
                        foreach (var info in batch)
                        {
                            token.set_error_if_cancelled();
                            var item = new FileItem(folder.get_child(info.get_name()), info);
                            item.relevance = criteria.text == "" ? 0 : item.name.casefold() == criteria.text.casefold() ? 30 : item.name.casefold().has_prefix(criteria.text.casefold()) ? 20 : 10;
                            if (criteria.matches(item, metadata) && (criteria.content == "" || (yield content_matches(item, criteria.content, token))) && emitted.add(item.file.get_uri()))
                                found(item);
                            if (recursive && item.directory && !Paths.is_symlink(info) && !item.hidden && !covered.contains(item.file.get_uri()) && visited.add(item.file.get_uri()))
                                queue.offer(item.file);
                        }
                    }
                }
                catch (Error e) {
                    if(enumerator != null)
                    {
                        try {
                            yield enumerator.close_async(Priority.LOW, null);
                        }
                        catch(Error ignored) {}
                        enumerator = null;
                    }
                    if(e is IOError.CANCELLED || token.is_cancelled())
                        throw new IOError.CANCELLED("Search cancelled");
                    unreadable++;
                }
                if(enumerator != null)
                {
                    try {
                        yield enumerator.close_async(Priority.LOW, null);
                    }
                    catch(Error e) {
                        unreadable++;
                    }
                }
                token.set_error_if_cancelled();
                scanned++;
                progress(scanned, unreadable);
            }
            progress(scanned, unreadable);
        }
        static async bool content_matches(FileItem item, string needle, Cancellable token) throws Error
        {
            // Direct content search is deliberately bounded and never reads network files.
            if(!item.file.is_native() || item.info.get_file_type() != FileType.REGULAR || Paths.is_symlink(item.info) || item.bytes > 4 * 1024 * 1024 || !(item.mime.has_prefix("text/") || item.mime.contains("json") || item.mime.contains("xml")))
                return false;
            try {
                var stream = yield item.file.read_async(Priority.LOW, token);
                var bytes = new ByteArray();
                try {
                    uint8[] buffer = new uint8[65536];
                    while(bytes.len <= 4 * 1024 * 1024)
                    {
                        var count = yield stream.read_async(buffer, Priority.LOW, token);
                        if(count == 0)
                            break;
                        bytes.append(buffer[0:count]);
                    }
                }
                catch(Error e) {
                    try {
                        yield stream.close_async(Priority.LOW, null);
                    }
                    catch(Error ignored) {}
                    throw e;
                }
                yield stream.close_async(Priority.LOW, null);
                if(bytes.len > 4 * 1024 * 1024)
                    return false;
                bytes.append({0});
                token.set_error_if_cancelled();
                return ((string)bytes.data).make_valid().casefold().contains(needle.casefold());
            }
            catch(IOError.CANCELLED e) {
                throw e;
            }
            catch(Error e) {
                return false;
            }
        }
    }
}
