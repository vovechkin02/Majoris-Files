using MajorisFiles;
int main(string[] args) {
    if (args.length != 7) return 2;
    var configuration = File.new_for_path(args[3]);
    var fixture = configuration.get_parent();
    if (fixture == null || fixture.get_parent().get_path() != "/tmp" || !fixture.get_basename().has_prefix("majoris-samba-visibility-") ||
        !File.new_for_path(args[1]).has_prefix(fixture) || !File.new_for_path(args[2]).has_prefix(fixture)) return 3;
    try {
        string text; FileUtils.get_contents(configuration.get_path(), out text);
        foreach (var directory in new string[] {"private", "state", "cache", "lock", "pid"})
            if (!text.contains("= " + fixture.get_child(directory).get_path() + "\n")) return 4;
        if (text.contains("include =") || text.contains("/etc/samba")) return 5;
    }
    catch (Error e) { return 6; }
    var loop = new MainLoop(); int result = 1;
    var policy = new ShareVisibility(args[1], args[2], args[3], args[4]);
    uint uid = uint.parse(args[5]);
    run.begin(policy, uid, args[6], (obj, res) => { try { run.end(res); result = 0; } catch (Error e) { stderr.printf("%s\n", e.message); } loop.quit(); });
    loop.run(); return result;
}
async void run(ShareVisibility policy, uint uid, string action) throws Error {
    assert(yield policy.supported());
    if (action == "hide") { yield policy.set_hidden("fixture", uid, true); assert(yield policy.hidden("fixture", uid)); }
    else if (action == "show") { yield policy.set_hidden("fixture", uid, false); assert(!(yield policy.hidden("fixture", uid))); }
    else if (action == "refuse") {
        bool refused = false; try { yield policy.set_hidden("fixture", uid, false); } catch (Error e) { refused = true; }
        assert(refused);
    }
    else assert_not_reached();
}
