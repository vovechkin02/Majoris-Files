namespace MajorisFiles {
    [CCode(cname = "majoris_archive_extract", cheader_filename = "src/archive/native.h")]
    extern bool native_extract(string source, string destination, Cancellable token) throws Error;
    [CCode(cname = "majoris_archive_create", cheader_filename = "src/archive/native.h")]
    extern bool native_compress(string destination, string format, [CCode(array_length = false, array_null_terminated = true)] string[] sources, Cancellable token) throws Error;
    public class ArchiveService : Object {
        public static async void extract(File source, File destination, Job job) throws Error
        {
            if (!source.is_native() || !destination.is_native())
                throw new FileError.UNSUPPORTED("Archive extraction requires local storage");
            yield destination.make_directory_async(Priority.DEFAULT, job.cancellable);
            Error? failure = null;
            SourceFunc resume = extract.callback;
            new Thread<void*>("extract", () => { try { native_extract(source.get_path(), destination.get_path(), job.cancellable);
                                                 }
                                                 catch (Error e) { failure = e;
                                                 }
                                                 Idle.add((owned)resume);
                                                 return null;
                });
            yield;
            if (failure != null)
            {
                try {
                    yield OperationManager.remove_tree(destination, new Cancellable());
                }
                catch (Error e) {}
                throw failure;
            }
        }
        public static async void compress(Gee.List<File> files, File destination, string format, Job job) throws Error
        {
            string[] paths = {};
            foreach (var file in files)
            {
                if (!file.is_native() || destination.equal(file) || destination.has_prefix(file))
                    throw new FileError.INVALID("Archive destination must be local and outside the source folders");
                paths += file.get_path();
            }
            if (!destination.is_native())
                throw new FileError.UNSUPPORTED("Archive creation requires local storage");
            Error? failure = null;
            SourceFunc resume = compress.callback;
            new Thread<void*>("compress", () => { try { native_compress(destination.get_path(), format, paths, job.cancellable);
                                                  }
                                                  catch (Error e) { failure = e;
                                                  }
                                                  Idle.add((owned)resume);
                                                  return null;
                });
            yield;
            if (failure != null)
                throw failure;
        }
    }
}
