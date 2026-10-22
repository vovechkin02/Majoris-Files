namespace MajorisFiles {
    public class DurableFiles : Object {
        [CCode(cname = "majoris_sync_tree", cheader_filename = "src/operations/durability.h")]
        extern static bool sync_native(string path, Cancellable token, bool recursive) throws Error;
        [CCode(cname = "majoris_exchange", cheader_filename = "src/operations/durability.h")]
        public extern static bool exchange(string target, string staging) throws Error;
        public static async void flush(File file, Cancellable token, bool recursive = true) throws Error {
            if (!file.is_native()) throw new IOError.NOT_SUPPORTED("This backend does not expose local durability synchronization");
            Error? failure = null;
            SourceFunc resume = flush.callback;
            new Thread<void*>("sync-replacement", () => {
                try { sync_native(file.get_path(), token, recursive); } catch (Error e) { failure = e; }
                Idle.add((owned)resume); return null;
            });
            yield;
            if (failure != null) throw failure;
        }
        public static File staging(ReplacementRecord record) {
            return record.backup.get_parent().get_child(record.backup.get_basename().replace(".majoris-backup-", ".majoris-stage-"));
        }
        public static async void copy_attributes(File original, File edited, Cancellable token) throws Error {
            Error? failure = null; SourceFunc resume = copy_attributes.callback;
            new Thread<void*>("preserve-image-attributes", () => {
                try {
                    // copy_attributes(ALL_METADATA) also attempts read-only
                    // standard::size on some GIO backends. Copy writable file
                    // metadata explicitly; image metadata is preserved by the
                    // decoder before this filesystem step.
                    var attributes = original.query_info("unix::mode,unix::uid,unix::gid,time::modified,time::modified-usec,time::access,time::access-usec,xattr::*", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, token);
                    edited.set_attributes_from_info(attributes, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, token);
                }
                catch (Error e) { failure = e; }
                Idle.add((owned)resume); return null;
            });
            yield; if (failure != null) throw failure;
        }
        public static async string snapshot(File root, Cancellable? cancellation = null) throws Error {
            var token = cancellation ?? new Cancellable();
            var queue = new Gee.ArrayQueue<File>(); queue.offer(root);
            var values = new Gee.TreeMap<string, string>();
            while (!queue.is_empty) {
                var file = queue.poll(); token.set_error_if_cancelled();
                var info = yield file.query_info_async("standard::name,standard::type,standard::is-symlink,standard::symlink-target,standard::size,id::file,etag::value,time::modified,time::modified-usec", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                string id = yield OperationManager.file_identity(file);
                if (id == "") throw new IOError.NOT_SUPPORTED("This backend cannot validate replacement identities");
                values[root.equal(file) ? "" : root.get_relative_path(file)] = new Variant("(ssttss)", id, info.get_etag() ?? "", (uint64)info.get_size(), info.get_attribute_uint64("time::modified") * 1000000 + info.get_attribute_uint32("time::modified-usec"), Paths.is_symlink(info) && info.has_attribute("standard::symlink-target") ? info.get_symlink_target() : "", info.get_file_type().to_string()).print(true);
                if (values.size > 1000000) throw new IOError.NO_SPACE("Replacement validation exceeds the resource limit");
                if (info.get_file_type() == FileType.DIRECTORY && !Paths.is_symlink(info)) {
                    var children = yield file.enumerate_children_async("standard::name", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                    try {
                        while (true) {
                            var batch = yield children.next_files_async(128, Priority.LOW, token); if (batch == null) break;
                            foreach (var child in batch) queue.offer(file.get_child(child.get_name()));
                        }
                    }
                    catch (Error e) { try { yield children.close_async(Priority.LOW, null); } catch (Error ignored) {} throw e; }
                    yield children.close_async(Priority.LOW, null);
                }
            }
            var digest = new Checksum(ChecksumType.SHA256);
            foreach (var key in values.keys) { digest.update(key.data, key.length); digest.update("\0".data, 1); digest.update(values[key].data, values[key].length); digest.update("\0".data, 1); }
            return digest.get_string();
        }
    }
}
