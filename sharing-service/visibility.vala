namespace MajorisFiles {
    // A bounded registry overlay for an owned usershare. No caller-supplied
    // command, configuration path, account or arbitrary smb.conf parameter.
    public class ShareVisibility : Object {
        string state_dir;
        string usershares;
        string config;
        string tools;
        [CCode(cname = "geteuid", cheader_filename = "unistd.h")]
        extern static uint effective_uid();
        public ShareVisibility(string state_dir = "/var/lib/majoris-files/share-visibility", string usershares = "/var/lib/samba/usershares", string config = "/etc/samba/smb.conf", string tools = "/usr/bin") {
            this.state_dir = state_dir; this.usershares = usershares; this.config = config; this.tools = tools;
        }
        public static void validate_name(string name) throws Error {
            if (!Regex.match_simple("^[A-Za-z0-9_][A-Za-z0-9_ -]{0,79}$", name) || name.down() in new string[] {"global", "homes", "printers"})
                throw new IOError.INVALID_ARGUMENT("Invalid managed share name");
        }
        public static string acl(string value) throws Error {
            string[] denies = {}, allows = {};
            var entries = value.split(",");
            if (entries.length == 0 || entries.length > 256) throw new IOError.INVALID_DATA("Unsupported usershare ACL");
            foreach (var entry in entries) {
                if (!Regex.match_simple("^S-[0-9]+(-[0-9]+)+:[FRD]$", entry)) throw new IOError.NOT_SUPPORTED("Visibility requires an unambiguous SID-based usershare ACL");
                int colon = entry.last_index_of(":"); string sid = entry.substring(0, colon), level = entry.substring(colon + 1);
                string rule = sid + ":" + (level == "D" ? "DENIED/0/FULL" : "ALLOWED/0/" + (level == "R" ? "READ" : "FULL"));
                if (level == "D") denies += rule; else allows += rule;
            }
            return string.joinv(",", denies) + (denies.length > 0 && allows.length > 0 ? "," : "") + string.joinv(",", allows);
        }
        async string command(string program, string[] arguments, string? configuration = null) throws Error {
            string[] args = {Path.build_filename(tools, program)};
            if (program != "testparm") args += "--configfile=" + (configuration ?? config);
            foreach (var argument in arguments) args += argument;
            if (program == "testparm") args += config;
            var process = new Subprocess.newv(args, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE);
            uint timeout = Timeout.add_seconds(8, () => { process.force_exit(); return Source.REMOVE; });
            Source? timer = MainContext.default().find_source_by_id(timeout);
            bool error_done = false, waiting = false; string errors = "";
            bounded_output.begin(process.get_stderr_pipe(), (obj, res) => {
                try { errors = bounded_output.end(res); } catch (Error e) { errors = e.message; process.force_exit(); }
                error_done = true;
                if (waiting) Idle.add(() => { command.callback(); return Source.REMOVE; });
            });
            try {
                string output = yield bounded_output(process.get_stdout_pipe());
                yield process.wait_async(null);
                if (!error_done) { waiting = true; yield; }
                if (!process.get_successful()) throw new IOError.FAILED("Samba " + program + ": " + errors);
                return output;
            }
            finally { process.force_exit(); if (timer != null && !timer.is_destroyed()) Source.remove(timeout); }
        }
        async string security(string name, string path, string[] arguments) throws Error {
            // sharesec intentionally does not load dynamic usershares. Give only
            // this tool a private, bounded section while retaining the real
            // server's passdb/share-security database paths from its config.
            var temporary = File.new_for_path(Path.build_filename(state_dir, "security-" + Uuid.string_random() + ".conf"));
            string text = "[global]\ninclude = " + config + "\n[" + name + "]\npath = " + path + "\n";
            yield temporary.replace_contents_async(text.data, null, false, FileCreateFlags.PRIVATE, null, null);
            string[] args = {name}; foreach (var argument in arguments) args += argument;
            try { return yield command("sharesec", args, temporary.get_path()); }
            finally { try { temporary.delete(); } catch (Error ignored) {} }
        }
        static async string bounded_output(InputStream stream) throws Error {
            uint8[] bytes = new uint8[65537]; size_t count;
            yield stream.read_all_async(bytes[0:65536], Priority.LOW, null, out count);
            if (count == 65536) throw new IOError.NO_SPACE("Samba response exceeds the limit");
            bytes[count] = 0; return ((string)bytes).make_valid();
        }
        public async bool supported() throws Error {
            return (yield command("testparm", {"-s", "--parameter-name=registry shares"})).strip().down() == "yes";
        }
        static string canonical(string text, string name) throws Error {
            var file = new KeyFile(); file.load_from_data(text, text.length, KeyFileFlags.NONE);
            string[] keys = file.get_keys(name);
            var sorted = new Gee.TreeMap<string, string>();
            foreach (var key in keys) {
                if (!(key in new string[] {"path", "comment", "read only", "guest ok", "browseable"})) throw new IOError.PERMISSION_DENIED("Managed registry share has unfamiliar parameters");
                string value = file.get_string(name, key).strip();
                sorted[key] = key in new string[] {"read only", "guest ok", "browseable"} ? value.down() : value;
            }
            var result = new StringBuilder(); foreach (var key in sorted.keys) result.append(key + "=" + sorted[key] + "\n");
            return Checksum.compute_for_string(ChecksumType.SHA256, result.str);
        }
        async bool exists(string name) throws Error {
            foreach (var share in (yield command("net", {"conf", "listshares"})).split("\n")) if (share.strip().down() == name.down()) return true;
            return false;
        }
        File record_file(string name) { return File.new_for_path(Path.build_filename(state_dir, name.down() + ".json")); }
        Json.Object? record(string name, uint uid) throws Error {
            var file = record_file(name); FileInfo info;
            try { info = file.query_info("standard::type,standard::is-symlink,standard::size,unix::uid", FileQueryInfoFlags.NOFOLLOW_SYMLINKS); }
            catch (IOError.NOT_FOUND e) { return null; }
            if (info.get_file_type() != FileType.REGULAR || info.get_is_symlink() || info.get_size() > 65536 || info.get_attribute_uint32("unix::uid") != effective_uid()) throw new IOError.PERMISSION_DENIED("Invalid visibility ownership record");
            string text; FileUtils.get_contents(file.get_path(), out text);
            var parser = new Json.Parser(); parser.load_from_data(text);
            var object = parser.get_root().get_object();
            if (object.get_int_member("uid") != uid) throw new IOError.PERMISSION_DENIED("This managed share belongs to another account");
            return object;
        }
        public async bool hidden(owned string name, uint uid) throws Error {
            validate_name(name); name = name.down(); var saved = record(name, uid);
            if (saved == null) return false;
            if (!(yield exists(name))) return false;
            string definition = yield command("net", {"conf", "showshare", name});
            if (canonical(definition, name) != saved.get_string_member("definition")) throw new IOError.PERMISSION_DENIED("Share visibility was changed by an administrator");
            return true;
        }
        public async void set_hidden(owned string name, uint uid, bool hidden) throws Error {
            validate_name(name); name = name.down();
            if (!(yield supported())) throw new IOError.NOT_SUPPORTED("The Majoris Samba registry-share foundation is not enabled");
            DirUtils.create_with_parents(state_dir, 0700);
            var directory = File.new_for_path(state_dir).query_info("standard::type,standard::is-symlink,unix::uid,unix::mode", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            if (directory.get_file_type() != FileType.DIRECTORY || directory.get_is_symlink() || directory.get_attribute_uint32("unix::uid") != effective_uid() || (directory.get_attribute_uint32("unix::mode") & 0077) != 0) throw new IOError.PERMISSION_DENIED("Unsafe visibility state directory");
            var saved = record(name, uid);
            bool present = yield exists(name);
            if (present) {
                if (saved == null || !(yield this.hidden(name, uid))) throw new IOError.PERMISSION_DENIED("An administrator-owned registry share uses this name");
                string descriptor = yield security(name, saved.get_string_member("path"), {"--view"});
                if (Checksum.compute_for_string(ChecksumType.SHA256, descriptor) != saved.get_string_member("acl")) throw new IOError.PERMISSION_DENIED("The share security descriptor changed outside Files");
            }
            if (!hidden) {
                if (present) yield command("net", {"conf", "delshare", name});
                if (saved != null) yield record_file(name).delete_async(Priority.DEFAULT, null);
                return;
            }
            var source = File.new_for_path(Path.build_filename(usershares, name));
            var info = yield source.query_info_async("standard::type,standard::size,standard::is-symlink,unix::uid", FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null);
            if (info.get_file_type() != FileType.REGULAR || info.get_is_symlink() || info.get_size() > 65536 || info.get_attribute_uint32("unix::uid") != uid) throw new IOError.PERMISSION_DENIED("Visibility is restricted to an owned usershare");
            string contents; FileUtils.get_contents(source.get_path(), out contents);
            var values = new Gee.HashMap<string, string>();
            foreach (var line in contents.split("\n")) {
                if (line.strip() == "" || line.has_prefix("#")) continue;
                int equals = line.index_of("="); if (equals < 1) throw new IOError.INVALID_DATA("Invalid usershare definition");
                string key = line.substring(0, equals).strip();
                if (!(key in new string[] {"path", "comment", "usershare_acl", "guest_ok", "sharename"}) || values.has_key(key)) throw new IOError.NOT_SUPPORTED("Unfamiliar usershare settings were not changed");
                values[key] = line.substring(equals + 1).strip();
            }
            string? path = values["path"], rules = values["usershare_acl"], guest = values["guest_ok"];
            if (path == null || rules == null || !Path.is_absolute(path) || path.contains("\n") || path.contains("\r") || path.contains("%") || path.contains("#") || path.contains(";") || !(guest in new string[] {"y", "n"})) throw new IOError.NOT_SUPPORTED("This usershare cannot be represented by the bounded visibility policy");
            var folder = File.new_for_path(path).query_info("standard::type,standard::is-symlink,unix::uid", FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
            if (folder.get_file_type() != FileType.DIRECTORY || folder.get_is_symlink() || folder.get_attribute_uint32("unix::uid") != uid) throw new IOError.PERMISSION_DENIED("The usershare folder must belong to the caller");
            // Do not shadow an administrator's smb.conf share.
            if (!present && Regex.match_simple("(?im)^\\[\\s*" + Regex.escape_string(name) + "\\s*\\]\\s*$", yield command("testparm", {"-s"}))) throw new IOError.PERMISSION_DENIED("An administrator-defined share uses this name");
            string definition = "[" + name + "]\npath = " + path + "\ncomment = Majoris Files owned visibility v1\nread only = no\nguest ok = " + (guest == "y" ? "yes" : "no") + "\nbrowseable = no\n";
            yield security(name, path, {"--replace=" + acl(rules)});
            string descriptor = yield security(name, path, {"--view"});
            var data = new Json.Object(); data.set_int_member("uid", uid); data.set_string_member("path", path); data.set_string_member("definition", canonical(definition, name)); data.set_string_member("acl", Checksum.compute_for_string(ChecksumType.SHA256, descriptor));
            var node = new Json.Node(Json.NodeType.OBJECT); node.set_object(data); var generator = new Json.Generator(); generator.set_root(node);
            yield record_file(name).replace_contents_async(generator.to_data(null).data, null, false, FileCreateFlags.PRIVATE, null, null);
            var temporary = File.new_for_path(Path.build_filename(state_dir, "import-" + Uuid.string_random() + ".conf"));
            yield temporary.replace_contents_async(definition.data, null, false, FileCreateFlags.PRIVATE, null, null);
            try { yield command("net", {"conf", "import", temporary.get_path(), name}); }
            finally { try { temporary.delete(); } catch (Error ignored) {} }
        }
    }
}
