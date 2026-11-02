namespace MajorisFiles {
    // Stable rows observe individual jobs. Recovery uses the same durable
    // manager state as the existing window actions, never a second backend.
    [GtkTemplate (ui = "/com/majoris/files/ui/operation-row.ui")]
    class OperationJobRow : Gtk.Box {
        private bool template_disposing;
        Job job;
        OperationManager manager;
        [GtkChild] private unowned Gtk.Label message;
        [GtkChild] private unowned Gtk.ProgressBar progress;
        [GtkChild] private unowned Gtk.Button cancel;
        [GtkChild] private unowned Gtk.Button retry;
        [GtkChild] private unowned Gtk.Label summary;
        [GtkChild] private unowned Gtk.Label statistics;
        [GtkChild] private unowned Gtk.FlowBox controls;
        [GtkChild] private unowned Gtk.Button pause;
        [GtkChild] private unowned Gtk.DrawingArea graph;
        JobState announced_state = JobState.QUEUED;
        uint timer;
        ulong handler;
        [GtkChild] private unowned Gtk.Button recovery_button;
        [GtkChild] private unowned Gtk.Expander details;
        public OperationJobRow(Job job,OperationManager manager) {
            this.job=job;this.manager=manager;
            bool recovery = job.recovery_action != "";
            recovery_button.visible = recovery;
            progress.visible = summary.visible = controls.visible = details.visible = !recovery;
            if (recovery) {
                var action = recovery_button;
                action.label = job.recovery_action == "recover-rename" ? _("Review…") : _("Recover…");
                action.clicked.connect(() => {
                    var app = GLib.Application.get_default() as Gtk.Application;
                    if (app == null) return;
                    bool found = false; foreach (var candidate in app.get_windows()) if (candidate is FilesWindow) found = true;
                    if (!found) app.activate_action("new-window", null);
                    foreach (var window in app.get_windows()) if (window is FilesWindow) { ((FilesWindow)window).activate_action("win." + job.recovery_action, null); return; }
                });
            }else{
                pause.clicked.connect(() => { if (job.can_resume) job.resume(); else job.request_pause(); });
                details.notify["expanded"].connect(details_changed);
                graph.set_draw_func((area, cr, width, height) => {
                    var color = area.get_color(); cr.set_source_rgba(color.red, color.green, color.blue, 0.8);
                    double peak = 1; foreach (var rate in job.history) peak = double.max(peak, rate);
                    for (int i = 0; i < job.history.size; i++) {
                        double x = (double)i / 119 * width, y = height - job.history[i] / peak * (height - 4);
                        if (i == 0) cr.move_to(x, y); else cr.line_to(x, y);
                    }
                    cr.stroke();
                });
                timer = Timeout.add(500, () => { if (get_mapped()) { refresh(); if (details.expanded) graph.queue_draw(); } if (job.done) { timer = 0; return Source.REMOVE; } return Source.CONTINUE; });
                cancel.clicked.connect(()=>job.cancellable.cancel());retry.clicked.connect(retry_job);
            }
            handler=job.notify.connect(job_changed);refresh();
        }
        void details_changed(Object object, ParamSpec parameter) {
            var details = (Gtk.Expander)object;
            details.label = details.expanded ? _("Fewer Details") : _("More Details");
        }
        void job_changed() { if (job.done) refresh(); }
        void refresh() {
            string text=job.title;

            if(job.error!="")text=job.error;
            if(job.cancelled)text=_("Cancelled · ")+job.current;
            message.label=text;
            progress.fraction=job.progress.clamp(0,1);
            string status;
            if (job.done) status = job.cancelled ? _("Cancelled") : job.error != "" ? _("Failed") : _("Completed");
            else if (job.state == JobState.FINALISING) status = _("Finalising…");
            else if (job.state == JobState.PAUSED) status = _("Paused");
            else if (job.state == JobState.PAUSING) status = _("Pausing at next file…");
            else if (job.state == JobState.WAITING_FOR_USER) status = _("Waiting for your response");
            else if (job.progress_known) status = "%d%%".printf((int)(job.progress * 100));
            else status = _("Calculating…");
            progress.text = status;
            if (job.state != announced_state) {
                if (get_mapped() && (job.done || job.state == JobState.WAITING_FOR_USER))
                    announce(job.title + ": " + status + (job.error == "" ? "" : " · " + job.error), Gtk.AccessibleAnnouncementPriority.MEDIUM);
                announced_state = job.state;
            }
            if (!job.done && !job.progress_known) progress.pulse();
            summary.label = job.source_description + (job.destination_description == "" ? "" : " → " + job.destination_description);
            if (job.items_total_known) summary.label = job.source_description + (job.destination_description == "" ? "" : " → " + job.destination_description) + "\n" + job.items_completed.to_string() + " / " + job.items_total.to_string() + _(" items");
            if (job.bytes_total_known && job.transfer_bytes) summary.label += "\n" + GLib.format_size(job.bytes_completed) + " / " + GLib.format_size(job.bytes_total);
            if (job.skipped_items > 0) summary.label += "\n" + job.skipped_items.to_string() + _(" items skipped");
            statistics.label = job.current + "\n" + _("Active time: ") + "%.0f s".printf(job.active_seconds);
            if (job.current_file_size > 0) statistics.label += "\n" + _("Current file: ") + GLib.format_size(job.current_file_completed) + " / " + GLib.format_size(job.current_file_size);
            graph.visible = job.transfer_bytes;
            if (job.transfer_bytes) statistics.label += "\n" + _("Speed: ") + GLib.format_size((uint64)job.bytes_per_second) + "/s";
            if (job.eta_seconds >= 0) statistics.label += "\n" + _("Time remaining: ") + "%.0f s".printf(job.eta_seconds);
            pause.visible = job.can_pause && !job.done;
            pause.tooltip_text = job.current_file_size > 0 ? _("Pause at a safe transfer checkpoint; other backends pause between files") : _("Pause between files");
            pause.sensitive = job.state != JobState.WAITING_FOR_USER && job.state != JobState.FINALISING && job.state != JobState.CALCULATING;
            pause.label = job.can_resume ? _("Resume") : _("Pause");
            controls.visible = !job.done || job.can_retry;
            cancel.visible = !job.done;
            cancel.sensitive=!job.done;
            retry.visible=job.can_retry;
            retry.sensitive=!job.retrying;
        }
        void retry_job(){var parent=get_root() as Gtk.Window;if(parent==null)return;manager.retry.begin(job,parent,(o,r)=>{try{manager.retry.end(r);}catch(Error e){Dialogs.error(parent,e.message);}});}
        protected override void dispose(){
            if (template_disposing) { base.dispose(); return; }
            template_disposing = true;
            if (timer != 0) { Source.remove(timer); timer = 0; }
            if (handler != 0) { job.disconnect(handler); handler = 0; }
            dispose_template(typeof(OperationJobRow));
            base.dispose();
        }
    }
    [GtkTemplate (ui = "/com/majoris/files/ui/file-operations-view.ui")]
    public class FileOperationsView : Gtk.Box {
        private bool template_disposing;
        OperationManager manager;
        [GtkChild]
        private unowned Gtk.ScrolledWindow scroll;
        [GtkChild]
        private unowned Gtk.Label empty;
        ulong handler;

        [GtkChild] private unowned Gtk.ListBox jobs;
        public FileOperationsView(OperationManager manager) {
            Object(); configure(manager);
        }
        public void configure(OperationManager manager) {
            this.manager=manager;

            var sorted=new Gtk.SortListModel(manager.jobs,new Gtk.CustomSorter((a,b)=>{bool first=((Job)a).recovery_action!="",second=((Job)b).recovery_action!="";if (first != second) return first ? 1 : -1; bool first_done=((Job)a).done, second_done=((Job)b).done; return first_done==second_done ? 0 : first_done ? 1 : -1;}));

            bind_jobs(jobs,sorted,manager);

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
        protected override void dispose(){
            if (template_disposing) { base.dispose(); return; }
            template_disposing = true;
            if (handler != 0) { manager.jobs.disconnect(handler); handler = 0; }
            dispose_template(typeof(FileOperationsView));
            base.dispose();
        }
    }
}

namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/file-operations.ui")]
    public class FileOperationsWindow : Adw.Window {
        private bool template_disposing;
        static construct { typeof(FileOperationsView).ensure(); }
        [GtkChild] private unowned FileOperationsView operations_view;

        [GtkChild] private unowned Adw.HeaderBar header;
        [GtkChild] private unowned Adw.ToolbarView toolbar;
        public FileOperationsWindow(OperationManager manager) {
            Object();

            operations_view.configure(manager);
            close_request.connect(() => { visible = false; application = null; return true; });
        }
        protected override void dispose() {
            if (!template_disposing) {
                template_disposing = true;
                content = null;
                dispose_template(typeof(FileOperationsWindow));
            }
            base.dispose();
        }
    }
}

namespace MajorisFiles {
    public class FileOperationsPresentation : Object {
        static FileOperationsWindow? window;
        static uint hiding;
        public static void completed(OperationManager manager) {
            if (hiding != 0) { Source.remove(hiding); hiding = 0; }
            if (window == null || !window.visible) return;
            for (uint i = 0; i < manager.jobs.get_n_items(); i++) {
                var job = (Job)manager.jobs.get_item(i);
                if (!job.done || job.error != "" || job.can_retry || job.recovery_action != "") return;
            }
            hiding = Timeout.add_seconds(4, () => { hiding = 0; if (window != null) { window.visible = false; window.application = null; } return Source.REMOVE; });
        }
        public static FileOperationsWindow get_window(OperationManager manager) {
            if (window == null) window = new FileOperationsWindow(manager);
            return window;
        }
        public static void show(OperationManager manager) {
            if (hiding != 0) { Source.remove(hiding); hiding = 0; }
            var progress = get_window(manager);
            progress.application = GLib.Application.get_default() as Gtk.Application;
            progress.present();
        }
    }
}
