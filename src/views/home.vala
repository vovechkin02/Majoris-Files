namespace MajorisFiles {
    // Native activity source shared by collection refresh and initial navigation.
    public class ActivityFiles : Object {
        public static Gee.ArrayList<File> recent() {
            var files = new Gee.ArrayList<File>();
            foreach (var info in Gtk.RecentManager.get_default().get_items())
                files.add(File.new_for_uri(info.get_uri()));
            return files;
        }
    }
}
