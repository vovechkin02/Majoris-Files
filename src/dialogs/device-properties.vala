namespace MajorisFiles {
    public class DevicePropertiesDialog : Adw.PreferencesDialog {
        public DeviceInfo? information;
        public Adw.PreferencesPage general = new Adw.PreferencesPage();
        public Adw.PreferencesPage hardware = new Adw.PreferencesPage();
        Place place;
        DeviceInformationProvider provider;
        VolumeMonitor monitor;
        ulong[] handlers;
        ulong provider_handler;
        Cancellable token = new Cancellable();
        uint generation;
        bool stopped;
        FileMonitor? tape_monitor;
        uint refresh_source;
        Gee.ArrayList<Adw.PreferencesGroup> groups = new Gee.ArrayList<Adw.PreferencesGroup>();
        Adw.NavigationPage hardware_page;
        public DevicePropertiesDialog(Place place, DeviceInformationProvider? provider = null) {
            this.place=place;this.provider=provider??DeviceInfoProvider.get_default();
            title=_("Properties");content_width=560;content_height=620;search_enabled=false;
            general.title=_("General");add(general);
            var toolbar=new Adw.ToolbarView();toolbar.add_top_bar(new Adw.HeaderBar());toolbar.content=hardware;hardware_page=new Adw.NavigationPage(toolbar,_("Hardware Details"));
            monitor=VolumeMonitor.get();
            weak DevicePropertiesDialog self=this;
            handlers={monitor.mount_added.connect(()=>{if(self!=null)self.schedule();}),monitor.mount_removed.connect(()=>{if(self!=null)self.schedule();}),monitor.mount_changed.connect(()=>{if(self!=null)self.schedule();}),monitor.volume_added.connect(()=>{if(self!=null)self.schedule();}),monitor.volume_removed.connect(()=>{if(self!=null)self.schedule();}),monitor.volume_changed.connect(()=>{if(self!=null)self.schedule();}),monitor.drive_connected.connect(()=>{if(self!=null)self.schedule();}),monitor.drive_disconnected.connect(()=>{if(self!=null)self.schedule();}),monitor.drive_changed.connect(()=>{if(self!=null)self.schedule();})};
            provider_handler=this.provider.changed.connect(()=>{if(self!=null)self.schedule();});
            if(place.tape_sysfs!="")try {tape_monitor=File.new_for_path(Path.get_dirname(place.tape_sysfs)).monitor_directory(FileMonitorFlags.NONE);tape_monitor.changed.connect(()=>{if(self!=null)self.schedule();});}catch(Error e){}
            closed.connect(stop);
            schedule();
        }
        void schedule() { if(stopped)return;token.cancel();if(refresh_source!=0)return;refresh_source=Idle.add(()=>{refresh_source=0;refresh.begin();return Source.REMOVE;}); }
        public async void refresh() {
            if(stopped)return;token.cancel();token=new Cancellable();var current=token;uint request=++generation;
            // Clear stale media/storage immediately while new metadata is loading.
            clear();clear_hardware();var loading=new Adw.PreferencesGroup();loading.add(new PropertiesInformationRow(_("Status"),_("Loading…")));general.add(loading);groups.add(loading);
            try {var result=yield provider.query(place,current);if(!stopped&&!current.is_cancelled()&&request==generation)render(result);}
            catch(Error e) {if(!stopped&&!current.is_cancelled()&&request==generation){var result=new DeviceInfo();result.name=place.label;result.status=_("Unavailable");render(result);}}
        }
        void clear() { var window=get_root() as Gtk.Window;if(window!=null)window.set_focus(null); foreach(var group in groups)general.remove(group);groups.clear(); }
        Adw.PreferencesGroup group(string title) {var result=new Adw.PreferencesGroup();result.title=title;general.add(result);groups.add(result);return result;}
        static void row(Adw.PreferencesGroup group,string title,string value) {if(value!="")group.add(new PropertiesInformationRow(title,value));}
        static void size_row(Adw.PreferencesGroup group,string title,uint64? value) {if(value!=null)row(group,title,Paths.size(value));}
        public void render(DeviceInfo info) {
            clear(); information=info;
            var heading=group("");var identity=new Gtk.Box(Gtk.Orientation.HORIZONTAL,12);
            var icon=new Gtk.Image.from_gicon(info.display_icon(place.icon??new ThemedIcon(place.icon_name),Gtk.IconTheme.get_for_display(get_display())));icon.pixel_size=48;
            var name=new Gtk.Label(info.name);name.xalign=0;name.wrap=true;name.wrap_mode=Pango.WrapMode.WORD_CHAR;name.max_width_chars=34;name.hexpand=true;name.selectable=true;name.add_css_class("heading");identity.append(icon);identity.append(name);heading.add(identity);
            var information=group(_("Information"));row(information,_("Type"),info.type_name());row(information,_("Status"),info.status);
            if(!info.connected){announce(_("Device disconnected"),Gtk.AccessibleAnnouncementPriority.MEDIUM);rebuild_hardware(info);return;}
            row(information,_("Filesystem"),info.filesystem);row(information,_("Mount point"),info.mount_point);
            row(information,info.optical?_("Disc label"):_("Volume label"),info.label);
            if(info.read_only!=null)row(information,_("Read only"),info.read_only?_("Yes"):_("No"));
            if(info.category==DeviceCategory.TAPE_DRIVE){row(information,_("Access"),_("Sequential storage"));var refresh=new Adw.ActionRow();refresh.title=_("Refresh");refresh.activatable=true;refresh.activated.connect(schedule);information.add(refresh);}
            row(information,_("Media type"),info.media_description());
            if(info.media_presence!=MediaPresence.UNKNOWN||info.media_removable==true)row(information,_("Media"),info.media_identity.presence_description(info.category));
            if(info.blank!=null&&info.blank)row(information,_("Disc status"),_("Blank"));
            if(info.optical) {
                bool filesystem_data=info.mounted&&info.blank!=true&&!info.audio_cd&&!(info.audio_tracks!=null&&info.audio_tracks>0&&info.data_tracks==0);
                if(info.media_presence!=MediaPresence.ABSENT&&(info.audio_tracks!=null||info.data_tracks!=null||info.media_size!=null||(filesystem_data&&info.capacity!=null))) {
                    var media=group(_("Disc Information"));
                    if(info.audio_tracks!=null)row(media,_("Audio tracks"),info.audio_tracks.to_string());
                    if(info.data_tracks!=null)row(media,_("Data tracks"),info.data_tracks.to_string());
                    size_row(media,_("Reported media size"),info.media_size);
                    if(filesystem_data)size_row(media,_("Recorded data"),info.used_estimated?null:info.used);
                    if(filesystem_data)size_row(media,_("Filesystem capacity"),info.capacity);
                }
            } else if(info.category!=DeviceCategory.TAPE_DRIVE&&(info.capacity!=null||info.volume_size!=null)) {
                var storage=group(_("Storage"));size_row(storage,_("Capacity"),info.capacity);
                if(info.capacity==null)size_row(storage,_("Volume size"),info.volume_size);
                if(info.show_usage){var bar=new Gtk.ProgressBar();bar.fraction=(double)info.used/(double)info.capacity;bar.margin_start=12;bar.margin_end=12;bar.margin_top=8;bar.margin_bottom=8;bar.update_property(Gtk.AccessibleProperty.LABEL,_("Used storage"),-1);var usage_row=new Adw.PreferencesRow();usage_row.selectable=false;usage_row.activatable=false;usage_row.child=bar;storage.add(usage_row);}
                if(info.usage_allowed){size_row(storage,info.used_estimated?_("Used (estimated)"):_("Used"),info.used);size_row(storage,_("Available"),info.available);}
            }
            if(info.has_hardware){var summary=group(_("Hardware"));row(summary,_("Connection"),info.connection);row(summary,_("Device type"),info.hardware_type);row(summary,_("Model"),info.model);row(summary,_("Supported media"),info.supported_media());var details=new Adw.ActionRow();details.title=_("Hardware Details");details.activatable=true;details.add_suffix(new Gtk.Image.from_icon_name("go-next-symbolic"));details.activated.connect(()=>push_subpage(hardware_page));summary.add(details);}
            rebuild_hardware(info);
        }
        void identifier(Adw.PreferencesGroup group,string title,string value) {
            if(value=="")return;
            var item=new PropertiesInformationRow(title,value);
            var copy=new Gtk.Button.from_icon_name("edit-copy-symbolic");copy.tooltip_text=_("Copy")+" "+title;copy.valign=Gtk.Align.CENTER;
            attach_copy(copy,get_clipboard(),value);item.add_suffix(copy);group.add(item);
        }
        static void attach_copy(Gtk.Button button,Gdk.Clipboard clipboard,string value){button.clicked.connect(()=>clipboard.set_text(value));}
        Gee.ArrayList<Adw.PreferencesGroup> hardware_groups = new Gee.ArrayList<Adw.PreferencesGroup>();
        void clear_hardware(){foreach(var group in hardware_groups)hardware.remove(group);hardware_groups.clear();}
        Adw.PreferencesGroup hardware_section(string title){var group=new Adw.PreferencesGroup();group.title=title;hardware.add(group);hardware_groups.add(group);return group;}
        void rebuild_hardware(DeviceInfo info) {
            clear_hardware();
            if(!info.connected){row(hardware_section(_("Device")),_("Status"),_("Disconnected"));return;}
            if(info.vendor!=""||info.model!=""||info.serial!=""||info.revision!=""||info.connection!=""||info.media_compatibility.length>0){
                var device=hardware_section(_("Device"));
                identifier(device,_("Manufacturer"),info.vendor);identifier(device,_("Model"),info.model);identifier(device,_("Serial number"),info.serial);identifier(device,_("Revision"),info.revision);identifier(device,_("Connection"),info.connection);identifier(device,_("Supported media"),info.supported_media());
            }
            if(info.device!=""||info.block_object!=""||info.drive_object!=""||info.backing_file!=""||info.backing_object!=""||info.partition_uuid!=""||info.partition_scheme!=""||info.physical_size!=null||info.volume_size!=null||info.media_size!=null){
                var storage=hardware_section(_("Storage"));
                identifier(storage,_("Device path"),info.device);identifier(storage,_("Backing file"),info.backing_file);identifier(storage,_("Backing block object"),info.backing_object);identifier(storage,_("Block object"),info.block_object);identifier(storage,_("Drive object"),info.drive_object);identifier(storage,_("Partition UUID"),info.partition_uuid);identifier(storage,_("Partition scheme"),info.partition_scheme);size_row(storage,_("Physical device size"),info.physical_size);size_row(storage,_("Reported media size"),info.media_size);size_row(storage,_("Volume size"),info.volume_size);
            }
            if(info.uuid!=""||info.mount_point!=""||info.filesystem!=""||info.read_only!=null){
                var filesystem=hardware_section(_("Filesystem"));identifier(filesystem,_("Filesystem UUID"),info.uuid);identifier(filesystem,_("Mount point"),info.mount_point);row(filesystem,_("Filesystem"),info.filesystem);if(info.read_only!=null)row(filesystem,_("Read only"),info.read_only?_("Yes"):_("No"));
            }
        }
        void stop() {if(stopped)return;stopped=true;if(tape_monitor!=null){tape_monitor.cancel();tape_monitor=null;}token.cancel();generation++;if(refresh_source!=0){Source.remove(refresh_source);refresh_source=0;}foreach(var id in handlers)monitor.disconnect(id);handlers={};if(provider_handler!=0){provider.disconnect(provider_handler);provider_handler=0;}}
        protected override void dispose(){stop();base.dispose();}
    }
}
