namespace MajorisFiles {
    public class FileClipboard : Object {
        public Gee.ArrayList<File> files = new Gee.ArrayList<File>();
        public bool cut;
        public static void publish(Gdk.Clipboard clipboard, Gee.ArrayList<File> files, bool cut)
        {
            if(files.size == 0)
                return;
            clipboard.set_content(provider(files, cut));
        }
        public static Gdk.ContentProvider provider(Gee.ArrayList<File> files, bool cut = false)
        {
            var uris = new StringBuilder();
            foreach(var file in files)
                uris.append(file.get_uri() + "\r\n");
            var copied = (cut ? "cut\n" : "copy\n") + uris.str.replace("\r\n", "\n");
            var value = Value(typeof(Gdk.FileList));
            value.set_boxed(new Gdk.FileList.from_array(files.to_array()));
            return new Gdk.ContentProvider.union({
                new Gdk.ContentProvider.for_value(value),
                new Gdk.ContentProvider.for_bytes("x-special/gnome-copied-files", new Bytes(copied.data)),
                new Gdk.ContentProvider.for_bytes("text/uri-list", new Bytes(uris.str.data))
            });
        }
        public static FileClipboard parse(string content, bool copied_format) throws Error
        {
            if(content.length > 4 * 1024 * 1024 || !content.validate())
                throw new FileError.INVALID("Invalid file clipboard data");
            var result = new FileClipboard();
            var lines = content.split("\n");
            int first = 0;
            if(copied_format)
            {
                if(lines.length == 0 || (lines[0] != "copy" && lines[0] != "cut"))
                    throw new FileError.INVALID("Invalid clipboard operation");
                result.cut = lines[0] == "cut";
                first = 1;
            }
            var seen = new Gee.HashSet<string>();
            for(int i = first; i < lines.length; i++)
            {
                var uri = lines[i].strip();
                if(uri == "" || uri.has_prefix("#"))
                    continue;
                if(Uri.parse_scheme(uri) == null || result.files.size >= 10000)
                    throw new FileError.INVALID("Invalid clipboard file URI");
                if(seen.add(uri))
                    result.files.add(File.new_for_uri(uri));
            }
            return result;
        }
        public static async FileClipboard read(Gdk.Clipboard clipboard) throws Error
        {
            var formats = clipboard.get_formats();
            if(formats.contain_mime_type("x-special/gnome-copied-files") || formats.contain_mime_type("text/uri-list"))
            {
                unowned string mime;
                var stream = yield clipboard.read_async({"x-special/gnome-copied-files", "text/uri-list"}, Priority.DEFAULT, null, out mime);
                if(stream == null)
                    throw new FileError.INVALID("File clipboard is unavailable");
                var output = new ByteArray();
                try {
                    uint8[] buffer = new uint8[8192];
                    while(true)
                    {
                        var count = yield stream.read_async(buffer, Priority.DEFAULT, null);
                        if(count == 0)
                            break;
                        if(output.len + count > 4 * 1024 * 1024)
                            throw new FileError.INVALID("File clipboard is too large");
                        output.append(buffer[0 : count]);
                    }
                }
                catch(Error e) {
                    try {
                        yield stream.close_async(Priority.DEFAULT, null);
                    }
                    catch(Error close_error) {}
                    throw e;
                }
                yield stream.close_async(Priority.DEFAULT, null);
                output.append({0});
                return parse((string)output.data, mime == "x-special/gnome-copied-files");
            }
            var result = new FileClipboard();
            if(formats.contain_gtype(typeof(Gdk.FileList)))
            {
                var value = yield clipboard.read_value_async(typeof(Gdk.FileList), Priority.DEFAULT, null);
                if(value != null)
                {
                    var list = (Gdk.FileList)value.get_boxed();
                    foreach(var file in list.get_files())
                        result.files.add(file);
                }
            }
            return result;
        }
    }
}
