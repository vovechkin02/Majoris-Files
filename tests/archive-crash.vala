using MajorisFiles;
[CCode(cname="_exit",cheader_filename="unistd.h")]
extern void exit_now(int status);
int main(string[] args){
    if(args.length==4&&args[1]=="--child"){
        var root=File.new_for_path(args[2]);var inputs=new Gee.ArrayList<File>();inputs.add(root.get_child("payload"));
        var loop=new MainLoop();SevenZip.create.begin(inputs,root.get_child("Backup.7z"),1024*1024,0,null,new Job("Publication crash"),(phase)=>{if(phase==args[3])exit_now(77);},(obj,res)=>{try{SevenZip.create.end(res);}catch(Error e){stderr.printf("%s\n",e.message);}exit_now(78);});loop.run();return 1;
    }
    Test.init(ref args);Test.add_func("/archive/process-crash-publication",()=>{var loop=new MainLoop();run.begin((obj,res)=>{try{run.end(res);}catch(Error e){error("%s",e.message);}loop.quit();});loop.run();});return Test.run();
}
async void run() throws Error {
    string executable=FileUtils.read_link("/proc/self/exe");
    foreach(var phase in new string[]{"staged","prepared","part","entry-point","committed"}){
        var root=File.new_for_path(DirUtils.make_tmp("majoris-archive-crash-XXXXXX"));uint8[] data=new uint8[3*1024*1024];
        for(int i=0;i<data.length;i++)data[i]=(uint8)(i%251);
        yield root.get_child("payload").replace_contents_async(data,null,false,FileCreateFlags.NONE,null,null);
        var child=new Subprocess.newv({executable,"--child",root.get_path(),phase},SubprocessFlags.STDOUT_SILENCE|SubprocessFlags.STDERR_PIPE);yield child.wait_async(null);assert(child.get_exit_status()==77);
        var first=root.get_child("Backup.7z.001"),marker=root.get_child("Backup.7z.majoris-incomplete");
        if(phase=="committed"){assert(first.query_exists()&&!marker.query_exists());yield SevenZip.verify(first,null,new Job("Verify complete publication"));}
        else{
            assert(phase=="staged"?!marker.query_exists():marker.query_exists());
            assert(phase=="entry-point"?first.query_exists():!first.query_exists());
            bool refused=false;try{yield SevenZip.verify(first,null,new Job("Refuse incomplete publication"));}catch(Error e){refused=true;}assert(refused);
        }
        yield OperationManager.remove_tree(root,new Cancellable());
    }
}
