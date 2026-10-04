namespace MajorisFiles {
    public enum OperationKind {
        COPY, MOVE, TRASH, DELETE, CREATE_FOLDER, RENAME
    }
    public class Job : Object {
        public string title {
            get;
            set;
        }
        public string current {
            get;
            set;
            default = "";
        }
        public double progress {
            get;
            set;
        }
        public string error {
            get;
            set;
            default = "";
        }
        public bool done {
            get;
            set;
        }
        public Cancellable cancellable = new Cancellable();
        public weak Gtk.Window? parent;
        public Job(string title)
        {
            this.title = title;
        }
    }
    public class JournalEntry : Object {
        public OperationKind kind;
        public File source;
        public File destination;
        public JournalEntry(OperationKind kind, File source, File destination)
        {
            this.kind = kind;
            this.source = source;
            this.destination = destination;
        }
    }
    public class OperationManager : Object {
        public GLib.ListStore jobs = new GLib.ListStore(typeof(Job));
        Gee.ArrayList<JournalEntry> undo_stack = new Gee.ArrayList<JournalEntry>();
        Gee.ArrayList<JournalEntry> redo_stack = new Gee.ArrayList<JournalEntry>();
        public MetadataStore metadata;
        public signal void changed();
        public OperationManager(MetadataStore metadata)
        {
            this.metadata = metadata;
        }
        public Job start(string title)
        {
            var job = new Job(title);
            jobs.append(job);
            var app = GLib.Application.get_default();
            if (app != null)
                app.hold();
            return job;
        }
        public void finish(Job job, Error? error = null)
        {
            job.done = true;
            job.progress = 1;
            if (error != null && !(error is IOError.CANCELLED))
                job.error = error.message;
            var app = GLib.Application.get_default();
            if (app != null)
                app.release();
            changed();
        }
        public async void run(OperationKind kind, Gee.List<File> files, File? target = null, Gtk.Window? parent = null)
        {
            var job = start(kind.to_string());
            job.parent = parent;
            try {
                int index = 0;
                bool replace_all = false;
                bool skip_all = false;
                foreach (var source in files)
                {
                    job.cancellable.set_error_if_cancelled();
                    job.current = source.get_parse_name();
                string destination_name=source.get_basename();
                if(kind==OperationKind.MOVE && source.has_uri_scheme("trash")) { var trash_info=yield source.query_info_async("trash::orig-path",FileQueryInfoFlags.NONE,Priority.DEFAULT,job.cancellable); var original_path=trash_info.get_attribute_byte_string("trash::orig-path"); if(original_path!=null) destination_name=Path.get_basename(original_path); }
                File? destination = target == null ? null : target.get_child(destination_name);
                    if (destination != null && (kind == OperationKind.COPY || kind == OperationKind.MOVE))
                    {
                        if (source.equal(destination) || destination.has_prefix(source))
                            throw new FileError.INVALID("The destination is inside the source or is the source itself");
                        bool exists = false;
                        try {
                            yield destination.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                            exists = true;
                        }
                        catch (IOError.NOT_FOUND e) {}
                        File? backup = null;
                        if (exists)
                        {
                            string decision = replace_all ? "replace" : (skip_all ? "skip" : "cancel");
                            if (!replace_all && !skip_all && parent != null)
                            {
                                var alert = new Adw.AlertDialog("An item already exists", source.get_basename() + " already exists in the destination.");
                                alert.add_response("cancel", "Cancel");
                                alert.add_response("skip", "Skip");
                                alert.add_response("skip-all", "Skip All");
                                alert.add_response("both", "Keep Both");
                                alert.add_response("replace", "Replace");
                                alert.add_response("replace-all", "Replace All");
                                alert.close_response = "cancel";
                                decision = yield alert.choose(parent, job.cancellable);
                            }
                            if (decision == "cancel")
                                throw new IOError.CANCELLED("Cancelled");
                            if (decision == "skip-all")
                                skip_all = true;
                            if (decision == "skip" || decision == "skip-all")
                                continue;
                            if (decision == "replace-all")
                                replace_all = true;
                            if (decision == "both")
                            {
                                uint suffix = 1;
                                do {
                                    destination = target.get_child("%s (%u)".printf(source.get_basename(), suffix++));
                                    exists = false;
                                    try {
                                        yield destination.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                                        exists = true;
                                    }
                                    catch (IOError.NOT_FOUND e) {}
                                } while (exists);
                            }
                            else {
                                backup = target.get_child(".majoris-backup-" + Uuid.string_random());
                                yield destination.move_async(backup, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable, null);
                            }
                        }
                        bool complete;
                        try {
                            complete = yield transfer(source, destination, kind == OperationKind.MOVE, job);
                        }
                        catch (Error e) {
                            if (backup != null)
                            {
                                try {
                                    yield remove_tree(destination, new Cancellable());
                                }
                                catch (Error ignored) {}
                                try {
                                    yield backup.move_async(destination, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null, null);
                                }
                                catch (Error recovery) {
                                    throw new FileError.INTEGRITY("Replacement failed. Your previous item is preserved at " + backup.get_parse_name());
                                }
                            }
                            throw e;
                        }
                        if (!complete)
                        {
                            if(backup != null)
                                yield backup.move_async(destination, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null, null);
                            continue;
                        }
                        if (backup != null)
                            yield remove_tree(backup, job.cancellable);
                        // Copies can be removed on undo only if they were not replacements.
                        if (!exists)
                        {
                            undo_stack.add(new JournalEntry(kind, source, destination));
                            redo_stack.clear();
                        }
                        if (kind == OperationKind.MOVE)
                            metadata.relocate(source, destination);
                    }
                    else if (kind == OperationKind.TRASH)
                    {
                        yield source.trash_async(Priority.DEFAULT, job.cancellable);
                    }
                    else if (kind == OperationKind.DELETE)
                    {
                        yield remove_tree(source, job.cancellable);
                    }
                    index++;
                    job.progress = (double) index / files.size;
                }
                finish(job);
            }
            catch (Error e) {
                finish(job, e);
            }
        }
        async bool transfer(File source, File destination, bool move, Job job) throws Error
        {
            var info = yield source.query_info_async("standard::type,standard::is-symlink,standard::size", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
            if (info.get_file_type() == FileType.REGULAR)
            {
                var fs = yield destination.get_parent().query_filesystem_info_async("filesystem::type", Priority.DEFAULT, job.cancellable);
                uint64 limit = Paths.max_file_size(fs.get_attribute_string("filesystem::type") ?? "");
                if (info.get_size() > limit)
                {
                    if (job.parent == null)
                        throw new FileError.UNSUPPORTED("This file exceeds the destination filesystem limit");
                    var alert = new Adw.AlertDialog("This file is too large for the destination filesystem.", "Split it into compatible pieces? The original file will be kept.");
                    alert.add_response("cancel", "Cancel");
                    alert.add_response("split", "Split into Compatible Parts");
                    alert.close_response = "cancel";
                    if ((yield alert.choose(job.parent, job.cancellable)) != "split")
                        throw new IOError.CANCELLED("Cancelled");
                    yield SplitService.split(source, destination.get_parent(), limit - 1024*1024, job);
                    return false;
                }
            }
            if (move)
            {
                try {
                    yield source.move_async(destination, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable, (a, b) => { if (b > 0)
                                                                                                                                             job.progress = (double)a / b;
                                            });
                    return true;
                }
                catch (IOError.WOULD_RECURSE e) {}
                catch (IOError.NOT_SUPPORTED e) {}
            }
            if (info.get_file_type() == FileType.DIRECTORY && !info.get_is_symlink())
            {
                yield destination.make_directory_async(Priority.DEFAULT, job.cancellable);
                var en = yield source.enumerate_children_async("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                bool complete = true;
                while (true)
                {
                    var batch = yield en.next_files_async(128, Priority.DEFAULT, job.cancellable);
                    if (batch == null)
                        break;
                    foreach (var child in batch)
                        if (!(yield transfer(source.get_child(child.get_name()), destination.get_child(child.get_name()), false, job)))
                            complete = false;
                }
                yield en.close_async(Priority.DEFAULT, null);
                if (!complete)
                    return false;
            }
            else yield source.copy_async(destination, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable, (a, b) => { if (b > 0)
                                                                                                                                          job.progress = (double)a / b;
                                         });
            if (move)
                yield remove_tree(source, job.cancellable);
            return true;
        }
        public static async void remove_tree(File file, Cancellable token) throws Error
        {
            var info = yield file.query_info_async("standard::type,standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
            if (info.get_file_type() == FileType.DIRECTORY && !info.get_is_symlink())
            {
                var en = yield file.enumerate_children_async("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                while (true)
                {
                    var batch = yield en.next_files_async(128, Priority.DEFAULT, token);
                    if (batch == null)
                        break;
                    foreach (var child in batch)
                        yield remove_tree(file.get_child(child.get_name()), token);
                }
                yield en.close_async(Priority.DEFAULT, null);
            }
            yield file.delete_async(Priority.DEFAULT, token);
        }
        public async void rename(File file, string name) throws Error
        {
            if (!Paths.valid_name(name))
                throw new FileError.INVALID("Invalid filename");
            var result = yield file.set_display_name_async(name, Priority.DEFAULT, null);
            metadata.relocate(file, result);
            undo_stack.add(new JournalEntry(OperationKind.RENAME, file, result));
            redo_stack.clear();
            changed();
        }
        public async void new_folder(File parent, string name) throws Error
        {
            if (!Paths.valid_name(name))
                throw new FileError.INVALID("Invalid folder name");
            var file = parent.get_child(name);
            yield file.make_directory_async(Priority.DEFAULT, null);
            undo_stack.add(new JournalEntry(OperationKind.CREATE_FOLDER, parent, file));
            redo_stack.clear();
            changed();
        }
        public async void undo(Gtk.Window? parent = null) throws Error
        {
            if (undo_stack.size == 0)
                return;
            var entry = undo_stack[undo_stack.size - 1];
            if (entry.kind == OperationKind.MOVE || entry.kind == OperationKind.RENAME)
            {
                yield entry.destination.move_async(entry.source, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
                metadata.relocate(entry.destination, entry.source);
            }
            else if (entry.kind == OperationKind.CREATE_FOLDER)
                yield entry.destination.delete_async(Priority.DEFAULT, null);
            else if (entry.kind == OperationKind.COPY)
            {
                if(parent == null)
                    throw new FileError.UNSUPPORTED("Copy undo requires confirmation");
                var alert = new Adw.AlertDialog("Undo Copy?", "The copied item will be moved to Trash, including any changes made since copying.");
                alert.add_response("cancel", "Cancel");
                alert.add_response("undo", "Move Copy to Trash");
                alert.close_response = "cancel";
                if((yield alert.choose(parent, null)) != "undo")
                    return;
                yield entry.destination.trash_async(Priority.DEFAULT, null);
            }
            undo_stack.remove_at(undo_stack.size - 1);
            redo_stack.add(entry);
            changed();
        }
        public async void redo() throws Error
        {
            if (redo_stack.size == 0)
                return;
            var entry = redo_stack[redo_stack.size - 1];
            if (entry.kind == OperationKind.MOVE || entry.kind == OperationKind.RENAME)
            {
                yield entry.source.move_async(entry.destination, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
                metadata.relocate(entry.source, entry.destination);
            }
            else if (entry.kind == OperationKind.CREATE_FOLDER)
                yield entry.destination.make_directory_async(Priority.DEFAULT, null);
            else if (entry.kind == OperationKind.COPY)
            {
                var job = new Job("Redo Copy");
                yield transfer(entry.source, entry.destination, false, job);
            }
            redo_stack.remove_at(redo_stack.size - 1);
            undo_stack.add(entry);
            changed();
        }
    }
}
