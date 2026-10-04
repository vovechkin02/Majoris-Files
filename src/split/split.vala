namespace MajorisFiles {
    public class SplitService : Object {
        const size_t BUFFER = 1024 * 1024;
        static void require_member(Json.Object object, string name, Json.NodeType kind, Type type = Type.INVALID) throws Error
        {
            var node = object.get_member(name);
            if (node == null || node.get_node_type() != kind || (kind == Json.NodeType.VALUE && node.get_value_type() != type))
                throw new FileError.INVALID("Invalid manifest field: " + name);
        }
        public static void validate_manifest(Json.Object object) throws Error
        {
            foreach(var key in new string[] {"format", "original_filename", "sha256"})
                require_member(object, key, Json.NodeType.VALUE, typeof(string));
            foreach(var key in new string[] {"version", "original_size"})
                require_member(object, key, Json.NodeType.VALUE, typeof(int64));
            require_member(object, "parts", Json.NodeType.ARRAY);
            if(object.get_string_member("format") != "majoris-split-file" || object.get_int_member("version") != 1 || !Paths.valid_name(object.get_string_member("original_filename")) || object.get_int_member("original_size") <= 0 || !Regex.match_simple("^[a-fA-F0-9]{64}$", object.get_string_member("sha256")))
                throw new FileError.INVALID("Invalid manifest header");
            var parts = object.get_array_member("parts");
            if(parts.get_length() == 0 || parts.get_length() > 100000)
                throw new FileError.INVALID("Invalid part count");
            uint64 sum = 0;
            for(uint i = 0; i < parts.get_length(); i++)
            {
                var node = parts.get_element(i);
                if(node.get_node_type() != Json.NodeType.OBJECT)
                    throw new FileError.INVALID("Invalid part");
                var part = node.get_object();
                require_member(part, "filename", Json.NodeType.VALUE, typeof(string));
                require_member(part, "sha256", Json.NodeType.VALUE, typeof(string));
                require_member(part, "size", Json.NodeType.VALUE, typeof(int64));
                int64 size = part.get_int_member("size");
                if(size <= 0 || part.get_string_member("filename") != Paths.part_name(object.get_string_member("original_filename"), i + 1) || !Regex.match_simple("^[a-fA-F0-9]{64}$", part.get_string_member("sha256")) || (uint64)size > (uint64)object.get_int_member("original_size") - sum)
                    throw new FileError.INVALID("Invalid part order, size, or checksum");
                sum += (uint64)size;
            }
            if(sum != object.get_int_member("original_size"))
                throw new FileError.INVALID("Part sizes do not match original size");
        }
        public static async string checksum(File file, ChecksumType type, Cancellable token) throws Error
        {
            var input = yield file.read_async(Priority.LOW, token);
            var hash = new Checksum(type);
            uint8[] buffer = new uint8[BUFFER];
            while (true)
            {
                ssize_t count = yield input.read_async(buffer, Priority.LOW, token);
                if (count == 0)
                    break;
                hash.update(buffer, count);
            }
            yield input.close_async(Priority.LOW, null);
            return hash.get_string().dup();
        }
        public static async void split(File source, File destination, uint64 piece_size, Job job) throws Error
        {
            if (piece_size == 0)
                throw new FileError.INVALID("Part size must be positive");
            var info = yield source.query_info_async("standard::size,standard::type,etag::value", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
            if (info.get_file_type() != FileType.REGULAR || info.get_size() == 0)
                throw new FileError.INVALID("Select a nonempty regular file");
            var input = yield source.read_async(Priority.LOW, job.cancellable);
            var full = new Checksum(ChecksumType.SHA256);
            var created = new Gee.ArrayList<File>();
            var builder = new Json.Builder();
            uint64 total = 0;
            builder.begin_object();
            builder.set_member_name("format");
            builder.add_string_value("majoris-split-file");
            builder.set_member_name("version");
            builder.add_int_value(1);
            builder.set_member_name("original_filename");
            builder.add_string_value(source.get_basename());
            builder.set_member_name("original_size");
            builder.add_int_value(info.get_size());
            builder.set_member_name("parts");
            builder.begin_array();
            try {
                uint index = 1;
                uint8[] buffer = new uint8[BUFFER];
                while (total < info.get_size())
                {
                    var file = destination.get_child(Paths.part_name(source.get_basename(), index++));
                    var output = yield file.create_async(FileCreateFlags.PRIVATE, Priority.LOW, job.cancellable);
                    created.add(file);
                    uint64 size = 0;
                    var hash = new Checksum(ChecksumType.SHA256);
                    while (size < piece_size && total < info.get_size())
                    {
                        size_t requested = (size_t) uint64.min(uint64.min(BUFFER, piece_size - size),(uint64)info.get_size()-total);
                        ssize_t count = yield input.read_async(buffer[0 : requested], Priority.LOW, job.cancellable);
                        if (count == 0)
                            throw new FileError.INTEGRITY("Source changed while splitting");
                        size_t written;
                        yield output.write_all_async(buffer[0 : count], Priority.LOW, job.cancellable, out written);
                        hash.update(buffer, count);
                        full.update(buffer, count);
                        size += count;
                        total += count;
                        job.progress = (double)total / info.get_size();
                        job.current = file.get_basename();
                    }
                    yield output.close_async(Priority.LOW, job.cancellable);
                    builder.begin_object();
                    builder.set_member_name("filename");
                    builder.add_string_value(file.get_basename());
                    builder.set_member_name("size");
                    builder.add_int_value((int64)size);
                    builder.set_member_name("sha256");
                    builder.add_string_value(hash.get_string());
                    builder.end_object();
                }
                var updated=yield source.query_info_async("standard::size,etag::value",FileQueryInfoFlags.NONE,Priority.LOW,job.cancellable);
                if(updated.get_size()!=info.get_size() || (info.get_etag()!=null && info.get_etag()!=updated.get_etag())) throw new FileError.INTEGRITY("Source changed while splitting");
                builder.end_array();
                builder.set_member_name("sha256");
                builder.add_string_value(full.get_string());
                builder.end_object();
                var generator = new Json.Generator();
                generator.set_root(builder.get_root());
                var manifest = destination.get_child(source.get_basename() + ".parts.json");
                var output = yield manifest.create_async(FileCreateFlags.PRIVATE, Priority.LOW, job.cancellable);
                created.add(manifest);
                size_t written;
                yield output.write_all_async(generator.to_data(null).data, Priority.LOW, job.cancellable, out written);
                yield output.close_async(Priority.LOW, null);
            }
            catch (Error e) {
                foreach (var file in created)
                {
                    try {
                        yield file.delete_async(Priority.LOW, null);
                    }
                    catch (Error cleanup) {}
                }
                throw e;
            }
            finally {
                try {
                    yield input.close_async(Priority.LOW, null);
                }
                catch (Error e) {}
            }
        }
        public static async void join(File manifest, File destination, Job job) throws Error
        {
            var mi = yield manifest.query_info_async("standard::size", FileQueryInfoFlags.NONE, Priority.DEFAULT, job.cancellable);
            if (mi.get_size() > 16 * 1024 * 1024)
                throw new FileError.INVALID("Manifest is too large");
            uint8[] data;
            yield manifest.load_contents_async(job.cancellable, out data, null);
            var parser = new Json.Parser();
            parser.load_from_data((string)data, data.length);
            var root = parser.get_root();
            if (root.get_node_type() != Json.NodeType.OBJECT)
                throw new FileError.INVALID("Invalid manifest");
            var object = root.get_object();
            validate_manifest(object);
            foreach (var key in new string[] {"format", "version", "original_filename", "original_size", "sha256", "parts"})
                if (!object.has_member(key))
                    throw new FileError.INVALID("Incomplete manifest");
            if (object.get_string_member("format") != "majoris-split-file" || object.get_int_member("version") != 1)
                throw new FileError.INVALID("Unsupported manifest");
            string name = object.get_string_member("original_filename");
            if (!Paths.valid_name(name))
                throw new FileError.INVALID("Unsafe output name");
            int64 expected = object.get_int_member("original_size");
            if (expected <= 0)
                throw new FileError.INVALID("Invalid size");
            var parts = object.get_array_member("parts");
            if (parts.get_length() == 0 || parts.get_length() > 100000)
                throw new FileError.INVALID("Invalid parts");
            uint64 sum = 0;
            for (uint i = 0; i < parts.get_length(); i++)
            {
                var part = parts.get_object_element(i);
                foreach (var key in new string[] {"filename", "size", "sha256"})
                    if (!part.has_member(key))
                        throw new FileError.INVALID("Incomplete part");
                if (part.get_string_member("filename") != Paths.part_name(name, i + 1) || part.get_int_member("size") <= 0)
                    throw new FileError.INVALID("Invalid part order or size");
                var info = yield manifest.get_parent().get_child(part.get_string_member("filename")).query_info_async("standard::size,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                if (info.get_file_type() != FileType.REGULAR || info.get_size() != part.get_int_member("size"))
                    throw new FileError.INTEGRITY("Missing or altered part");
                sum += info.get_size();
            }
            if (sum != expected)
                throw new FileError.INTEGRITY("Part sizes do not match original size");
            var space = yield destination.query_filesystem_info_async("filesystem::free", Priority.DEFAULT, job.cancellable);
            if (space.has_attribute("filesystem::free") && space.get_attribute_uint64("filesystem::free") < sum)
                throw new FileError.INVALID("Insufficient free space");
            var temp = destination.get_child(".majoris-join-" + Uuid.string_random());
            var output = yield temp.create_async(FileCreateFlags.PRIVATE, Priority.LOW, job.cancellable);
            try {
                uint8[] buffer = new uint8[BUFFER];
                var full = new Checksum(ChecksumType.SHA256);
                uint64 total = 0;
                for (uint i = 0; i < parts.get_length(); i++)
                {
                    var part = parts.get_object_element(i);
                    var file = manifest.get_parent().get_child(part.get_string_member("filename"));
                    var input = yield file.read_async(Priority.LOW, job.cancellable);
                    var hash = new Checksum(ChecksumType.SHA256);
                    while (true)
                    {
                        ssize_t count = yield input.read_async(buffer, Priority.LOW, job.cancellable);
                        if (count == 0)
                            break;
                        size_t written;
                        yield output.write_all_async(buffer[0 : count], Priority.LOW, job.cancellable, out written);
                        hash.update(buffer, count);
                        full.update(buffer, count);
                        total += count;
                        job.progress = (double)total / sum;
                    }
                    yield input.close_async(Priority.LOW, null);
                    if (hash.get_string() != part.get_string_member("sha256"))
                        throw new FileError.INTEGRITY("Part checksum mismatch");
                }
                if (full.get_string() != object.get_string_member("sha256"))
                    throw new FileError.INTEGRITY("Original checksum mismatch");
                yield output.close_async(Priority.LOW, job.cancellable);
                yield temp.move_async(destination.get_child(name), FileCopyFlags.NONE, Priority.LOW, job.cancellable, null);
            }
            catch (Error e) {
                try {
                    yield output.close_async(Priority.LOW, null);
                    yield temp.delete_async(Priority.LOW, null);
                }
                catch (Error cleanup) {}
                throw e;
            }
        }
    }
}
