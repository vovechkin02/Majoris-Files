namespace MajorisFiles {
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
        Gee.ArrayList<ThumbnailProvider> providers = new Gee.ArrayList<ThumbnailProvider>();
        public ThumbnailService()
        {
            providers.add(new ImageThumbnail());
            providers.add(new PdfThumbnail());
        }
        public void register_provider(ThumbnailProvider provider)
        {
            providers.insert(0, provider);
        }
        public async Gdk.Texture? texture(FileItem item, Cancellable token) throws Error {
            if (!enabled || !item.file.is_native() || item.info.get_is_symlink())
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
                var cached_info = yield cached.query_info_async("standard::size,standard::type", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, token);
                if(cached_info.get_file_type() != FileType.REGULAR || cached_info.get_size() > 1024 * 1024)
                    throw new FileError.INVALID("Invalid thumbnail cache entry");
                var stream = yield cached.read_async(Priority.LOW, token);
                var decoded = yield new Gdk.Pixbuf.from_stream_async(stream, token);
                yield stream.close_async(Priority.LOW, null);
                if (decoded.get_option("tEXt::Thumb::URI") == item.file.get_uri() && decoded.get_option("tEXt::Thumb::MTime") == modified)
                    image = decoded;
            }
            catch (IOError.CANCELLED e) {
                throw e;
            }
            catch (Error e) {}
            if (image == null)
            {
                var encoded_preview = yield provider.render(item, token);
                var stream = new MemoryInputStream.from_bytes(encoded_preview);
                image = yield new Gdk.Pixbuf.from_stream_at_scale_async(stream, 128, 128, true, token);
                yield stream.close_async(Priority.LOW, null);
                uint8[] encoded;
                image.save_to_buffer(out encoded, "png", "tEXt::Thumb::URI", item.file.get_uri(), "tEXt::Thumb::MTime", modified);
                yield cached.replace_contents_async(encoded, null, false, FileCreateFlags.PRIVATE, token, null);
            }
            return Gdk.Texture.for_pixbuf(image);
        }
    }
}
