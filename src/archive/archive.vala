namespace MajorisFiles {
    public delegate void ArchiveProgress(uint64 bytes,uint files);
    class ArchiveInputBudget : Object {public uint64 bytes;public uint count;}
    [CCode(cname = "majoris_archive_extract", cheader_filename = "src/archive/native.h")]
    extern bool native_extract(string source, string destination, string? password, Cancellable token,ArchiveProgress? progress) throws Error;
    [CCode(cname = "majoris_archive_create", cheader_filename = "src/archive/native.h")]
    extern bool native_compress(string destination, string format, [CCode(array_length = false, array_null_terminated = true)] string[] sources, string? password, Cancellable token,ArchiveProgress? progress) throws Error;
    public class ArchiveService : Object {
        public static async void extract(File source, File destination, Job job, string? password = null) throws Error
        {
            SevenZip.check_complete(source);
            if(!destination.is_native()){yield extract_remote(source,destination,job,password);return;}
            if(!source.is_native()&&destination.is_native()){
                var temporary=File.new_for_path(DirUtils.make_tmp("majoris-remote-archive-XXXXXX"));
                try{
                    var local=yield stage_source(source,temporary,job);
                    yield extract(local,destination,job,password);
                }finally{try{yield OperationManager.remove_tree(temporary,new Cancellable());}catch(Error ignored){}}
                return;
            }
            if (!source.is_native() || !destination.is_native())
                throw new FileError.UNSUPPORTED("Archive extraction requires local storage");
            yield destination.make_directory_async(Priority.DEFAULT, job.cancellable);
            if(password!=null&&(source.get_basename().has_suffix(".7z")||source.get_basename().has_suffix(".7z.001"))){
                try{yield SevenZip.extract_isolated(source,destination,password,job);}
                catch(Error e){try{yield OperationManager.remove_tree(destination,new Cancellable());}catch(Error ignored){}throw e;}
                return;
            }
            Error? failure = null;
            SourceFunc resume = extract.callback;
            ArchiveProgress progress=(bytes,files)=>{Idle.add(()=>{if(!job.done)job.current="%u entries · %s extracted".printf(files,Paths.size(bytes));return Source.REMOVE;});};
            new Thread<void*>("extract", () => { try { native_extract(source.get_path(), destination.get_path(), password, job.cancellable,progress);
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
        public static async void compress(Gee.List<File> files, File destination, string format, Job job, string? password = null) throws Error
        {
            if(!(format in new string[] {"zip", "7z", "tar", "tar.gz", "tar.bz2", "tar.xz", "tar.zst"}))
                throw new FileError.UNSUPPORTED("Unsupported archive format");
            if(password != null && (password == "" || password.length > 4096 || format != "zip"))
                throw new FileError.INVALID("Encrypted creation requires ZIP and a non-empty password up to 4096 bytes");
            bool remote=!destination.is_native();foreach(var file in files)if(!file.is_native())remote=true;
            if(remote){yield compress_staged(files,destination,format,job,password);return;}
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
            ArchiveProgress progress=(bytes,count)=>{Idle.add(()=>{if(!job.done)job.current="%u entries · %s archived".printf(count,Paths.size(bytes));return Source.REMOVE;});};
            new Thread<void*>("compress", () => { try { native_compress(destination.get_path(), format, paths, password, job.cancellable,progress);
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
        static async File stage_source(File source,File temporary,Job job) throws Error {
            var imports=temporary.get_child("imports");
            var result=temporary.get_child("volumes");yield result.make_directory_async(Priority.DEFAULT,job.cancellable);
            string name=source.get_basename();bool multipart=name.has_suffix(".7z.001");
            uint64 total=0;
            for(uint part=1;part<=10000;part++){
                var remote=part==1?source:source.get_parent().get_child(name.substring(0,name.length-3)+"%03u".printf(part));
                if(part>1){try{yield remote.query_info_async("standard::type",FileQueryInfoFlags.NONE,Priority.DEFAULT,job.cancellable);}catch(IOError.NOT_FOUND e){break;}}
                var downloaded=yield ChooserImport.download(remote,job.cancellable,imports,new ImportPolicy(),(done,size)=>{job.current="Downloading archive: %s / %s".printf(Paths.size(done),Paths.size(size));job.progress=size==0?0:(double)done/size;});
                var info=yield downloaded.query_info_async("standard::size",FileQueryInfoFlags.NONE,Priority.DEFAULT,job.cancellable);
                total+=(uint64)info.get_size();if(total>10UL*1024*1024*1024)throw new FileError.UNSUPPORTED("Remote archive volumes exceed the 10 GiB staging limit");
                yield downloaded.move_async(result.get_child(remote.get_basename()),FileCopyFlags.NONE,Priority.DEFAULT,job.cancellable,null);
                if(!multipart)break;
            }
            job.current="Extracting "+name;job.progress=0;
            return result.get_child(name);
        }
        static async void compress_staged(Gee.List<File> files,File destination,string format,Job job,string? password) throws Error {
            var temporary=File.new_for_path(DirUtils.make_tmp("majoris-remote-archive-XXXXXX"));bool preserve=false;
            var output=temporary.get_child(destination.get_basename());
            File? pending=null;string pending_identity="";
            try{
                var inputs=new Gee.ArrayList<File>();
                var sources=temporary.get_child("sources");yield sources.make_directory_async(Priority.DEFAULT,job.cancellable);var budget=new ArchiveInputBudget();
                foreach(var file in files){
                    if(file.equal(destination)||destination.has_prefix(file))throw new FileError.INVALID("Archive destination must be outside the selected inputs");
                    if(file.is_native())inputs.add(file);
                    else{var local=sources.get_child(file.get_basename());yield download_tree(file,local,temporary.get_child("imports"),job,budget);inputs.add(local);}
                }
                yield compress(inputs,output,format,job,password);yield DurableFiles.flush(output,job.cancellable);
                if(destination.is_native())yield output.move_async(destination,FileCopyFlags.NONE,Priority.DEFAULT,job.cancellable,null);
                else{
                    pending=destination.get_parent().get_child(".majoris-archive-"+Uuid.string_random());
                    yield output.copy_async(pending,FileCopyFlags.NONE,Priority.DEFAULT,job.cancellable,(done,total)=>{job.current="Uploading archive: "+Paths.size(done);job.progress=total==0?0:(double)done/total;});
                    pending_identity=yield OperationManager.file_identity(pending);
                    // No copy/delete fallback: the backend must provide its own
                    // non-overwriting server-side move of the finished output.
                    yield pending.move_async(destination,FileCopyFlags.NO_FALLBACK_FOR_MOVE,Priority.DEFAULT,job.cancellable,null);
                }
                job.progress=1;
            }catch(Error e){
                if(output.query_exists()){
                    preserve=true;
                    throw new FileError.INTEGRITY("Archive publication did not complete. The complete local result is retained at %s. %s".printf(output.get_path(),e.message));
                }
                throw e;
            }finally{
                if(pending!=null&&pending_identity!=""&&pending_identity==(yield OperationManager.file_identity(pending)))try{yield pending.delete_async(Priority.DEFAULT,null);}catch(Error ignored){}
                if(!preserve)try{yield OperationManager.remove_tree(temporary,new Cancellable());}catch(Error ignored){}
            }
        }
        static async void download_tree(File source,File target,File imports,Job job,ArchiveInputBudget budget,uint depth=0) throws Error {
            if(depth>128||++budget.count>100000)throw new FileError.INVALID("Remote archive input exceeds the tree resource limits");
            var info=yield source.query_info_async("standard::type,standard::is-symlink,standard::size",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.LOW,job.cancellable);
            if(Paths.is_symlink(info))throw new FileError.UNSUPPORTED("Remote archive input links must be resolved explicitly");
            if(info.get_file_type()==FileType.REGULAR){
                if(info.get_size()<0||(uint64)info.get_size()>10UL*1024*1024*1024-budget.bytes)throw new FileError.UNSUPPORTED("Remote archive inputs exceed the 10 GiB staging limit");budget.bytes+=(uint64)info.get_size();
                var local=yield ChooserImport.download(source,job.cancellable,imports,new ImportPolicy(),(done,total)=>{job.current="Downloading archive input: "+Paths.size(done);job.progress=total==0?0:(double)done/total;});
                yield local.move_async(target,FileCopyFlags.NONE,Priority.DEFAULT,job.cancellable,null);return;
            }
            if(info.get_file_type()!=FileType.DIRECTORY)throw new FileError.UNSUPPORTED("Remote archive input is not a regular file or folder");
            yield target.make_directory_async(Priority.DEFAULT,job.cancellable);
            var en=yield source.enumerate_children_async("standard::name",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.LOW,job.cancellable);
            try{while(true){var batch=yield en.next_files_async(128,Priority.LOW,job.cancellable);if(batch==null)break;foreach(var child in batch){if(!Paths.valid_name(child.get_name()))throw new FileError.INVALID("Unsafe remote archive filename");yield download_tree(source.get_child(child.get_name()),target.get_child(child.get_name()),imports,job,budget,depth+1);}}}
            catch(Error e){try{yield en.close_async(Priority.LOW,null);}catch(Error ignored){}throw e;}yield en.close_async(Priority.LOW,null);
        }
        static async void upload_tree(File source,File target,Job job) throws Error {
            var info=yield source.query_info_async("standard::type,standard::is-symlink",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.LOW,job.cancellable);
            if(Paths.is_symlink(info))throw new FileError.INVALID("Extracted links cannot be published remotely");
            if(info.get_file_type()==FileType.REGULAR){yield source.copy_async(target,FileCopyFlags.NONE,Priority.DEFAULT,job.cancellable,(done,total)=>{job.current="Uploading extracted file: "+Paths.size(done);job.progress=total==0?0:(double)done/total;});return;}
            if(info.get_file_type()!=FileType.DIRECTORY)throw new FileError.INVALID("Extracted special file cannot be published remotely");
            yield target.make_directory_async(Priority.DEFAULT,job.cancellable);
            var en=yield source.enumerate_children_async("standard::name",FileQueryInfoFlags.NOFOLLOW_SYMLINKS,Priority.LOW,job.cancellable);
            try{while(true){var batch=yield en.next_files_async(128,Priority.LOW,job.cancellable);if(batch==null)break;foreach(var child in batch)yield upload_tree(source.get_child(child.get_name()),target.get_child(child.get_name()),job);}}
            catch(Error e){try{yield en.close_async(Priority.LOW,null);}catch(Error ignored){}throw e;}yield en.close_async(Priority.LOW,null);
        }
        static async void extract_remote(File source,File destination,Job job,string? password) throws Error {
            var temporary=File.new_for_path(DirUtils.make_tmp("majoris-remote-extraction-XXXXXX"));var output=temporary.get_child("extracted");bool complete=false,preserve=false;
            var pending=destination.get_parent().get_child(".majoris-extract-"+Uuid.string_random());
            try{
                var local=source.is_native()?source:yield stage_source(source,temporary,job);
                yield extract(local,output,job,password);complete=true;yield DurableFiles.flush(output,job.cancellable);
                yield upload_tree(output,pending,job);
                yield pending.move_async(destination,FileCopyFlags.NO_FALLBACK_FOR_MOVE,Priority.DEFAULT,job.cancellable,null);job.progress=1;
            }catch(Error e){
                if(complete){preserve=true;throw new FileError.INTEGRITY("Remote extraction publication did not complete. Complete output is retained at %s. Any uploaded staging folder is %s; inspect it before cleanup. %s".printf(output.get_path(),pending.get_parse_name(),e.message));}
                throw e;
            }finally{if(!preserve)try{yield OperationManager.remove_tree(temporary,new Cancellable());}catch(Error ignored){}}
        }
    }
}
