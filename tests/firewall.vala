using MajorisFiles;
Variant policy(string[] ingress, string[] services, string target, int priority, string marker)
{
    var settings = new VariantBuilder(VariantType.VARDICT);
    settings.add("{sv}", "description", new Variant.string(marker));
    settings.add("{sv}", "target", new Variant.string(target));
    settings.add("{sv}", "priority", new Variant.int32(priority));
    settings.add("{sv}", "ingress_zones", new Variant.strv(ingress));
    settings.add("{sv}", "egress_zones", new Variant.strv({"HOST"}));
    settings.add("{sv}", "services", new Variant.strv(services));
    return settings.end();
}
int main(string[] args)
{
    Test.init(ref args);
    Test.add_func("/firewall/owned-policy-scope", () => {
        assert(SharingFirewall.owns_policy(policy({}, {"samba"}, "CONTINUE", 32767, SharingFirewall.MARKER)));
        assert(SharingFirewall.owns_policy(policy({"home", "work"}, {"samba"}, "CONTINUE", 32767, SharingFirewall.MARKER)));
        assert(!SharingFirewall.owns_policy(policy({"public"}, {"samba"}, "CONTINUE", 32767, SharingFirewall.MARKER)));
        assert(!SharingFirewall.owns_policy(policy({"home"}, {"samba", "ssh"}, "CONTINUE", 32767, SharingFirewall.MARKER)));
        assert(!SharingFirewall.owns_policy(policy({"home"}, {"samba"}, "ACCEPT", 32767, SharingFirewall.MARKER)));
        assert(!SharingFirewall.owns_policy(policy({"home"}, {"samba"}, "CONTINUE", -1, SharingFirewall.MARKER)));
        assert(!SharingFirewall.owns_policy(policy({"home"}, {"samba"}, "CONTINUE", 32767, "Administrator policy")));
    });
    Test.add_func("/sharing/client-status-privacy", () => {
        try {
            var output = SharingClients.filter("""{"sessions":{"1":{"username":"allowed"},"2":{"username":"private"}},"tcons":{"a":{"service":"Public","machine":"client-a","session_id":"1"},"b":{"service":"Secret","machine":"client-b","session_id":"2"}},"open_files":{"secret":"private-path"}}""", "Public");
            var parser = new Json.Parser(); parser.load_from_data(output);
            var rows = parser.get_root().get_array();
            assert(rows.get_length() == 1);
            assert(rows.get_object_element(0).get_string_member("user") == "allowed");
            assert(!output.contains("private") && !output.contains("client-b") && !output.contains("Secret"));
            assert(SharingClients.filter("{}", "Public") == "[]");
            bool invalid = false;
            try { SharingClients.filter("[]", "Public"); } catch (Error e) { invalid = true; }
            assert(invalid);
        }
        catch (Error e) { error("%s", e.message); }
    });
    Test.add_func("/firewall/empty-versus-unmanaged", () => {
        try {
            assert(SharingFirewall.empty_nft_ruleset("{\"nftables\":[{\"metainfo\":{\"version\":\"fixture\"}}]}"));
            assert(!SharingFirewall.empty_nft_ruleset("{\"nftables\":[{\"table\":{\"name\":\"administrator\"}}]}"));
            bool invalid = false; try { SharingFirewall.empty_nft_ruleset("{}"); } catch (Error e) { invalid = true; } assert(invalid);
        }
        catch (Error e) { error("%s", e.message); }
    });
    return Test.run();
}
