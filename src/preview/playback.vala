namespace MajorisFiles {
    public class IsolatedPlayback : Object {
        [CCode(cname="majoris_playback_new",cheader_filename="src/preview/playback.h")]
        extern static Gtk.MediaStream create(Subprocess process,bool audio_output);
        [CCode(cname="majoris_playback_close",cheader_filename="src/preview/playback.h")]
        public extern static void close(Gtk.MediaStream stream);
        [CCode(cname="majoris_playback_audio_bytes",cheader_filename="src/preview/playback.h")]
        public extern static uint64 audio_bytes(Gtk.MediaStream stream);
        public static Gtk.MediaStream open(FileItem item,Cancellable token,bool audio_output=true) throws Error {
            token.set_error_if_cancelled();
            if(!item.file.is_native()||Paths.is_symlink(item.info)||item.info.get_file_type()!=FileType.REGULAR)throw new FileError.UNSUPPORTED("Media playback requires a materialised local regular file");
            var bwrap=Environment.find_program_in_path("bwrap");if(bwrap==null)throw new FileError.UNSUPPORTED("Media playback requires bubblewrap");
            string helper=PREVIEW_HELPER_PATH;
            try{var sibling=Path.build_filename(Path.get_dirname(FileUtils.read_link("/proc/self/exe")),"majoris-files-preview-helper");if(FileUtils.test(sibling,FileTest.IS_EXECUTABLE))helper=sibling;}catch(Error ignored){}
            string[] args={bwrap,"--unshare-all","--die-with-parent","--new-session","--clearenv","--setenv","HOME","/tmp","--setenv","LANG","C.UTF-8","--setenv","GST_REGISTRY","/tmp/gst-registry.bin","--ro-bind","/usr","/usr","--ro-bind","/lib","/lib","--proc","/proc","--dev","/dev","--tmpfs","/tmp","--dir","/etc"};
            if(FileUtils.test("/lib64",FileTest.IS_DIR))foreach(var arg in new string[]{"--ro-bind","/lib64","/lib64"})args+=arg;
            if(FileUtils.test("/etc/alternatives",FileTest.IS_DIR))foreach(var arg in new string[]{"--ro-bind","/etc/alternatives","/etc/alternatives"})args+=arg;
            foreach(var arg in new string[]{"--setenv","OPENBLAS_NUM_THREADS","1","--setenv","OMP_NUM_THREADS","2"})args+=arg;
            if(FileUtils.test("/etc/ld.so.cache",FileTest.IS_REGULAR))foreach(var arg in new string[]{"--ro-bind","/etc/ld.so.cache","/etc/ld.so.cache"})args+=arg;
            foreach(var arg in new string[]{"--ro-bind",helper,"/helper","--ro-bind",item.file.get_path(),"/input","--","/helper","media-play","/input"})args+=arg;
            var process=new Subprocess.newv(args,SubprocessFlags.STDIN_PIPE|SubprocessFlags.STDOUT_PIPE|SubprocessFlags.STDERR_SILENCE);
            var stream=create(process,audio_output);
            token.cancelled.connect(()=>close(stream));
            return stream;
        }
    }
}
