using MajorisFiles;
int main(string[] args)
{
    var loop = new MainLoop();
    int result = 1;
    bool search=args.length>1&&args[1]=="--search";
    int count = search?10000:args.length > 1 ? int.parse(args[1]) : 10000;
    if (count < 1 || count > 100000) return 2;
    if(search)search_benchmark.begin((obj,res)=>{try{search_benchmark.end(res);result=0;}catch(Error e){stderr.printf("%s\n",e.message);}loop.quit();});
    else run.begin(count, (obj, res) => { try { run.end(res); result = 0; } catch (Error e) { stderr.printf("%s\n", e.message); } loop.quit(); });
    loop.run(); return result;
}
class CompleteFixtureIndex : Object, SearchCoverage {
    File root;
    public CompleteFixtureIndex(File root){this.root=root;}
    public async bool covers(File location,bool recursive,Cancellable token) throws Error {token.set_error_if_cancelled();return root.equal(location);}
}
async void search_benchmark() throws Error {
    var temporary=File.new_for_path(DirUtils.make_tmp("majoris-search-benchmark-XXXXXX"));var indexed=temporary.get_child("indexed"),unindexed=temporary.get_child("unindexed");
    DirUtils.create(indexed.get_path(),0700);DirUtils.create(unindexed.get_path(),0700);FileUtils.set_contents(unindexed.get_child("needle-extra.txt").get_path(),"fixture");
    var connection=yield Tsparql.SparqlConnection.new_async(Tsparql.SparqlConnectionFlags.NONE,null,File.new_for_uri("resource:///org/freedesktop/tracker/nepomuk"),null);
    var insert=new StringBuilder("INSERT DATA { GRAPH tracker:FileSystem {");uint batch=0;
    for(int directory=0;directory<1000;directory++){
        var folder=indexed.get_child("folder-%04d".printf(directory));DirUtils.create(folder.get_path(),0700);
        for(int item=0;item<10;item++){
            string name=directory%100==0&&item==0?"needle.txt":"entry-%d.txt".printf(item);var file=folder.get_child(name);FileUtils.set_contents(file.get_path(),"fixture");
            insert.append("<%s> a nfo:FileDataObject; nie:url \"%s\"; nfo:fileName \"%s\" .\n".printf(file.get_uri(),file.get_uri(),name));
            if(++batch==500){insert.append("} }");yield connection.update_async(insert.str,null);insert=new StringBuilder("INSERT DATA { GRAPH tracker:FileSystem {");batch=0;}
        }
    }
    var controller=new SearchController();controller.indexed=new IndexedSearchProvider(connection,new CompleteFixtureIndex(indexed));var query=new SearchQuery();query.text="needle";var roots=new Gee.ArrayList<File>();roots.add(indexed);var found=new Gee.HashSet<string>();controller.found.connect((item)=>found.add(item.file.get_uri()));
    uint heartbeats=0;uint timer=Timeout.add(1,()=>{heartbeats++;return Source.CONTINUE;});
    int64 start=get_monotonic_time();yield controller.search_roots(roots,query);double index_seconds=(get_monotonic_time()-start)/1000000.0;assert(found.size==10&&controller.scanned==0);
    found.clear();controller.exhaustive=true;start=get_monotonic_time();yield controller.search_roots(roots,query);double exhaustive_seconds=(get_monotonic_time()-start)/1000000.0;assert(found.size==10&&controller.scanned==1001);
    stdout.printf("10,000 indexed files / 1,001 directories: index %.3f s / 0 scans; exhaustive %.3f s / %u scans\n",index_seconds,exhaustive_seconds,controller.scanned);
    found.clear();controller.exhaustive=false;roots.add(unindexed);yield controller.search_roots(roots,query);assert(found.size==11&&controller.scanned==1);stdout.printf("Mixed roots: 11 deduplicated results / 1 unindexed directory scanned\n");
    roots.remove(unindexed);found.clear();query.text="entry";start=get_monotonic_time();yield controller.search_roots(roots,query);assert(found.size==9990&&controller.scanned==0);stdout.printf("Large indexed result set: %d results in %.3f s; %u main-loop heartbeats across searches\n",found.size,(get_monotonic_time()-start)/1000000.0,heartbeats);
    Source.remove(timer);assert(heartbeats>0);connection.close();yield OperationManager.remove_tree(temporary,new Cancellable());
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
