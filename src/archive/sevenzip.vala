namespace MajorisFiles {
    public delegate void ArchiveCheckpoint(string phase);
    delegate void SevenZipOutput(string text) throws Error;
    public class SevenZip : Object {
        static string program() throws Error
        {
            foreach (var name in new string[] {"7z", "7zz"}) {
                var path = Environment.find_program_in_path(name);
                if (path != null) return path;
            }
            throw new FileError.UNSUPPORTED("The system 7-Zip backend is not installed");
        }
        static async void execute(string[] args, string? password, Job job,SevenZipOutput? inspect = null) throws Error
        {
            var process = new Subprocess.newv(args, SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
            bool expired=false;
            uint timer=Timeout.add_seconds(1800,()=>{expired=true;process.force_exit();return Source.REMOVE;});
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
                    if(inspect!=null)inspect(text);
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
            finally { job.cancellable.disconnect(cancelled); if(!expired)Source.remove(timer); }
        }
        public static async void create(Gee.List<File> sources, File destination, uint64 volume_bytes, uint level, string? password, Job job,ArchiveCheckpoint? checkpoint=null) throws Error
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
            var marker = parent.get_child(destination.get_basename()+".majoris-incomplete");
            string marker_identity="";
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
                yield DurableFiles.flush(staging,job.cancellable);
                if(checkpoint!=null)checkpoint("staged");
                foreach (var part in outputs) {
                    var target = parent.get_child(part.get_basename());
                    // Verify all names first, then still move without overwrite.
                    try { yield target.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable); throw new FileError.CONFLICT("An archive output already exists: " + target.get_basename()); }
                    catch (IOError.NOT_FOUND e) {}
                }
                // Publish the recognizable entry point last. A durable marker
                // makes even a crash after that final rename distinguishable
                // from a completed archive set.
                outputs.sort((a, b) => -Paths.natural_compare(a.get_basename(), b.get_basename()));
                var marker_stream=yield marker.create_async(FileCreateFlags.PRIVATE,Priority.DEFAULT,job.cancellable);
                marker_identity=yield OperationManager.file_identity(marker);
                var manifest=new StringBuilder("Majoris incomplete archive publication v1\n");
                foreach(var part in outputs)manifest.append(part.get_basename()+"\n");
                size_t written;yield marker_stream.write_all_async(manifest.str.data,Priority.DEFAULT,job.cancellable,out written);
                yield marker_stream.close_async(Priority.DEFAULT,job.cancellable);
                yield DurableFiles.flush(marker,job.cancellable);yield DurableFiles.flush(parent,job.cancellable,false);
                if(checkpoint!=null)checkpoint("prepared");
                foreach (var part in outputs) {
                    var target = parent.get_child(part.get_basename());
                    yield part.move_async(target, FileCopyFlags.NONE, Priority.DEFAULT, job.cancellable, null);
                    published[target.get_uri()] = yield OperationManager.file_identity(target);
                    if(checkpoint!=null)checkpoint(part.get_basename()==destination.get_basename()+".001"?"entry-point":"part");
                    job.current = target.get_basename();
                }
                yield staging.delete_async(Priority.DEFAULT, null);
                yield DurableFiles.flush(parent,job.cancellable,false);
                if(marker_identity!=(yield OperationManager.file_identity(marker)))throw new FileError.CONFLICT("The archive publication marker changed; inspect the output set before using it");
                yield marker.delete_async(Priority.DEFAULT,null);yield DurableFiles.flush(parent,new Cancellable(),false);
                if(checkpoint!=null)checkpoint("committed");
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
                if(marker_identity!="" && marker_identity==(yield OperationManager.file_identity(marker)))
                    try{yield marker.delete_async(Priority.DEFAULT,null);}catch(Error ignored){}
                throw e;
            }
        }
        public static async void verify(File archive, string? password, Job job) throws Error
        {
            check_complete(archive);
            string[] args = {program(), "t", "-bsp1"};
            // During testing/extraction, omitting -p requests stdin prompting.
            // An explicit empty -p instead selects the empty password in 7-Zip.
            args += archive.get_path();
            yield execute(args, password, job);
        }
        public static void check_complete(File archive) throws Error {
            string name=archive.get_basename();if(name.has_suffix(".7z.001"))name=name.substring(0,name.length-4);
            if(archive.get_parent().get_child(name+".majoris-incomplete").query_exists())
                throw new FileError.INTEGRITY("Archive publication was interrupted. Keep the listed volumes and the .majoris-incomplete manifest together; verify the complete set with 7-Zip before removing the marker.");
        }
        public static async void extract_isolated(File archive,File destination,string? password,Job job) throws Error {
            check_complete(archive);
            var bwrap=Environment.find_program_in_path("bwrap");
            if(bwrap==null)throw new FileError.UNSUPPORTED("Encrypted 7-Zip extraction requires bubblewrap");
            string[] args={bwrap,"--unshare-all","--die-with-parent","--new-session","--clearenv","--setenv","HOME","/tmp","--setenv","LANG","C.UTF-8","--ro-bind","/usr","/usr","--ro-bind","/bin","/bin","--ro-bind","/lib","/lib","--proc","/proc","--dev","/dev","--tmpfs","/tmp","--dir","/input","--bind",destination.get_path(),"/output","--chdir","/output"};
            if(FileUtils.test("/lib64",FileTest.IS_DIR))foreach(var arg in new string[]{"--ro-bind","/lib64","/lib64"})args+=arg;
            if(archive.get_basename().has_suffix(".7z.001")){
                var stem=archive.get_basename().substring(0,archive.get_basename().length-3);
                uint found=0;
                for(uint i=1;i<=10000;i++){
                    var part=archive.get_parent().get_child(stem+"%03u".printf(i));
                    if(!part.query_exists())break;
                    var info=yield part.query_info_async("standard::type,standard::is-symlink",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.DEFAULT,job.cancellable);
                    if(info.get_file_type()!=FileType.REGULAR||Paths.is_symlink(info))throw new FileError.INVALID("Unsafe archive volume");
                    foreach(var arg in new string[]{"--ro-bind",part.get_path(),"/input/"+part.get_basename()})args+=arg;found++;
                }
                if(found==0)throw new FileError.INVALID("Missing first archive volume");
            }else foreach(var arg in new string[]{"--ro-bind",archive.get_path(),"/input/"+archive.get_basename()})args+=arg;
            foreach(var arg in new string[]{"--","/usr/bin/prlimit","--as=2147483648","--fsize=21474836480","--nofile=128","--cpu=120","--",program(),"x","-y","-aos","-bsp1","-o/output","--","/input/"+archive.get_basename()})args+=arg;
            string[] listing={};foreach(var arg in args){if(arg=="x"){listing+="l";listing+="-slt";}else if(arg!="-o/output"&&arg!="-aos")listing+=arg;}
            string pending_line="";uint64 declared=0;uint entries=0;
            yield execute(listing,password,job,(text)=>{
                pending_line+=text;
                int newline;
                while((newline=pending_line.index_of("\n"))>=0){
                    string line=pending_line.substring(0,newline).strip();pending_line=pending_line.substring(newline+1);
                    if(line.has_prefix("Size = ")){uint64 size;if(!uint64.try_parse(line.substring(7),out size)||size>20UL*1024*1024*1024||declared>20UL*1024*1024*1024-size||++entries>100000)throw new FileError.INVALID("Archive exceeds the 20 GiB / 100,000-entry extraction limit");declared+=size;}
                }
                if(pending_line.length>65536)throw new FileError.INVALID("Oversized archive metadata");
            });
            var free=yield destination.query_filesystem_info_async("filesystem::free",Priority.LOW,job.cancellable);
            if(!free.has_attribute("filesystem::free")||free.get_attribute_uint64("filesystem::free")<declared+32*1024*1024)throw new FileError.INVALID("Not enough verified local storage to extract this archive");
            yield execute(args,password,job);
            var queue=new Gee.ArrayQueue<File>();queue.offer(destination);uint count=0;uint64 size=0;
            while(!queue.is_empty){
                var folder=queue.poll();var en=yield folder.enumerate_children_async("standard::name,standard::type,standard::is-symlink,standard::size,unix::nlink",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.LOW,job.cancellable);
                try{while(true){var batch=yield en.next_files_async(128,Priority.LOW,job.cancellable);if(batch==null)break;
                    foreach(var info in batch){
                        if(++count>100000||Paths.is_symlink(info)||!(info.get_file_type() in new FileType[]{FileType.REGULAR,FileType.DIRECTORY})||(info.get_file_type()==FileType.REGULAR&&info.get_attribute_uint32("unix::nlink")>1))throw new FileError.INVALID("Archive contains links, special files or too many entries");
                        size+=(uint64)info.get_size();if(size>20UL*1024*1024*1024)throw new FileError.INVALID("Archive exceeds the 20 GiB extraction limit");
                        if(info.get_file_type()==FileType.DIRECTORY)queue.offer(folder.get_child(info.get_name()));
                    }
                }}catch(Error e){try{yield en.close_async(Priority.LOW,null);}catch(Error ignored){}throw e;}
                yield en.close_async(Priority.LOW,null);
            }
        }
    }
}
