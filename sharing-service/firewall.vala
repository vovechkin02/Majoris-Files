namespace MajorisFiles {
    public class SharingFirewall : Object {
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
                throw new IOError.NOT_SUPPORTED("The supported firewalld service is not active. Existing system firewall policy was left unchanged.");
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
