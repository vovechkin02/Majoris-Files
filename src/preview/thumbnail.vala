namespace MajorisFiles {
    public class ConflictThumbnails : Object {
        public static void attach(Adw.AlertDialog dialog, File source, File destination, MetadataStore metadata)
        {
            var token = new Cancellable();
            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 24);
            box.homogeneous = true;
            dialog.extra_child = box;
            dialog.closed.connect(() => token.cancel());
            foreach (var file in new File[] {source, destination}) {
                var column = new Gtk.Box(Gtk.Orientation.VERTICAL, 6);
                var image = new Gtk.Picture(); image.height_request = 96;
                image.content_fit = Gtk.ContentFit.CONTAIN;
                image.alternative_text = file.equal(source) ? _("Source preview") : _("Destination preview");
                column.append(image);
                var label = new Gtk.Label(file.equal(source) ? _("Source") : _("Destination"));
                column.append(label); box.append(column);
                load.begin(file, image, metadata, token);
            }
        }
        static async void load(File file, Gtk.Picture picture, MetadataStore metadata, Cancellable token)
        {
            try {
                var info = yield file.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                // Honor the normal remote-download and thumbnail policy. An unavailable
                // thumbnail leaves the labeled comparison without delaying the prompt.
                var texture = yield new ThumbnailService(metadata).texture(new FileItem(file, info), token);
                if (!token.is_cancelled() && texture != null) picture.paintable = texture;
            }
            catch (Error e) {} // Preview failure never changes the conflict decision.
        }
    }
    public class VideoThumbnail : Object, ThumbnailProvider {
        public bool supports(FileItem item) { return item.mime.has_prefix("video/") && item.bytes <= 1024UL * 1024 * 1024; }
        public async Bytes render(FileItem item, Cancellable token) throws Error
        {
            return yield PreviewSandbox.run(item, "video-thumbnail", {}, token);
        }
    }
    public interface ThumbnailProvider : Object {
        public abstract bool supports(FileItem item);
        public abstract async Bytes render(FileItem item, Cancellable token) throws Error;
    }
    public class ImageThumbnail : Object, ThumbnailProvider {
        public bool supports(FileItem item)
        {
            return item.mime.has_prefix("image/") && item.bytes <= 32 * 1024 * 1024;
        }
        public async Bytes render(FileItem item, Cancellable token) throws Error
        {
            return yield PreviewSandbox.run(item, "image-thumbnail", {}, token);
        }
    }
    public class PdfThumbnail : Object, ThumbnailProvider {
        public bool supports(FileItem item)
        {
            return item.mime == "application/pdf" && item.bytes <= 128 * 1024 * 1024;
        }
        public async Bytes render(FileItem item, Cancellable token) throws Error
        {
            return yield PreviewSandbox.run(item, "pdf-thumbnail", {}, token);
        }
    }
    public class ThumbnailService : Object {
        public bool enabled = true;
        MetadataStore? metadata;
        static uint remote_active;
        Gee.ArrayList<ThumbnailProvider> providers = new Gee.ArrayList<ThumbnailProvider>();
        public ThumbnailService(MetadataStore? metadata = null)
        {
            this.metadata = metadata;
            providers.add(new ImageThumbnail());
            providers.add(new PdfThumbnail());
            providers.add(new FontThumbnail());
            providers.add(new VideoThumbnail());
        }
        public void register_provider(ThumbnailProvider provider)
        {
            providers.insert(0, provider);
        }
        public async Gdk.Texture? texture(FileItem item, Cancellable token) throws Error {
            string policy = metadata == null ? "Local" : metadata.state("thumbnail-policy", "Local");
            if (!enabled || policy == "Never" || (!item.file.is_native() && policy != "All") || item.info.get_is_symlink())
                return null;
            uint limit = 8;
            if(metadata != null)
                uint.try_parse(metadata.state("remote-thumbnail-limit", "8"), out limit);
            limit = limit.clamp(1, 128);
            if(!item.file.is_native() && (!item.info.has_attribute("standard::size") || item.bytes > (uint64)limit * 1024 * 1024))
                return null;
            ThumbnailProvider? provider = null;
            foreach(var candidate in providers)
                if(candidate.supports(item))
                {
                    provider = candidate;
                    break;
                }
            if(provider == null)
                return null;
            string cache = Path.build_filename(Environment.get_user_cache_dir(), "thumbnails", "normal");
            DirUtils.create_with_parents(cache, 0700);
            string filename = Checksum.compute_for_string(ChecksumType.MD5, item.file.get_uri()) + ".png";
            var cached = File.new_for_path(Path.build_filename(cache, filename));
            string modified = item.info.get_attribute_uint64("time::modified").to_string();
            Gdk.Pixbuf? image = null;
            try {
                if(!item.info.has_attribute("time::modified"))
                    throw new FileError.INVALID("Thumbnail cache requires a modification time");
                var cached_info = yield cached.query_info_async("standard::size,standard::type,standard::is-symlink", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                if(cached_info.get_file_type() != FileType.REGULAR || cached_info.get_size() > 1024 * 1024)
                    throw new FileError.INVALID("Invalid thumbnail cache entry");
                var cached_item = new FileItem(cached, cached_info);
                var sanitized = yield PreviewSandbox.run(cached_item, "thumbnail-cache", {item.file.get_uri(), modified}, token);
                var stream = new MemoryInputStream.from_bytes(sanitized);
                image = yield new Gdk.Pixbuf.from_stream_async(stream, token);
                yield stream.close_async(Priority.LOW, null);
            }
            catch (IOError.CANCELLED e) {
                throw e;
            }
            catch (Error e) {}
            if (image == null)
            {
                Bytes encoded_preview;
                if(item.file.is_native())
                    encoded_preview = yield provider.render(item, token);
                else encoded_preview = yield remote_preview(provider, item, cache, (uint64)limit * 1024 * 1024, token);
                var stream = new MemoryInputStream.from_bytes(encoded_preview);
                image = yield new Gdk.Pixbuf.from_stream_at_scale_async(stream, 128, 128, true, token);
                yield stream.close_async(Priority.LOW, null);
                uint8[] encoded;
                image.save_to_buffer(out encoded, "png", "tEXt::Thumb::URI", item.file.get_uri(), "tEXt::Thumb::MTime", modified);
                yield cached.replace_contents_async(encoded, null, false, FileCreateFlags.PRIVATE, token, null);
            }
            return Gdk.Texture.for_pixbuf(image);
        }
        async Bytes remote_preview(ThumbnailProvider provider, FileItem item, string cache, uint64 limit, Cancellable token) throws Error
        {
            while(remote_active >= 2)
            {
                Timeout.add(50, () => { remote_preview.callback();
                                        return Source.REMOVE;
                    });
                yield;
                token.set_error_if_cancelled();
            }
            remote_active++;
            var transfer_token = new Cancellable();
            ulong cancellation = token.cancelled.connect(() => transfer_token.cancel());
            bool timed_out = false;
            uint timeout = Timeout.add_seconds(30, () => { timed_out = true;
                                                           transfer_token.cancel();
                                                           return Source.REMOVE;
                });
            var temporary = File.new_for_path(Path.build_filename(cache, ".remote-" + Uuid.string_random()));
            InputStream? input = null;
            OutputStream? output = null;
            try {
                token.set_error_if_cancelled();
                output = yield temporary.create_async(FileCreateFlags.PRIVATE, Priority.LOW, transfer_token);
                input = yield item.file.read_async(Priority.LOW, transfer_token);
                uint8[] buffer = new uint8[65536];
                uint64 total = 0;
                while(true)
                {
                    ssize_t count = yield input.read_async(buffer, Priority.LOW, transfer_token);
                    if(count == 0)
                        break;
                    total += count;
                    if(total > limit)
                        throw new FileError.UNSUPPORTED("Remote thumbnail exceeds the download limit");
                    size_t written;
                    yield output.write_all_async(buffer[0:count], Priority.LOW, transfer_token, out written);
                }
                yield input.close_async(Priority.LOW, null);
                input = null;
                yield output.close_async(Priority.LOW, null);
                output = null;
                var info = yield temporary.query_info_async(FileItem.ATTRIBUTES, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                info.set_content_type(item.mime);
                info.set_display_name(item.name);
                var result = yield provider.render(new FileItem(temporary, info), token);
                yield temporary.delete_async(Priority.LOW, null);
                return result;
            }
            catch(Error e) {
                if(input != null)
                    try {
                        yield input.close_async(Priority.LOW, null);
                    }
                    catch(Error ignored) {}
                if(output != null)
                    try {
                        yield output.close_async(Priority.LOW, null);
                    }
                    catch(Error ignored) {}
                try {
                    yield temporary.delete_async(Priority.LOW, null);
                }
                catch(Error ignored) {}
                throw e;
            }
            finally {
                if(!timed_out)
                    Source.remove(timeout);
                token.disconnect(cancellation);
                remote_active--;
            }
        }
    }
    public class FontThumbnail : Object, ThumbnailProvider {
        public bool supports(FileItem item)
        {
            return new FontPreview().supports(item) && item.bytes <= 32 * 1024 * 1024;
        }
        public async Bytes render(FileItem item, Cancellable token) throws Error
        {
            return yield PreviewSandbox.run(item, "font", {}, token);
        }
    }
}
