namespace MajorisFiles {
    // State is keyed by the authenticated app ID from xdg-desktop-portal and is
    // never exposed through the backend's D-Bus interface.
    public class ChooserState : Object {
        MetadataStore metadata;
        string prefix;
        public ChooserState(MetadataStore metadata, string application_id) {
            this.metadata = metadata;
            prefix = application_id == "" ? "" : "chooser:" + Checksum.compute_for_string(ChecksumType.SHA256, application_id) + ":";
        }
        public new string get(string key, string fallback = "") {
            return prefix == "" ? fallback : metadata.state(prefix + key, fallback);
        }
        public new void set(string key, string value) {
            if (prefix != "") metadata.set_state(prefix + key, value);
        }
        public int dimension(string key, int fallback, int minimum, int maximum) {
            int value;
            return int.try_parse(get(key), out value) ? value.clamp(minimum, maximum) : fallback;
        }
        public void apply(ChooserOptions options) {
            var uri = get(options.save ? "save-location" : "open-location");
            if (!options.initial_provided && options.initial.equal(File.new_for_path(Environment.get_home_dir())) && uri != "") options.initial = File.new_for_uri(uri);
        }
    }
}
