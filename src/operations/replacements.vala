namespace MajorisFiles {
    public class ReplacementRecord : Object {
        public string id = Uuid.string_random();
        public File target;
        public File backup;
        public string previous_identity;
        public string current_identity = "";
        public string phase = "prepared";
        public ReplacementRecord(File target, File backup, string previous_identity)
        {
            this.target = target;
            this.backup = backup;
            this.previous_identity = previous_identity;
        }
    }
    public class ReplacementJournal : Object {
        MetadataStore metadata;
        public Gee.ArrayList<ReplacementRecord> records = new Gee.ArrayList<ReplacementRecord>();
        public ReplacementJournal(MetadataStore metadata)
        {
            this.metadata = metadata;
            string saved = metadata.state("replacement-recovery-v1");
            if (saved == "" || saved.length > 4 * 1024 * 1024) return;
            try {
                var entries = Variant.parse(new VariantType("a(ssssss)"), saved);
                if (entries.n_children() > 10000) return;
                for (size_t i = 0; i < entries.n_children(); i++) {
                    var entry = entries.get_child_value(i);
                    var target = File.new_for_uri(entry.get_child_value(1).get_string());
                    var backup = File.new_for_uri(entry.get_child_value(2).get_string());
                    if (target.get_parent() == null || backup.get_parent() == null ||
                        !target.get_parent().equal(backup.get_parent()) || !backup.get_basename().has_prefix(".majoris-backup-"))
                        continue;
                    var record = new ReplacementRecord(target, backup, entry.get_child_value(3).get_string());
                    record.id = entry.get_child_value(0).get_string();
                    record.current_identity = entry.get_child_value(4).get_string();
                    record.phase = entry.get_child_value(5).get_string();
                    records.add(record);
                }
            }
            catch (Error e) { warning("Replacement recovery records could not be read: %s", e.message); }
        }
        void persist() throws Error
        {
            var entries = new VariantBuilder(new VariantType("a(ssssss)"));
            foreach (var record in records)
                entries.add("(ssssss)", record.id, record.target.get_uri(), record.backup.get_uri(), record.previous_identity, record.current_identity, record.phase);
            metadata.set_state_checked("replacement-recovery-v1", entries.end().print(true));
        }
        public async ReplacementRecord prepare(File target, File backup) throws Error
        {
            string identity = "guard2:" + (yield DurableFiles.snapshot(target));
            if (identity == "")
                throw new FileError.UNSUPPORTED("This backend cannot identify the previous destination safely for replacement recovery");
            var record = new ReplacementRecord(target, backup, identity);
            records.add(record);
            try { persist(); } catch (Error e) { records.remove(record); throw e; }
            return record;
        }
        public async void committed(ReplacementRecord record) throws Error
        {
            record.current_identity = yield OperationManager.file_identity(record.target);
            record.phase = "committed";
            persist();
        }
        public async void staged(ReplacementRecord record, File staging) throws Error
        {
            record.current_identity = yield OperationManager.file_identity(staging);
            record.phase = "staged";
            persist();
        }
        public static async bool matches(ReplacementRecord record, File file) throws Error {
            if (record.previous_identity.has_prefix("guard2:")) {
                try { return record.previous_identity == "guard2:" + (yield DurableFiles.snapshot(file)); }
                catch (IOError.NOT_FOUND e) { return false; }
            }
            return (yield OperationManager.file_identity(file)) == record.previous_identity;
        }
        public void forget(ReplacementRecord record) throws Error
        {
            records.remove(record);
            persist();
        }
        public void history(ReplacementRecord record) throws Error { record.phase = "history"; persist(); }
        public async File restore(ReplacementRecord record, Cancellable token) throws Error
        {
            if (yield matches(record, record.target)) {
                var staging = DurableFiles.staging(record);
                string identity = yield OperationManager.file_identity(staging);
                if (identity != "") {
                    if (record.current_identity == "" || identity != record.current_identity)
                        throw new FileError.INTEGRITY("The original is intact. Unverified staged data was retained at " + staging.get_parse_name());
                    var retained = record.target.get_parent().get_child(record.target.get_basename() + " (unpublished replacement " + record.id + ")");
                    yield staging.move_async(retained, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token, null);
                }
                forget(record); return record.target;
            }
            File preserved = record.backup;
            if (!(yield matches(record, preserved))) {
                preserved = DurableFiles.staging(record);
                if (!(yield matches(record, preserved)))
                    throw new FileError.INTEGRITY("The preserved item is missing or has changed; it has not been touched");
            }
            File destination = record.target;
            for (uint i = 0; ; i++) {
                if (i > 10000) throw new FileError.CONFLICT("No free recovery filename was found");
                if (i > 0) destination = record.target.get_parent().get_child(record.target.get_basename() + " (recovered original %u)".printf(i));
                try {
                    yield destination.query_info_async("standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token);
                }
                catch (IOError.NOT_FOUND e) { break; }
            }
            // No overwrite: another writer winning the race produces an error.
            yield preserved.move_async(destination, FileCopyFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, token, null);
            forget(record);
            return destination;
        }
        public async void reconcile(Cancellable token) throws Error {
            var snapshot = new Gee.ArrayList<ReplacementRecord>(); snapshot.add_all(records);
            foreach (var record in snapshot) {
                token.set_error_if_cancelled();
                if (record.phase == "committed" && record.current_identity != "" &&
                    (yield OperationManager.file_identity(record.target)) == record.current_identity &&
                    (yield OperationManager.file_identity(record.backup)) == "" &&
                    (yield OperationManager.file_identity(DurableFiles.staging(record))) == "") forget(record);
            }
        }
    }
}
