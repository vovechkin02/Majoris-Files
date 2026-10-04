namespace MajorisFiles {
    public class ThumbnailService : Object {
        public bool enabled = true;
        public async Gdk.Texture? texture(FileItem item, Cancellable token) throws Error {
            if (!enabled || !item.file.is_native() || !item.mime.has_prefix("image/") || item.bytes > 32 * 1024 * 1024)
                return null;
            string cache = Path.build_filename(Environment.get_user_cache_dir(), "thumbnails", "normal");
            DirUtils.create_with_parents(cache, 0700);
            string filename = Checksum.compute_for_string(ChecksumType.MD5, item.file.get_uri()) + ".png";
            var cached = File.new_for_path(Path.build_filename(cache, filename));
            string modified = item.info.get_attribute_uint64("time::modified").to_string();
            Gdk.Pixbuf? image = null;
            try {
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
                var stream = yield item.file.read_async(Priority.LOW, token);
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
