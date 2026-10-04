namespace MajorisFiles {
    public enum OperationKind {
        COPY, MOVE, TRASH, DELETE, CREATE_FOLDER, RENAME, LINK
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
        public bool cancelled {
            get;
            set;
        }
        public bool can_retry {
            get;
            set;
        }
        public bool retrying {
            get;
            set;
        }
        internal OperationKind retry_kind;
        internal bool replace_all;
        internal bool skip_all;
        internal string journal_group = Uuid.string_random();
        internal File? retry_target;
        internal string target_identity = "";
        internal bool restored_plan;
        internal Gee.HashMap<string, string> source_identities = new Gee.HashMap<string, string>();
        internal Gee.ArrayList<File> remaining = new Gee.ArrayList<File>();
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
        public string source_identity = "";
        public string destination_identity = "";
        public string group = Uuid.string_random();
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
        bool history_busy;
        Gee.HashSet<string> discarded_groups = new Gee.HashSet<string>();
        public signal void changed();
        public OperationManager(MetadataStore metadata)
        {
            this.metadata = metadata;
            restore_history("undo", undo_stack);
            restore_history("redo", redo_stack);
            restore_jobs();
            var interrupted = metadata.state("operations-active");
            if(interrupted != "" && jobs.get_n_items() == 0)
            {
                var job = new Job("Interrupted operations");
                job.current = interrupted;
                job.error = "Files stopped before these operations finished. Check the source and destination before retrying.";
                job.done = true;
                jobs.append(job);
                metadata.set_state("operations-active", "");
            }
        }
        void restore_jobs()
        {
            string saved = metadata.state("operations-plans");
            if(saved == "" || saved.length > 4 * 1024 * 1024)
                return;
            try {
                var plans = Variant.parse(new VariantType("aa{sv}"), saved);
                if(plans.n_children() > 100)
                    return;
                for(size_t i = 0; i < plans.n_children(); i++)
                {
                    var plan = plans.get_child_value(i);
                    var kind = plan.lookup_value("kind", VariantType.UINT32);
                    var title = plan.lookup_value("title", VariantType.STRING);
                    var target = plan.lookup_value("target", VariantType.STRING);
                    var target_id = plan.lookup_value("target-id", VariantType.STRING);
                    var group = plan.lookup_value("group", VariantType.STRING);
                    var sources = plan.lookup_value("sources", new VariantType("a(ss)"));
                    if(kind == null || title == null || target == null || target_id == null || group == null || sources == null || sources.n_children() == 0 || sources.n_children() > 10000)
                        continue;
                    uint value = kind.get_uint32();
                    if(value != OperationKind.COPY && value != OperationKind.MOVE && value != OperationKind.LINK)
                        continue;
                    if(Uri.parse_scheme(target.get_string()) == null || target_id.get_string() == "")
                        continue;
                    var job = new Job(title.get_string());
                    job.retry_kind = (OperationKind)value;
                    job.retry_target = File.new_for_uri(target.get_string());
                    job.target_identity = target_id.get_string();
                    job.journal_group = group.get_string();
                    bool valid = true;
                    for(size_t j = 0; j < sources.n_children(); j++)
                    {
                        var source = sources.get_child_value(j);
                        string uri = source.get_child_value(0).get_string(), identity = source.get_child_value(1).get_string();
                        if(Uri.parse_scheme(uri) == null || identity == "")
                        {
                            valid = false;
                            break;
                        }
                        job.remaining.add(File.new_for_uri(uri));
                        job.source_identities[uri] = identity;
                    }
                    if(!valid)
                        continue;
                    job.done = true;
                    job.can_retry = true;
                    job.restored_plan = true;
                    job.current = job.retry_target.get_parse_name();
                    job.error = "Incomplete operation. Retry rechecks file identities and asks about destination conflicts. Check any preserved .majoris-backup files.";
                    jobs.append(job);
                }
            }
            catch(Error e) {
                warning("Cannot restore operation plans: %s", e.message);
            }
        }
        void restore_history(string key, Gee.ArrayList<JournalEntry> stack)
        {
            var saved = metadata.state("operations-" + key);
            if(saved == "")
                return;
            try {
                bool version_three = saved.has_prefix("v3:");
                bool version_two = saved.has_prefix("v2:") || version_three;
                var entries = Variant.parse(new VariantType(version_three ? "a(usssss)" : version_two ? "a(ussss)" : "a(uss)"), version_two ? saved.substring(3) : saved);
                if(entries.n_children() > 100)
                    return;
                for(size_t i = 0; i < entries.n_children(); i++)
                {
                    var entry = entries.get_child_value(i);
                    uint kind = entry.get_child_value(0).get_uint32();
                    string source = entry.get_child_value(1).get_string(), destination = entry.get_child_value(2).get_string();
                    if(kind > OperationKind.LINK || kind == OperationKind.DELETE || Uri.parse_scheme(source) == null || Uri.parse_scheme(destination) == null)
                        continue;
                    var restored = new JournalEntry((OperationKind)kind, File.new_for_uri(source), File.new_for_uri(destination));
                    if(version_two)
                    {
                        restored.source_identity = entry.get_child_value(3).get_string();
                        restored.destination_identity = entry.get_child_value(4).get_string();
                        if(version_three)
                            restored.group = entry.get_child_value(5).get_string();
                    }
                    stack.add(restored);
                }
            }
            catch(Error e) {
                warning("Cannot restore operation history: %s", e.message);
            }
        }
        void persist_history()
        {
            save_stack("undo", undo_stack);
            save_stack("redo", redo_stack);
        }
        void save_stack(string key, Gee.ArrayList<JournalEntry> stack)
        {
            while(stack.size > 100)
            {
                string oldest = stack[0].group;
                discarded_groups.add(oldest);
                while(stack.size > 0 && stack[0].group == oldest)
                    stack.remove_at(0);
            }
            var builder = new VariantBuilder(new VariantType("a(usssss)"));
            foreach(var entry in stack)
                builder.add("(usssss)", (uint)entry.kind, entry.source.get_uri(), entry.destination.get_uri(), entry.source_identity, entry.destination_identity, entry.group);
            metadata.set_state("operations-" + key, "v3:" + builder.end().print(true));
        }
        static async string file_identity(File file)
        {
            var token = new Cancellable();
            bool timed_out = false;
            uint timeout = Timeout.add_seconds(5, () => { timed_out = true;
                                                          token.cancel();
                                                          return Source.REMOVE;
                });
            try {
                var info = yield file.query_info_async("id::file,id::filesystem,unix::device,unix::inode,time::created,time::created-usec,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                string id = info.get_attribute_string("id::file") ?? "";
                uint64 inode = info.get_attribute_uint64("unix::inode");
                if(id == "" && inode == 0)
                    return "";
                return new Variant("(ssttttu)", id, info.get_attribute_string("id::filesystem") ?? "", (uint64)info.get_attribute_uint32("unix::device"), inode, info.get_attribute_uint64("time::created"), (uint64)info.get_attribute_uint32("time::created-usec"), (uint)info.get_file_type()).print(true);
            }
            catch(Error e) {
                return "";
            }
            finally {
                if(!timed_out)
                    Source.remove(timeout);
            }
        }
        async void record(OperationKind kind, File source, File destination, string? group = null)
        {
            var entry = new JournalEntry(kind, source, destination);
            entry.source_identity = yield file_identity(source);
            entry.destination_identity = yield file_identity(destination);
            if(group != null)
                entry.group = group;
            redo_stack.clear();
            if(discarded_groups.contains(entry.group))
                return;
            int position = undo_stack.size;
            for(int i = 0; i < undo_stack.size; i++)
                if(undo_stack[i].group == entry.group)
                    position = i + 1;
            undo_stack.insert(position, entry);
        }
        static async void require_identity(File file, string expected) throws Error
        {
            if(expected == "")
                throw new FileError.UNSUPPORTED("This operation has no verified file identity and cannot safely be reversed");
            if((yield file_identity(file)) != expected)
                throw new FileError.CONFLICT("The original item is missing or has been replaced: " + file.get_parse_name());
        }
        void persist_jobs()
        {
            var text = new StringBuilder();
            var plans = new VariantBuilder(new VariantType("aa{sv}"));
            for(uint i = 0; i < jobs.get_n_items(); i++)
            {
                var job = (Job)jobs.get_item(i);
                if(!job.done)
                    text.append(job.title + ": " + job.current + "\n");
                if((!job.done || job.can_retry) && job.retry_target != null && job.target_identity != "" && job.remaining.size > 0)
                {
                    var sources = new VariantBuilder(new VariantType("a(ss)"));
                    bool valid = true;
                    foreach(var source in job.remaining)
                    {
                        string identity = job.source_identities[source.get_uri()] ?? "";
                        if(identity == "")
                        {
                            valid = false;
                            break;
                        }
                        sources.add("(ss)", source.get_uri(), identity);
                    }
                    if(valid)
                    {
                        var plan = new VariantBuilder(VariantType.VARDICT);
                        plan.add("{sv}", "kind", new Variant.uint32((uint)job.retry_kind));
                        plan.add("{sv}", "title", new Variant.string(job.title));
                        plan.add("{sv}", "target", new Variant.string(job.retry_target.get_uri()));
                        plan.add("{sv}", "target-id", new Variant.string(job.target_identity));
                        plan.add("{sv}", "group", new Variant.string(job.journal_group));
                        plan.add("{sv}", "sources", sources.end());
                        plans.add_value(plan.end());
                    }
                }
            }
            metadata.set_state("operations-active", text.str);
            metadata.set_state("operations-plans", plans.end().print(true));
        }
        public Job start(string title)
        {
            var job = new Job(title);
            jobs.append(job);
            persist_jobs();
            var app = GLib.Application.get_default();
            if (app != null)
                app.hold();
            return job;
        }
        public void finish(Job job, Error? error = null)
        {
            job.done = true;
            if(error == null)
                job.progress = 1;
            job.cancelled = error is IOError.CANCELLED;
            job.can_retry = error != null && job.remaining.size > 0;
            if (error != null && !(error is IOError.CANCELLED))
                job.error = error.message;
            var app = GLib.Application.get_default();
            if(app != null && !(error is IOError.CANCELLED) && metadata.state("notifications", "true") == "true" && (job.parent == null || !job.parent.is_active))
            {
                var notification = new Notification(job.error == "" ? "File operation completed" : "File operation failed");
                notification.set_body(job.error == "" ? job.title : job.error);
                app.send_notification("operation-" + Uuid.string_random(), notification);
            }
            if (app != null)
                app.release();
            changed();
            persist_history();
            persist_jobs();
        }
        public async void run(OperationKind kind, Gee.List<File> files, File? target = null, Gtk.Window? parent = null, string? journal_group = null)
        {
            var job = start(kind.to_string());
            job.parent = parent;
            if(history_busy)
            {
                finish(job, new IOError.BUSY("Wait for undo or redo to finish"));
                return;
            }
            job.retry_kind = kind;
            if(journal_group != null)
                job.journal_group = journal_group;
            job.retry_target = target;
            int completed = 0;
            try {
                if(target != null && (kind == OperationKind.COPY || kind == OperationKind.MOVE || kind == OperationKind.LINK))
                {
                    job.target_identity = yield file_identity(target);
                    foreach(var source in files)
                    {
                        job.cancellable.set_error_if_cancelled();
                        job.source_identities[source.get_uri()] = yield file_identity(source);
                    }
                    job.remaining.add_all(files);
                    persist_jobs();
                }
                int index = 0;
                var previous_trash = kind == OperationKind.TRASH ? yield trash_snapshot(job.cancellable) : null;


                foreach (var source in files)
                {
                    job.remaining.clear();
                    if(kind == OperationKind.COPY || kind == OperationKind.MOVE || kind == OperationKind.LINK)
                        for(int i = completed; i < files.size; i++)
                            job.remaining.add(files[i]);
                    job.cancellable.set_error_if_cancelled();
                    job.current = source.get_parse_name();
                    persist_jobs();
                    string destination_name = source.get_basename();
                    if(kind == OperationKind.MOVE && source.has_uri_scheme("trash"))
                    {
                        var trash_info = yield source.query_info_async("trash::orig-path", FileQueryInfoFlags.NONE, Priority.DEFAULT, job.cancellable);
                        var original_path = trash_info.get_attribute_byte_string("trash::orig-path");
                        if(original_path != null)
                            destination_name = Path.get_basename(original_path);
                    }
                    File? destination = target == null ? null : target.get_child(destination_name);
                    if(kind == OperationKind.LINK)
                    {
                        if(destination == null || !source.is_native() || !destination.is_native())
                            throw new FileError.UNSUPPORTED("Symbolic links require local source and destination paths");
                        // Exclusive creation leaves any existing item untouched.
                        yield destination.make_symbolic_link_async(source.get_path(), Priority.DEFAULT, job.cancellable);
                        yield record(kind, source, destination, job.journal_group);
                    }
                    else if (destination != null && (kind == OperationKind.COPY || kind == OperationKind.MOVE))
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
                        bool merge = false;
                        if (exists)
                        {
                            string decision = job.replace_all ? "replace" : (job.skip_all ? "skip" : "cancel");
                            if (!job.replace_all && !job.skip_all && parent != null)
                            {
                                var source_info = yield source.query_info_async("standard::type,standard::size,time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                                var destination_info = yield destination.query_info_async("standard::type,standard::size,time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                                var source_date = source_info.get_modification_date_time();
                                var destination_date = destination_info.get_modification_date_time();
                                var detail = "%s\nSource: %s · %s\nDestination: %s · %s".printf(destination_name, Paths.size(source_info.get_size()), source_date == null ? "Unknown date" : source_date.format("%c"), Paths.size(destination_info.get_size()), destination_date == null ? "Unknown date" : destination_date.format("%c"));
                                var alert = new Adw.AlertDialog("An item already exists", detail);
                                alert.add_response("cancel", "Cancel");
                                alert.add_response("skip", "Skip");
                                alert.add_response("skip-all", "Skip All");
                                alert.add_response("both", "Keep Both");
                                alert.add_response("rename", "Rename");
                                if(source_info.get_file_type() == FileType.DIRECTORY && destination_info.get_file_type() == FileType.DIRECTORY)
                                    alert.add_response("merge", "Merge Folders");
                                alert.add_response("replace", "Replace");
                                alert.add_response("replace-all", "Replace All");
                                alert.close_response = "cancel";
                                decision = yield alert.choose(parent, job.cancellable);
                            }
                            if (decision == "cancel")
                                throw new IOError.CANCELLED("Cancelled");
                            if (decision == "skip-all")
                                job.skip_all = true;
                            if (decision == "skip" || decision == "skip-all")
                            {
                                completed++;
                                continue;
                            }
                            if (decision == "replace-all")
                                job.replace_all = true;
                            if(decision == "merge")
                                merge = true;
                            else if(decision == "rename")
                            {
                                var name = yield Dialogs.prompt(parent, "Destination Name", destination_name);
                                if(name == null)
                                    throw new IOError.CANCELLED("Cancelled");
                                if(!Paths.valid_name(name))
                                    throw new FileError.INVALID("Invalid destination name");
                                destination = target.get_child(name);
                                try {
                                    yield destination.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                                    throw new FileError.INVALID("An item with that name already exists");
                                }
                                catch(IOError.NOT_FOUND e) {}
                                exists = false;
                            }
                            else if (decision == "both")
                            {
                                uint suffix = 1;
                                do {
                                    destination = target.get_child("%s (%u)".printf(destination_name, suffix++));
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
                            complete = merge ? yield merge_folders(source, destination, kind == OperationKind.MOVE, job) : yield transfer(source, destination, kind == OperationKind.MOVE, job);
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
                            {
                                try {
                                    yield remove_tree(destination, new Cancellable());
                                }
                                catch(IOError.NOT_FOUND ignored) {}
                                try {
                                    yield backup.move_async(destination, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null, null);
                                }
                                catch(Error e) {
                                    throw new FileError.INTEGRITY("Previous item preserved at " + backup.get_parse_name());
                                }
                            }
                            completed++;
                            continue;
                        }
                        if (backup != null)
                            yield remove_tree(backup, job.cancellable);
                        // Copies can be removed on undo only if they were not replacements.
                        if (!exists)
                        {
                            yield record(kind, source, destination, job.journal_group);
                            redo_stack.clear();
                        }
                        if (kind == OperationKind.MOVE && !merge)
                            metadata.relocate(source, destination);
                    }
                    else if (kind == OperationKind.TRASH)
                    {
                        yield source.trash_async(Priority.DEFAULT, job.cancellable);
                        if(previous_trash != null)
                        {
                            var trashed = yield find_trashed(source, previous_trash, job.cancellable);
                            if(trashed != null)
                            {
                                previous_trash.add(trashed.get_uri());
                                yield record(OperationKind.TRASH, source, trashed, job.journal_group);
                                redo_stack.clear();
                                persist_history();
                            }
                        }
                    }
                    else if (kind == OperationKind.DELETE)
                    {
                        yield remove_tree(source, job.cancellable);
                    }
                    index++;
                    completed++;
                    job.progress = (double) index / files.size;
                }
                job.remaining.clear();
                finish(job);
            }
            catch (Error e) {
                finish(job, e);
            }
        }
        public async void retry(Job job, Gtk.Window? parent = null) throws Error
        {
            if(!job.done || !job.can_retry || job.retrying)
                return;
            bool registered = false;
            for(uint i = 0; i < jobs.get_n_items(); i++)
                if(jobs.get_item(i) == job)
                    registered = true;
            if(!registered)
                return;
            job.retrying = true;
            try {
                var pending = new Gee.ArrayList<File>();
                pending.add_all(job.remaining);
                if(job.restored_plan)
                {
                    yield require_identity(job.retry_target, job.target_identity);
                    foreach(var source in pending)
                        yield require_identity(source, job.source_identities[source.get_uri()]);
                }
                job.can_retry = false;
                yield run(job.retry_kind, pending, job.retry_target, parent, job.journal_group);
            }
            finally {
                job.retrying = false;
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
        async bool merge_folders(File source, File destination, bool move, Job job) throws Error
        {
            var enumerator = yield source.enumerate_children_async("standard::name,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
            bool complete = true;
            try {
                while(true)
                {
                    var batch = yield enumerator.next_files_async(64, Priority.DEFAULT, job.cancellable);
                    if(batch == null)
                        break;
                    foreach(var info in batch)
                    {
                        var child = source.get_child(info.get_name());
                        var target = destination.get_child(info.get_name());
                        FileInfo? existing = null;
                        try {
                            existing = yield target.query_info_async("standard::type,standard::size,time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                        }
                        catch(IOError.NOT_FOUND e) {}
                        if(existing != null && info.get_file_type() == FileType.DIRECTORY && existing.get_file_type() == FileType.DIRECTORY)
                        {
                            if(!(yield merge_folders(child, target, move, job)))
                                complete = false;
                            continue;
                        }
                        File? backup = null;
                        if(existing != null)
                        {
                            if(job.parent == null && !job.replace_all && !job.skip_all)
                                throw new FileError.INVALID("A merged child conflicts with an existing item");
                            var incoming = yield child.query_info_async("standard::size,time::modified", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                            var source_date = incoming.get_modification_date_time();
                            var target_date = existing.get_modification_date_time();
                            var detail = target.get_parse_name() + "\nSource: " + Paths.size(incoming.get_size()) + " · " + (source_date == null ? "Unknown date" : source_date.format("%c")) + "\nDestination: " + Paths.size(existing.get_size()) + " · " + (target_date == null ? "Unknown date" : target_date.format("%c"));
                            var dialog = new Adw.AlertDialog("An item already exists", detail);
                            dialog.add_response("cancel", "Cancel");
                            dialog.add_response("skip", "Skip");
                            dialog.add_response("skip-all", "Skip All");
                            dialog.add_response("both", "Keep Both");
                            dialog.add_response("rename", "Rename");
                            dialog.add_response("replace", "Replace");
                            dialog.add_response("replace-all", "Replace All");
                            dialog.close_response = "cancel";
                            var decision = job.replace_all ? "replace" : job.skip_all ? "skip" : yield dialog.choose(job.parent, job.cancellable);
                            if(decision == "cancel")
                                throw new IOError.CANCELLED("Cancelled");
                            if(decision == "skip-all")
                                job.skip_all = true;
                            if(decision == "replace-all")
                                job.replace_all = true;
                            if(decision == "skip" || decision == "skip-all")
                            {
                                complete = false;
                                continue;
                            }
                            if(decision == "rename")
                            {
                                var name = yield Dialogs.prompt(job.parent, "Destination Name", info.get_name());
                                if(name == null)
                                    throw new IOError.CANCELLED("Cancelled");
                                if(!Paths.valid_name(name))
                                    throw new FileError.INVALID("Invalid destination name");
                                target = destination.get_child(name);
                                try {
                                    yield target.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                                    throw new FileError.CONFLICT("An item with that name already exists");
                                }
                                catch(IOError.NOT_FOUND e) {}
                                existing = null;
                            }
                            else if(decision == "both")
                            {
                                uint suffix = 1;
                                while(true)
                                {
                                    target = destination.get_child("%s (%u)".printf(info.get_name(), suffix++));
                                    try {
                                        yield target.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                                    }
                                    catch(IOError.NOT_FOUND e) {
                                        break;
                                    }
                                }
                                existing = null;
                            }
                            else {
                                backup = destination.get_child(".majoris-backup-" + Uuid.string_random());
                                yield target.move_async(backup, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable, null);
                            }
                        }
                        try {
                            if(!(yield transfer(child, target, move, job)))
                            {
                                complete = false;
                                if(backup != null)
                                {
                                    try {
                                        yield remove_tree(target, new Cancellable());
                                    }
                                    catch(IOError.NOT_FOUND ignored) {}
                                    try {
                                        yield backup.move_async(target, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null, null);
                                    }
                                    catch(Error e) {
                                        throw new FileError.INTEGRITY("Previous item preserved at " + backup.get_parse_name());
                                    }
                                }
                                continue;
                            }
                        }
                        catch(Error e) {
                            if(backup != null)
                            {
                                try {
                                    yield remove_tree(target, new Cancellable());
                                }
                                catch(Error ignored) {}
                                try {
                                    yield backup.move_async(target, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null, null);
                                }
                                catch(Error recovery) {
                                    throw new FileError.INTEGRITY("Previous item preserved at " + backup.get_parse_name());
                                }
                            }
                            throw e;
                        }
                        if(backup != null)
                            yield remove_tree(backup, job.cancellable);
                        if(existing == null)
                        {
                            yield record(move ? OperationKind.MOVE : OperationKind.COPY, child, target, job.journal_group);
                            redo_stack.clear();
                            persist_history();
                        }
                        if(move)
                            metadata.relocate(child, target);
                    }
                }
            }
            catch(Error e) {
                try {
                    yield enumerator.close_async(Priority.DEFAULT, null);
                }
                catch(Error ignored) {}
                throw e;
            }
            yield enumerator.close_async(Priority.DEFAULT, null);
            if(move && complete)
                yield source.delete_async(Priority.DEFAULT, job.cancellable);
            return complete;
        }
        static async void ensure_parent(File file) throws Error
        {
            var parent = file.get_parent();
            if(parent == null)
                return;
            try {
                yield parent.query_info_async("standard::type", FileQueryInfoFlags.NONE, Priority.DEFAULT, null);
            }
            catch(IOError.NOT_FOUND e) {
                yield ensure_parent(parent);
                yield parent.make_directory_async(Priority.DEFAULT, null);
            }
        }
        static async Gee.HashSet<string>? trash_snapshot(Cancellable token) throws Error {
            var result = new Gee.HashSet<string>();
            var trash = File.new_for_uri("trash:///");
            try {
                var en = yield trash.enumerate_children_async("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                try {
                    while(true)
                    {
                        var batch = yield en.next_files_async(128, Priority.DEFAULT, token);
                        if(batch == null)
                            break;
                        foreach(var info in batch)
                            result.add(trash.get_child(info.get_name()).get_uri());
                    }
                }
                catch(Error e) {
                    try {
                        yield en.close_async(Priority.DEFAULT, null);
                    }
                    catch(Error ignored) {}
                    throw e;
                }
                yield en.close_async(Priority.DEFAULT, null);
                return result;
            }
            catch(IOError.CANCELLED e) {
                throw e;
            }
            catch(Error e) {
                return null;
            }
        }
        static async File? find_trashed(File original, Gee.HashSet<string> previous, Cancellable token) throws Error
        {
            if(!original.is_native())
                return null;
            var trash = File.new_for_uri("trash:///");
            File? match = null;
            var en = yield trash.enumerate_children_async("standard::name,trash::orig-path", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
            bool ambiguous = false;
            try {
                while(true)
                {
                    var batch = yield en.next_files_async(128, Priority.DEFAULT, token);
                    if(batch == null)
                        break;
                    foreach(var info in batch)
                    {
                        var candidate = trash.get_child(info.get_name());
                        var path = info.get_attribute_byte_string("trash::orig-path");
                        if(!previous.contains(candidate.get_uri()) && path != null && File.new_for_path(path).equal(original))
                        {
                            if(match != null)
                                ambiguous = true;
                            else match = candidate;
                        }
                    }
                }
            }
            catch(Error e) {
                try {
                    yield en.close_async(Priority.DEFAULT, null);
                }
                catch(Error ignored) {}
                throw e;
            }
            yield en.close_async(Priority.DEFAULT, null);
            return ambiguous ? null : match;
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
            if(history_busy)
                throw new IOError.BUSY("Wait for undo or redo to finish");
            if (!Paths.valid_name(name))
                throw new FileError.INVALID("Invalid filename");
            var result = yield file.set_display_name_async(name, Priority.DEFAULT, null);
            metadata.relocate(file, result);
            yield record(OperationKind.RENAME, file, result);
            redo_stack.clear();
            persist_history();
            changed();
        }
        public async void new_folder(File parent, string name) throws Error
        {
            if(history_busy)
                throw new IOError.BUSY("Wait for undo or redo to finish");
            if (!Paths.valid_name(name))
                throw new FileError.INVALID("Invalid folder name");
            var file = parent.get_child(name);
            yield file.make_directory_async(Priority.DEFAULT, null);
            yield record(OperationKind.CREATE_FOLDER, parent, file);
            redo_stack.clear();
            persist_history();
            changed();
        }
        public async void undo(Gtk.Window? parent = null) throws Error
        {
            if(history_busy || running_jobs())
                throw new IOError.BUSY("An undo or redo is already running");
            history_busy = true;
            var application = GLib.Application.get_default();
            if(application != null)
                application.hold();
            try {
                if(undo_stack.size == 0)
                    return;
                string group = undo_stack[undo_stack.size - 1].group;
                bool copies = false;
                var records = new Gee.ArrayList<JournalEntry>();
                foreach(var entry in undo_stack)
                    if(entry.group == group)
                        records.add(entry);
                foreach(var entry in records)
                {
                    yield require_identity(entry.destination, entry.destination_identity);
                    if(entry.kind == OperationKind.COPY)
                        copies = true;
                }
                if(copies)
                {
                    if(parent == null)
                        throw new FileError.UNSUPPORTED("Copy undo requires confirmation");
                    var alert = new Adw.AlertDialog("Undo Copy?", "Copied items in this operation will be moved to Trash, including changes made since copying.");
                    alert.add_response("cancel", "Cancel");
                    alert.add_response("undo", "Move Copies to Trash");
                    alert.close_response = "cancel";
                    if((yield alert.choose(parent, null)) != "undo")
                        return;
                }
                while(undo_stack.size > 0 && undo_stack[undo_stack.size - 1].group == group)
                    yield undo_entry();
            }
            finally {
                history_busy = false;
                if(application != null)
                    application.release();
            }
        }
        bool running_jobs()
        {
            for(uint i = 0; i < jobs.get_n_items(); i++)
                if(!((Job)jobs.get_item(i)).done)
                    return true;
            return false;
        }
        async void undo_entry() throws Error
        {
            if (undo_stack.size == 0)
                return;
            var entry = undo_stack[undo_stack.size - 1];
            yield require_identity(entry.destination, entry.destination_identity);
            if (entry.kind == OperationKind.MOVE || entry.kind == OperationKind.RENAME || entry.kind == OperationKind.TRASH)
            {
                yield ensure_parent(entry.source);
                yield entry.destination.move_async(entry.source, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
                metadata.relocate(entry.destination, entry.source);
            }
            else if (entry.kind == OperationKind.CREATE_FOLDER || entry.kind == OperationKind.LINK)
                yield entry.destination.delete_async(Priority.DEFAULT, null);
            else if (entry.kind == OperationKind.COPY)
            {
                yield entry.destination.trash_async(Priority.DEFAULT, null);
            }
            entry.source_identity = yield file_identity(entry.source);
            undo_stack.remove(entry);
            redo_stack.add(entry);
            persist_history();
            changed();
        }
        public async void redo() throws Error
        {
            if(history_busy || running_jobs())
                throw new IOError.BUSY("An undo or redo is already running");
            history_busy = true;
            var application = GLib.Application.get_default();
            if(application != null)
                application.hold();
            try {
                if(redo_stack.size == 0)
                    return;
                string group = redo_stack[redo_stack.size - 1].group;
                var records = new Gee.ArrayList<JournalEntry>();
                foreach(var entry in redo_stack)
                    if(entry.group == group)
                        records.add(entry);
                foreach(var entry in records)
                    yield require_identity(entry.source, entry.source_identity);
                while(redo_stack.size > 0 && redo_stack[redo_stack.size - 1].group == group)
                    yield redo_entry();
            }
            finally {
                history_busy = false;
                if(application != null)
                    application.release();
            }
        }
        async void redo_entry() throws Error
        {
            if (redo_stack.size == 0)
                return;
            var entry = redo_stack[redo_stack.size - 1];
            yield require_identity(entry.source, entry.source_identity);
            if (entry.kind == OperationKind.MOVE || entry.kind == OperationKind.RENAME)
            {
                yield entry.source.move_async(entry.destination, FileCopyFlags.NONE, Priority.DEFAULT, null, null);
                metadata.relocate(entry.source, entry.destination);
            }
            else if(entry.kind == OperationKind.TRASH)
            {
                var previous = yield trash_snapshot(new Cancellable());
                if(previous == null)
                    throw new FileError.UNSUPPORTED("The Trash backend is unavailable");
                yield entry.source.trash_async(Priority.DEFAULT, null);
                var destination = yield find_trashed(entry.source, previous, new Cancellable());
                if(destination == null)
                {
                    redo_stack.remove(entry);
                    persist_history();
                    throw new FileError.UNSUPPORTED("The restored file was trashed, but its new Trash entry could not be identified");
                }
                entry.destination = destination;
            }
            else if (entry.kind == OperationKind.CREATE_FOLDER)
                yield entry.destination.make_directory_async(Priority.DEFAULT, null);
            else if(entry.kind == OperationKind.LINK)
                yield entry.destination.make_symbolic_link_async(entry.source.get_path(), Priority.DEFAULT, null);
            else if (entry.kind == OperationKind.COPY)
            {
                var job = new Job("Redo Copy");
                yield transfer(entry.source, entry.destination, false, job);
            }
            entry.destination_identity = yield file_identity(entry.destination);
            redo_stack.remove(entry);
            undo_stack.add(entry);
            persist_history();
            changed();
        }
    }
}
