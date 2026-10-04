namespace MajorisFiles {
    public delegate void Callback();
    public errordomain FileError {
        INVALID, CONFLICT, INTEGRITY, UNSUPPORTED
    }
    public class Paths : Object {
        public static File parse(string value)
        {
            if (value == "~")
                return File.new_for_path(Environment.get_home_dir());
            if (value.has_prefix("~/"))
                return File.new_for_path(Path.build_filename(Environment.get_home_dir(), value.substring(2)));
            return File.new_for_commandline_arg(value);
        }
        public static bool valid_name(string name)
        {
            return name.length > 0 && name != "." && name != ".." && !name.contains("/") && name.validate();
        }
        public static int natural_compare(string a, string b)
        {
            return strcmp(a.casefold().collate_key_for_filename(), b.casefold().collate_key_for_filename());
        }
        public static string size(uint64 bytes)
        {
            return format_size(bytes, FormatSizeFlags.IEC_UNITS);
        }
        public static uint64 max_file_size(string filesystem)
        {
            if (filesystem == "vfat" || filesystem == "fat" || filesystem == "msdos")
                return 4294967295;
            return uint64.MAX;
        }
        public static uint64 split_size(uint64 total, uint64 count) throws Error
        {
            if (count == 0 || total == 0 || count > total)
                throw new FileError.INVALID("Invalid number of parts");
            return total / count + (total % count == 0 ? 0 : 1);
        }
        public static string part_name(string name, uint index)
        {
            return "%s.part%03u".printf(name, index);
        }
    }
}
