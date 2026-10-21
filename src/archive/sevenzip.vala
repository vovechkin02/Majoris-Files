namespace MajorisFiles {
    public class SevenZip : Object {
        static string program() throws Error
        {
            foreach (var name in new string[] {"7z", "7zz"}) {
                var path = Environment.find_program_in_path(name);
                if (path != null) return path;
            }
            throw new FileError.UNSUPPORTED("The system 7-Zip backend is not installed");
        }
        static async void execute(string[] args, string? password, Job job) throws Error
        {
            var process = new Subprocess.newv(args, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
            ulong cancelled = job.cancellable.cancelled.connect(() => process.force_exit());
            try {
                job.cancellable.set_error_if_cancelled();
                if (password != null) {
                    if (password.contains("\n") || password.contains("\r") || password.length > 4096)
                        throw new FileError.INVALID("Archive passwords must be one line, at most 4096 bytes");
                    size_t written;
                    yield process.get_stdin_pipe().write_all_async((password + "\n" + password + "\n").data, Priority.DEFAULT, job.cancellable, out written);
                }
                yield process.get_stdin_pipe().close_async(Priority.DEFAULT, null);
                uint8[] buffer = new uint8[4097];
                var percentage = new Regex("([0-9]{1,3})%");
                string diagnostic = "";
                while (true) {
                    ssize_t count = yield process.get_stdout_pipe().read_async(buffer[0:4096], Priority.LOW, job.cancellable);
                    if (count == 0) break;
                    buffer[count] = 0;
                    string text = ((string)buffer).make_valid();
                    diagnostic += text;
                    if (diagnostic.length > 8192) diagnostic = diagnostic.substring(diagnostic.length - 4096).make_valid();
                    MatchInfo match;
                    if (percentage.match(text, 0, out match)) {
                        int value = int.parse(match.fetch(1));
                        job.progress = value.clamp(0, 100) / 100.0;
                    }
                }
                yield process.wait_async(job.cancellable);
                if (!process.get_successful()) throw new FileError.INVALID("7-Zip could not complete the operation: " + diagnostic);
            }
            catch (Error e) { process.force_exit(); throw e; }
            finally { job.cancellable.disconnect(cancelled); }
        }
        public static async void create(Gee.List<File> sources, File destination, uint64 volume_bytes, uint level, string? password, Job job) throws Error
        {
            if (!destination.is_native() || !destination.get_basename().has_suffix(".7z") || sources.size == 0 || level > 9 ||
                (volume_bytes != 0 && volume_bytes < 1024 * 1024))
                throw new FileError.INVALID("Choose a local .7z destination and volumes of at least 1 MiB");
            var parent = destination.get_parent();
            foreach (var source in sources)
                if (!source.is_native() || destination.equal(source) || destination.has_prefix(source))
                    throw new FileError.INVALID("Choose local inputs and a destination outside the selected folders");
            // Compression happens in an exclusive sibling directory. Publication uses
            // non-overwriting moves; the preflight does not reserve destination paths.
            var staging = parent.get_child(".majoris-archive-" + Uuid.string_random());
            yield staging.make_directory_async(Priority.DEFAULT, job.cancellable);
            var output = staging.get_child(destination.get_basename());
            var published = new Gee.HashMap<string, string>();
            try {
                string[] args = {program(), "a", "-t7z", "-mx=" + level.to_string(), "-snl", "-bsp1", "-bso1", "-bse1"};
                if (volume_bytes > 0) args += "-v" + volume_bytes.to_string() + "b";
                if (password != null) { args += "-p"; args += "-mhe=on"; }
                args += output.get_path(); args += "--";
                foreach (var source in sources) args += source.get_path();
                job.current = "Creating " + destination.get_basename();
                yield execute(args, password, job);
                var en = yield staging.enumerate_children_async("standard::name,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                var outputs = new Gee.ArrayList<File>();
                try {
                    while (true) {
                        var batch = yield en.next_files_async(128, Priority.DEFAULT, job.cancellable);
                        if (batch == null) break;
                        foreach (var info in batch) {
                            if (info.get_file_type() != FileType.REGULAR) throw new FileError.INVALID("Unexpected archive output");
                            outputs.add(staging.get_child(info.get_name()));
                            if (outputs.size > 10000) throw new FileError.INVALID("Archive exceeds the 10,000-volume safety limit");
                        }
                    }
                }
                catch (Error e) { try { yield en.close_async(Priority.DEFAULT, null); } catch (Error ignored) {} throw e; }
                yield en.close_async(Priority.DEFAULT, null);
                if (outputs.size == 0) throw new FileError.INVALID("No archive volumes were produced");
                foreach (var part in outputs) {
                    var target = parent.get_child(part.get_basename());
                    // Verify all names first, then still move without overwrite.
                    try { yield target.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable); throw new FileError.CONFLICT("An archive output already exists: " + target.get_basename()); }
                    catch (IOError.NOT_FOUND e) {}
                }
                outputs.sort((a, b) => Paths.natural_compare(a.get_basename(), b.get_basename()));
                foreach (var part in outputs) {
                    var target = parent.get_child(part.get_basename());
                    yield part.move_async(target, FileCopyFlags.NONE, Priority.DEFAULT, job.cancellable, null);
                    published[target.get_uri()] = yield OperationManager.file_identity(target);
                    job.current = target.get_basename();
                }
                yield staging.delete_async(Priority.DEFAULT, null);
                job.progress = 1;
            }
            catch (Error e) {
                // Roll back only outputs whose identities still belong to this job.
                foreach (var entry in published.entries) {
                    var file = File.new_for_uri(entry.key);
                    if (entry.value != "" && (yield OperationManager.file_identity(file)) == entry.value)
                        try { yield file.delete_async(Priority.DEFAULT, null); } catch (Error ignored) {}
                }
                try { yield OperationManager.remove_tree(staging, new Cancellable()); } catch (Error ignored) {}
                throw e;
            }
        }
        public static async void verify(File archive, string? password, Job job) throws Error
        {
            string[] args = {program(), "t", "-bsp1"};
            // During testing/extraction, omitting -p requests stdin prompting.
            // An explicit empty -p instead selects the empty password in 7-Zip.
            args += archive.get_path();
            yield execute(args, password, job);
        }
    }
}
