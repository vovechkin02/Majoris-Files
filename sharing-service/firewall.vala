namespace MajorisFiles {
    public class SharingFirewall : Object {
        public static bool empty_nft_ruleset(string text) throws Error {
            var parser = new Json.Parser(); parser.load_from_data(text);
            if (parser.get_root().get_node_type() != Json.NodeType.OBJECT) throw new IOError.INVALID_DATA("Invalid nftables status");
            var root = parser.get_root().get_object();
            if (!root.has_member("nftables") || root.get_member("nftables").get_node_type() != Json.NodeType.ARRAY) throw new IOError.INVALID_DATA("Missing nftables status");
            foreach (var entry in root.get_array_member("nftables").get_elements()) {
                if (entry.get_node_type() != Json.NodeType.OBJECT) throw new IOError.INVALID_DATA("Invalid nftables entry");
                foreach (var key in entry.get_object().get_members()) if (key != "metainfo") return false;
            }
            return true;
        }
        public static async string backend(DBusConnection bus) throws Error {
            var owner = yield bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", new Variant("(s)", SERVICE), new VariantType("(b)"), DBusCallFlags.NONE, 3000, null);
            if (owner.get_child_value(0).get_boolean()) return "firewalld";
            // No generic rule writer: only classify other policies, never change
            // them or install/activate a firewall as a side effect of sharing.
            if (!FileUtils.test("/usr/sbin/nft", FileTest.IS_EXECUTABLE)) return "unknown";
            var process = new Subprocess.newv({"/usr/sbin/nft", "--json", "list", "ruleset"}, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
            uint timeout = Timeout.add_seconds(3, () => { process.force_exit(); return Source.REMOVE; });
            Source? timer = MainContext.default().find_source_by_id(timeout);
            try {
                uint8[] bytes = new uint8[4*1024*1024+1]; size_t count;
                yield process.get_stdout_pipe().read_all_async(bytes[0:bytes.length-1], Priority.LOW, null, out count);
                if (count == bytes.length-1) return "unmanaged";
                yield process.wait_check_async(null); bytes[count]=0;
                if (!empty_nft_ruleset((string)bytes)) return "unmanaged";
                foreach (var file in new string[] {"/proc/net/ip_tables_names", "/proc/net/ip6_tables_names"}) {
                    string contents;
                    try { FileUtils.get_contents(file, out contents); if (contents.strip() != "") return "unmanaged"; }
                    catch (GLib.FileError.NOENT e) {}
                }
                return "none";
            }
            catch (Error e) { return "unknown"; }
            finally { process.force_exit(); if (timer != null && !timer.is_destroyed()) Source.remove(timeout); }
        }
        const string SERVICE = "org.fedoraproject.FirewallD1";
        const string ROOT = "/org/fedoraproject/FirewallD1";
        public const string MARKER = "Majoris Files owned SMB policy v1";
        public static bool owns_policy(Variant settings, bool require_marker = true)
        {
            var description = settings.lookup_value("description", VariantType.STRING);
            var target = settings.lookup_value("target", VariantType.STRING);
            var services = settings.lookup_value("services", new VariantType("as"));
            var egress = settings.lookup_value("egress_zones", new VariantType("as"));
            var priority = settings.lookup_value("priority", VariantType.INT32);
            if ((require_marker && (description == null || description.get_string() != MARKER)) || priority == null || priority.get_int32() != 32767 || target == null || target.get_string() != "CONTINUE" ||
                services == null || services.n_children() != 1 || services.get_child_value(0).get_string() != "samba" ||
                egress == null || egress.n_children() != 1 || egress.get_child_value(0).get_string() != "HOST") return false;
            var ingress = settings.lookup_value("ingress_zones", new VariantType("as"));
            if (ingress != null)
                for (size_t i = 0; i < ingress.n_children(); i++)
                    if (!(ingress.get_child_value(i).get_string() in new string[] {"home", "work"})) return false;
            foreach (var key in new string[] {"ports", "protocols", "source_ports", "rich_rules", "forward_ports"}) {
                var value = settings.lookup_value(key, null);
                if (value != null && value.n_children() != 0) return false;
            }
            var masquerade = settings.lookup_value("masquerade", VariantType.BOOLEAN);
            return masquerade == null || !masquerade.get_boolean();
        }
        public static async void configure(DBusConnection bus, bool enabled) throws Error
        {
            // Do not auto-activate or install a firewall daemon.
            var owner = yield bus.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", new Variant("(s)", SERVICE), new VariantType("(b)"), DBusCallFlags.NONE, 5000, null);
            if (!owner.get_child_value(0).get_boolean())
            {
                if ((yield backend(bus)) == "none") return;
                throw new IOError.NOT_SUPPORTED("No supported firewall manager is active. An alternative or unknown administrator policy was left unchanged; Files did not install or activate a firewall.");
            }
            var path = yield bus.call(SERVICE, ROOT + "/config", SERVICE + ".config", "getPolicyByName", new Variant("(s)", "majoris-files-sharing"), new VariantType("(o)"), DBusCallFlags.NO_AUTO_START, 5000, null);
            string object_path = path.get_child_value(0).get_string();
            var response = yield bus.call(SERVICE, object_path, SERVICE + ".config.policy", "getSettings", null, new VariantType("(a{sv})"), DBusCallFlags.NO_AUTO_START, 5000, null);
            var settings = response.get_child_value(0);
            if (!owns_policy(settings))
                throw new IOError.PERMISSION_DENIED("The Majoris firewall policy was modified by an administrator; Files will not change it");
            var current = yield bus.call(SERVICE, ROOT, SERVICE + ".policy", "getPolicySettings", new Variant("(s)", "majoris-files-sharing"), new VariantType("(a{sv})"), DBusCallFlags.NO_AUTO_START, 5000, null);
            if (!owns_policy(current.get_child_value(0), false))
                throw new IOError.PERMISSION_DENIED("The running Majoris firewall policy was modified; Files will not change it");
            string[] zones = enabled ? new string[] {"home", "work"} : new string[] {};
            var runtime = new VariantBuilder(VariantType.VARDICT);
            runtime.add("{sv}", "ingress_zones", new Variant.strv(zones));
            yield bus.call(SERVICE, ROOT, SERVICE + ".policy", "setPolicySettings", new Variant("(s@a{sv}i)", "majoris-files-sharing", runtime.end(), 0), null, DBusCallFlags.NO_AUTO_START, 5000, null);
            var updated = new VariantBuilder(VariantType.VARDICT);
            var iterator = settings.iterator(); string key; Variant value;
            while (iterator.next("{sv}", out key, out value)) if (key != "ingress_zones") updated.add("{sv}", key, value);
            updated.add("{sv}", "ingress_zones", new Variant.strv(zones));
            yield bus.call(SERVICE, object_path, SERVICE + ".config.policy", "update", new Variant("(@a{sv})", updated.end()), null, DBusCallFlags.NO_AUTO_START, 5000, null);
        }
    }
}
