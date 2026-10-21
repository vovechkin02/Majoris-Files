using MajorisFiles;
int main(string[] args)
{
    var loop = new MainLoop();
    int result = 1;
    int count = args.length > 1 ? int.parse(args[1]) : 10000;
    if (count < 1 || count > 100000) return 2;
    run.begin(count, (obj, res) => { try { run.end(res); result = 0; } catch (Error e) { stderr.printf("%s\n", e.message); } loop.quit(); });
    loop.run(); return result;
}
async void run(int count) throws Error
{
    var root = File.new_for_path(DirUtils.make_tmp("majoris-performance-XXXXXX"));
    for (int i = 0; i < count; i++) FileUtils.set_contents(root.get_child("entry-%06d.txt".printf(i)).get_path(), "");
    var model = new DirectoryModel();
    uint heartbeats = 0;
    uint timer = Timeout.add(1, () => { heartbeats++; return Source.CONTINUE; });
    int64 start = get_monotonic_time();
    yield model.open(root);
    int64 elapsed = get_monotonic_time() - start;
    Source.remove(timer);
    assert(model.items.get_n_items() == count && !model.loading && heartbeats > 0);
    stdout.printf("Enumerated %u entries in %.3f seconds; %u main-loop heartbeats\n", model.items.get_n_items(), elapsed / 1000000.0, heartbeats);
    string status; FileUtils.get_contents("/proc/self/status", out status);
    foreach (var line in status.split("\n")) if (line.has_prefix("VmRSS:")) stdout.printf("%s\n", line);
    model.cancel();
    yield OperationManager.remove_tree(root, new Cancellable());
}
