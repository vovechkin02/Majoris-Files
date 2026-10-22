namespace MajorisFiles {
    public class RenameRecovery : Object {
        public const string KEY="batch-rename-recovery-v1";
        MetadataStore metadata;
        public bool pending {get{return metadata.state(KEY)!="";}}
        public RenameRecovery(MetadataStore metadata){this.metadata=metadata;}
        public async void prepare(Gee.List<File> sources,Gee.List<File> temporary,Gee.List<string> names) throws Error {
            if(pending)throw new IOError.BUSY("Recover the interrupted batch rename before starting another batch");
            var entries=new VariantBuilder(new VariantType("a(ssss)"));
            for(int i=0;i<sources.size;i++){
                if(!sources[i].is_native())throw new IOError.NOT_SUPPORTED("Crash-safe batch rename requires a native filesystem");
                var identity=yield OperationManager.file_identity(sources[i]);
                if(identity=="")throw new IOError.NOT_SUPPORTED("Cannot identify a batch rename input");
                entries.add("(ssss)",sources[i].get_uri(),temporary[i].get_uri(),sources[i].get_parent().get_child(names[i]).get_uri(),identity);
            }
            metadata.set_state_checked(KEY,entries.end().print(true));
        }
        public void clear() throws Error{metadata.set_state_checked(KEY,"");}
        public async void recover(Cancellable token) throws Error {
            string saved=metadata.state(KEY);if(saved=="")return;
            if(saved.length>4*1024*1024)throw new IOError.INVALID_DATA("Invalid rename recovery journal");
            var records=Variant.parse(new VariantType("a(ssss)"),saved);
            if(records.n_children()==0||records.n_children()>1000)throw new IOError.INVALID_DATA("Invalid rename recovery count");
            var originals=new Gee.ArrayList<File>();var temporary=new Gee.ArrayList<File>();var current=new Gee.ArrayList<File>();var identities=new Gee.ArrayList<string>();
            for(size_t i=0;i<records.n_children();i++){
                var record=records.get_child_value(i);var original=File.new_for_uri(record.get_child_value(0).get_string());var staging=File.new_for_uri(record.get_child_value(1).get_string());var target=File.new_for_uri(record.get_child_value(2).get_string());string identity=record.get_child_value(3).get_string();
                if(!original.is_native()||original.get_parent()==null||!original.get_parent().equal(staging.get_parent())||!original.get_parent().equal(target.get_parent())||!staging.get_basename().has_prefix(".majoris-rename-")||identity=="")throw new IOError.INVALID_DATA("Invalid rename recovery paths");
                File? found=null;
                foreach(var candidate in new File[]{original,staging,target})if((yield OperationManager.file_identity(candidate))==identity){if(found!=null&&!found.equal(candidate))throw new IOError.INVALID_DATA("Ambiguous rename identity");found=candidate;}
                if(found==null)throw new FileError.CONFLICT("A renamed item was removed or replaced. Keep the journal and remaining .majoris-rename files for manual recovery.");
                originals.add(original);temporary.add(staging);current.add(found);identities.add(identity);
            }
            // Evacuate all names first, preserving swaps and cycles. A second
            // interruption is recoverable from the same fixed path journal.
            for(int i=0;i<current.size;i++)if(!current[i].equal(temporary[i])){
                if((yield OperationManager.file_identity(current[i]))!=identities[i])throw new FileError.CONFLICT("Rename recovery input changed");
                yield current[i].move_async(temporary[i],FileCopyFlags.NONE,Priority.DEFAULT,token,null);metadata.relocate(current[i],temporary[i]);current[i]=temporary[i];
            }
            yield DurableFiles.flush(originals[0].get_parent(),token,false);
            for(int i=0;i<current.size;i++){
                if((yield OperationManager.file_identity(current[i]))!=identities[i])throw new FileError.CONFLICT("Rename recovery input changed");
                yield current[i].move_async(originals[i],FileCopyFlags.NONE,Priority.DEFAULT,token,null);metadata.relocate(current[i],originals[i]);
            }
            yield DurableFiles.flush(originals[0].get_parent(),token,false);clear();
        }
    }
}
