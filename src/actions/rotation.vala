namespace MajorisFiles {
    public class ImageRotation : Object {
        [CCode(cname = "geteuid", cheader_filename = "unistd.h")]
        extern static uint effective_uid();
        public static bool supports(FileItem item) {
            return item.file.is_native() && !item.directory && !Paths.is_symlink(item.info) &&
                item.mime in new string[] {"image/png", "image/jpeg"} && item.bytes <= 256 * 1024 * 1024 &&
                (!item.info.has_attribute("access::can-write") || item.info.get_attribute_boolean("access::can-write")) &&
                item.info.has_attribute("unix::uid") && item.info.get_attribute_uint32("unix::uid") == effective_uid();
        }
        public static async void rotate(owned FileItem item, bool clockwise, OperationManager operations, Gtk.Window? parent = null, bool allow_lossy = false) throws Error {
            var job = new Job(clockwise ? _("Rotate Image Clockwise") : _("Rotate Image Counterclockwise"));
            operations.jobs.append(job);
            File? temporary = null; string temporary_identity = "";
            try {
                var info = yield item.file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable);
                item = new FileItem(item.file, info);
                if (!supports(item)) throw new IOError.NOT_SUPPORTED("Persistent rotation requires a writable, owned local JPEG or PNG image");
                string expected = yield DurableFiles.snapshot(item.file, job.cancellable);
                string format = item.mime == "image/jpeg" ? "jpeg" : "png";
                job.current = _("Rendering the saved image in the isolated helper");
                Bytes rendered;
                try { rendered = yield PreviewSandbox.run(item, "image-rotate", {clockwise ? "90" : "270", format, "lossless"}, job.cancellable); }
                catch (Error e) {
                    job.cancellable.set_error_if_cancelled();
                    if (format != "jpeg") throw e;
                    bool accepted = allow_lossy;
                    if (!accepted && parent != null)
                        accepted = yield Dialogs.confirm(parent, _("Lossless rotation is unavailable"), _("The JPEG edges may not align with its compression blocks. Re-encoding can reduce image quality. The original bytes will be kept for Undo."), _("Re-encode JPEG"));
                    if (!accepted) throw new IOError.NOT_SUPPORTED("JPEG cannot be rotated losslessly without trimming; the original was left unchanged");
                    rendered = yield PreviewSandbox.run(item, "image-rotate", {clockwise ? "90" : "270", format, "lossy"}, job.cancellable);
                }
                temporary = item.file.get_parent().get_child(".majoris-edited-" + Uuid.string_random());
                yield temporary.replace_contents_async(rendered.get_data(), null, false, FileCreateFlags.PRIVATE, job.cancellable, null);
                temporary_identity = yield OperationManager.file_identity(temporary);
                yield DurableFiles.copy_attributes(item.file, temporary, job.cancellable);
                var attributes = new FileInfo(); int64 now = get_real_time();
                attributes.set_attribute_uint64("time::modified", (uint64)(now / 1000000));
                attributes.set_attribute_uint32("time::modified-usec", (uint32)(now % 1000000));
                yield temporary.set_attributes_async(attributes, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, job.cancellable, null);
                job.current = _("Publishing the rotated image and preserving Undo data");
                yield operations.replace_existing(temporary, item.file, false, job, true, expected);
                job.progress = 1;
            }
            catch (Error e) { job.error = e.message; job.cancelled = e is IOError.CANCELLED; throw e; }
            finally {
                job.done = true;
                if (temporary != null && temporary_identity != "") {
                    cleanup.begin(temporary, temporary_identity);
                }
            }
        }
        static async void cleanup(File file, string identity) {
            if ((yield OperationManager.file_identity(file)) == identity)
                try { yield file.delete_async(Priority.LOW, null); } catch (Error e) {}
        }
    }
}
