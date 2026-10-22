namespace MajorisFiles {
    public delegate void ImportProgress(uint64 transferred, uint64 total);
    public class ImportPolicy : Object {
        public uint64 maximum_bytes = 10UL * 1024 * 1024 * 1024;
        public uint timeout_seconds = 1800;
        public uint64 reserve_bytes = 32 * 1024 * 1024;
        public ImportPolicy(MetadataStore? metadata = null)
        {
            if (metadata != null)
            {
                uint64 gib = 10;
                uint minutes = 30;
                uint64.try_parse(metadata.state("remote-import-limit-gib", "10"), out gib);
                uint.try_parse(metadata.state("remote-import-timeout-minutes", "30"), out minutes);
                maximum_bytes = gib.clamp(1, 1024) * 1024 * 1024 * 1024;
                timeout_seconds = minutes.clamp(1, 1440) * 60;
            }
        }
    }
    // An explicitly approved, durable local copy. Never used for Save: there is
    // deliberately no implicit remote writeback or sandbox permission bypass.
    public class ChooserImport : Object {
        [CCode(cname = "getpid", cheader_filename = "unistd.h")]
        extern static int process_id();
        public static async void cleanup_abandoned(File root, Cancellable token) throws Error
        {
            var entries = yield root.enumerate_children_async("standard::name,standard::type,standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
            try {
                while (true)
                {
                    var batch = yield entries.next_files_async(128, Priority.LOW, token);
                    if (batch == null) break;
                    foreach (var entry in batch)
                    {
                        var parts = entry.get_name().split("-", 3);
                        int pid = 0;
                        if (parts.length != 3 || parts[0] != ".pending" || !int.try_parse(parts[1], out pid) || pid <= 0 ||
                            entry.get_file_type() != FileType.DIRECTORY || Paths.is_symlink(entry))
                            continue;
                        if (!FileUtils.test("/proc/" + pid.to_string(), FileTest.IS_DIR))
                            yield OperationManager.remove_tree(root.get_child(entry.get_name()), token);
                    }
                }
            }
            catch (Error e) {
                try { yield entries.close_async(Priority.LOW, null); } catch (Error ignored) {}
                throw e;
            }
            yield entries.close_async(Priority.LOW, null);
        }
        public static async File download(File source, Cancellable token, File? import_root = null, ImportPolicy? policy = null, ImportProgress? progress = null) throws Error
        {
            var limits = policy ?? new ImportPolicy();
            var info = yield source.query_info_async("standard::type,standard::size,standard::name,etag::value", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
            if (info.get_file_type() != FileType.REGULAR ||
                !info.has_attribute("standard::size") || info.get_size() < 0 || info.get_size() > limits.maximum_bytes)
                throw new FileError.UNSUPPORTED("The file exceeds the configured remote download limit, or its size is unavailable");
            string name = source.get_basename();
            if (!Paths.valid_name(name))
                throw new FileError.INVALID("Invalid imported filename");
            var root = import_root ?? File.new_for_path(Path.build_filename(Environment.get_user_data_dir(), "majoris-files", "imports"));
            if (!root.is_native())
                throw new FileError.INVALID("The import destination must be local");
            if (import_root == null)
                DirUtils.create_with_parents(root.get_path(), 0700);
            else
                try { yield root.make_directory_async(Priority.DEFAULT, token); } catch (IOError.EXISTS e) {}
            var root_info = yield root.query_info_async("standard::type,standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
            if (root_info.get_file_type() != FileType.DIRECTORY || Paths.is_symlink(root_info))
                throw new FileError.INVALID("The import destination must be a local directory");
            var filesystem = yield root.query_filesystem_info_async("filesystem::free", Priority.DEFAULT, token);
            if (!filesystem.has_attribute("filesystem::free") ||
                filesystem.get_attribute_uint64("filesystem::free") < (uint64)info.get_size() + limits.reserve_bytes)
                throw new FileError.INVALID("There is not enough verified local free space for this download");
            yield cleanup_abandoned(root, token);
            string identity = Uuid.string_random();
            var folder = root.get_child(".pending-" + process_id().to_string() + "-" + identity);
            yield folder.make_directory_async(Priority.DEFAULT, token);
            var target = folder.get_child(name);
            InputStream? input = null;
            OutputStream? output = null;
            var transfer = new Cancellable();
            ulong cancel = token.cancelled.connect(() => transfer.cancel());
            bool expired = false;
            uint timer = Timeout.add_seconds(limits.timeout_seconds, () => {
                expired = true;
                transfer.cancel();
                return Source.REMOVE;
            });
            try {
                token.set_error_if_cancelled();
                output = yield target.create_async(FileCreateFlags.PRIVATE, Priority.DEFAULT, transfer);
                input = yield source.read_async(Priority.DEFAULT, transfer);
                uint8[] buffer = new uint8[65536];
                uint64 total = 0;
                while (true)
                {
                    ssize_t count = yield input.read_async(buffer, Priority.DEFAULT, transfer);
                    if (count == 0)
                        break;
                    total += count;
                    if (total > limits.maximum_bytes || total > (uint64)info.get_size())
                        throw new FileError.UNSUPPORTED("The file changed or exceeded the configured remote download limit");
                    size_t written;
                    yield output.write_all_async(buffer[0:count], Priority.DEFAULT, transfer, out written);
                    if (progress != null)
                        progress(total, info.get_size());
                }
                var updated = yield source.query_info_async("standard::size,etag::value", FileQueryInfoFlags.NONE, Priority.DEFAULT, transfer);
                if (total != info.get_size() || updated.get_size() != info.get_size() ||
                    (info.get_etag() != null && info.get_etag() != updated.get_etag()))
                    throw new FileError.INTEGRITY("The remote file changed during download; select it again");
                yield input.close_async(Priority.DEFAULT, null);
                input = null;
                yield output.close_async(Priority.DEFAULT, transfer);
                output = null;
                token.set_error_if_cancelled();
                var published = root.get_child(identity);
                yield folder.move_async(published, FileCopyFlags.NONE, Priority.DEFAULT, transfer, null);
                return published.get_child(name);
            }
            catch (Error e) {
                if (input != null)
                    try { yield input.close_async(Priority.DEFAULT, null); } catch (Error ignored) {}
                if (output != null)
                    try { yield output.close_async(Priority.DEFAULT, null); } catch (Error ignored) {}
                try { yield target.delete_async(Priority.DEFAULT, null); } catch (Error ignored) {}
                try { yield folder.delete_async(Priority.DEFAULT, null); } catch (Error ignored) {}
                if (expired)
                    throw new IOError.TIMED_OUT("The download took too long");
                throw e;
            }
            finally {
                token.disconnect(cancel);
                if (!expired)
                    Source.remove(timer);
            }
        }
    }
}
