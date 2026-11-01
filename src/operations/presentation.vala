namespace MajorisFiles {
    // Stable rows observe individual jobs. Recovery uses the same durable
    // manager state as the existing window actions, never a second backend.
    class OperationJobRow : Gtk.Box {
        Job job;
        OperationManager manager;
        Gtk.Label message=new Gtk.Label("");
        Gtk.ProgressBar progress=new Gtk.ProgressBar();
        Gtk.Button cancel=new Gtk.Button.with_label(_("Cancel"));
        Gtk.Button retry=new Gtk.Button.with_label(_("Retry Remaining Items"));
        ulong handler;
        public OperationJobRow(Job job,OperationManager manager) {
            Object(orientation:Gtk.Orientation.VERTICAL,spacing:6);this.job=job;this.manager=manager;
            margin_start=12;margin_end=12;margin_top=8;margin_bottom=8;
            message.wrap=true;message.wrap_mode=Pango.WrapMode.WORD_CHAR;message.xalign=0;message.selectable=true;append(message);
            if(job.recovery_action!=""){
                var action=new Gtk.Button.with_label(job.recovery_action=="recover-rename"?_("Review…"):_("Recover…"));
                action.action_name="win."+job.recovery_action;append(action);
            }else{
                append(progress);append(cancel);append(retry);
                cancel.clicked.connect(()=>job.cancellable.cancel());retry.clicked.connect(retry_job);
            }
            handler=job.notify.connect(refresh);refresh();
        }
        void refresh() {
            string text=job.title;
            if(job.current!="")text=job.title+"\n"+job.current;
            if(job.error!="")text=job.error;
            if(job.cancelled)text=_("Cancelled · ")+job.current;
            message.label=text;
            progress.fraction=job.progress.clamp(0,1);
            cancel.sensitive=!job.done;
            retry.visible=job.can_retry;
            retry.sensitive=!job.retrying;
        }
        void retry_job(){var parent=get_root() as Gtk.Window;if(parent==null)return;manager.retry.begin(job,parent,(o,r)=>{try{manager.retry.end(r);}catch(Error e){Dialogs.error(parent,e.message);}});}
        protected override void dispose(){if(handler!=0){job.disconnect(handler);handler=0;}base.dispose();}
    }
    public class FileOperationsView : Gtk.Box {
        OperationManager manager;
        Gtk.ScrolledWindow scroll=new Gtk.ScrolledWindow();
        Gtk.Label empty=new Gtk.Label(_("No current file operations"));
        ulong handler;
        public FileOperationsView(OperationManager manager) {
            Object(orientation:Gtk.Orientation.VERTICAL,spacing:8);this.manager=manager;
            var title=new Gtk.Label(_("File Operations"));title.add_css_class("heading");append(title);
            empty.margin_start=16;empty.margin_end=16;empty.margin_top=12;empty.margin_bottom=12;append(empty);
            var sorted=new Gtk.SortListModel(manager.jobs,new Gtk.CustomSorter((a,b)=>{bool first=((Job)a).recovery_action!="",second=((Job)b).recovery_action!="";return first==second?0:first?1:-1;}));
            var jobs=new Gtk.ListBox();jobs.selection_mode=Gtk.SelectionMode.NONE;
            bind_jobs(jobs,sorted,manager);
            scroll.min_content_width=340;scroll.max_content_height=440;scroll.propagate_natural_height=true;scroll.child=jobs;append(scroll);
            handler=manager.jobs.items_changed.connect(refresh);refresh();
        }
        static void bind_jobs(Gtk.ListBox jobs,Gtk.SortListModel sorted,OperationManager manager){
            jobs.bind_model(sorted,(obj)=>new OperationJobRow((Job)obj,manager));
            jobs.set_header_func((row,before)=>{

                // The model index, rather than display text, identifies sections.
                var job=(Job)sorted.get_item((uint)row.get_index());bool previous=false;
                if(before!=null)previous=((Job)sorted.get_item((uint)before.get_index())).recovery_action!="";
                bool recovery=job.recovery_action!="";
                if(before==null||previous!=recovery){var heading=new Gtk.Label(recovery?_("Recovery Available"):_("Current operations"));heading.halign=Gtk.Align.START;heading.add_css_class("heading");heading.margin_top=8;row.set_header(heading);}else row.set_header(null);
            });
        }
        void refresh(){uint count=manager.jobs.get_n_items();empty.visible=count==0;scroll.visible=count>0;scroll.min_content_height=((int)count*160).clamp(0,440);}
        protected override void dispose(){if(handler!=0){manager.jobs.disconnect(handler);handler=0;}base.dispose();}
    }
}
