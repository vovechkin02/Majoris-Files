namespace MajorisFiles {
    // An explicitly approved, durable local copy. Never used for Save: there is
    // deliberately no implicit remote writeback or sandbox permission bypass.
    public class ChooserImport : Object {
        public static async File download(File source, Cancellable token, File? import_root = null) throws Error
        {
            const uint64 LIMIT = 64 * 1024 * 1024;
            var info = yield source.query_info_async("standard::type,standard::size,standard::name", FileQueryInfoFlags.NONE, Priority.DEFAULT, token);
            if (info.get_file_type() != FileType.REGULAR ||
                !info.has_attribute("standard::size") || info.get_size() > LIMIT)
                throw new FileError.UNSUPPORTED("Only regular files up to 64 MiB can be imported");
            string name = source.get_basename();
            if (!Paths.valid_name(name))
                throw new FileError.INVALID("Invalid imported filename");
            string downloads = Environment.get_user_special_dir(UserDirectory.DOWNLOAD) ?? Environment.get_home_dir();
            var root = import_root ?? File.new_for_path(Path.build_filename(downloads, "Files Imports"));
            if (!root.is_native())
                throw new FileError.INVALID("The import destination must be local");
            try { yield root.make_directory_async(Priority.DEFAULT, token); }
            catch (IOError.EXISTS e) {}
            var root_info = yield root.query_info_async("standard::type,standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
            if (root_info.get_file_type() != FileType.DIRECTORY || root_info.get_is_symlink())
                throw new FileError.INVALID("The import destination must be a local directory");
            var folder = root.get_child(Uuid.string_random());
            yield folder.make_directory_async(Priority.DEFAULT, token);
            var target = folder.get_child(name);
            InputStream? input = null;
            OutputStream? output = null;
            var transfer = new Cancellable();
            ulong cancel = token.cancelled.connect(() => transfer.cancel());
            bool expired = false;
            uint timer = Timeout.add_seconds(60, () => {
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
                    if (total > LIMIT)
                        throw new FileError.UNSUPPORTED("The file exceeded the 64 MiB import limit");
                    size_t written;
                    yield output.write_all_async(buffer[0:count], Priority.DEFAULT, transfer, out written);
                }
                yield input.close_async(Priority.DEFAULT, null);
                input = null;
                yield output.close_async(Priority.DEFAULT, transfer);
                output = null;
                token.set_error_if_cancelled();
                return target;
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
