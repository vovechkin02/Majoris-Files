namespace MajorisFiles {
    [GtkTemplate (ui = "/com/majoris/files/ui/device-properties.ui")]
    public class DevicePropertiesDialog : Adw.PreferencesDialog {
        private bool template_disposing;
        static construct { typeof(PropertiesInformationRow).ensure(); typeof(DeviceSection).ensure(); typeof(DeviceIdentity).ensure(); }
        [GtkChild] private unowned Adw.PreferencesGroup loading_group;
        [GtkChild] private unowned DeviceSection identity_section;
        [GtkChild] private unowned DeviceSection information_section;
        [GtkChild] private unowned DeviceSection media_section;
        [GtkChild] private unowned DeviceSection storage_section;
        [GtkChild] private unowned DeviceSection hardware_section;
        [GtkChild] private unowned DeviceIdentity identity_widget;
        DeviceHardwarePage hardware_view;
        public DeviceInfo? information;
        [GtkChild]
        public unowned Adw.PreferencesPage general;
        public Adw.PreferencesPage hardware;
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
        Adw.NavigationPage hardware_page;

        public DevicePropertiesDialog(Place place, DeviceInformationProvider? provider = null) {
            this.place=place;this.provider=provider??DeviceInfoProvider.get_default();

            hardware_view = new DeviceHardwarePage(); hardware = hardware_view.hardware; hardware_page = hardware_view;
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
            clear();clear_hardware();loading_group.visible=true;
            try {var result=yield provider.query(place,current);if(!stopped&&!current.is_cancelled()&&request==generation)render(result);}
            catch(Error e) {if(!stopped&&!current.is_cancelled()&&request==generation){var result=new DeviceInfo();result.name=place.label;result.status=_("Unavailable");render(result);}}
        }
        void clear() {
            loading_group.visible = false;
            var window = get_root() as Gtk.Window;
            if (window != null) window.set_focus(null);
            foreach (var section in new DeviceSection[] {identity_section, information_section, media_section, storage_section, hardware_section}) section.clear_rows();
        }
        DeviceSection section(DeviceSection target) { target.visible = true; return target; }
        static void row(DeviceSection group, string title, string value) { if (value != "") group.append(new PropertiesInformationRow(title, value)); }
        static void size_row(DeviceSection group, string title, uint64? value) { if (value != null) row(group, title, Paths.size(value)); }
        public void render(DeviceInfo info) {
            clear(); information=info;
            section(identity_section); var identity = identity_widget;
            identity.icon.set_from_gicon(info.display_icon(place.icon ?? new ThemedIcon(place.icon_name), Gtk.IconTheme.get_for_display(get_display())));
            identity.label.label = info.name;
            var information=section(information_section);row(information,_("Type"),info.type_name());row(information,_("Status"),info.status);
            if(!info.connected){announce(_("Device disconnected"),Gtk.AccessibleAnnouncementPriority.MEDIUM);rebuild_hardware(info);return;}
            row(information,_("Filesystem"),info.filesystem);row(information,_("Mount point"),info.mount_point);
            row(information,info.optical?_("Disc label"):_("Volume label"),info.label);
            if(info.read_only!=null)row(information,_("Read only"),info.read_only?_("Yes"):_("No"));
            if(info.category==DeviceCategory.TAPE_DRIVE){row(information,_("Access"),_("Sequential storage"));var refresh=new Adw.ActionRow();refresh.title=_("Refresh");refresh.activatable=true;refresh.activated.connect(schedule);information.append(refresh);}
            row(information,_("Media type"),info.media_description());
            if(info.media_presence!=MediaPresence.UNKNOWN||info.media_removable==true)row(information,_("Media"),info.media_identity.presence_description(info.category));
            if(info.blank!=null&&info.blank)row(information,_("Disc status"),_("Blank"));
            if(info.optical) {
                bool filesystem_data=info.mounted&&info.blank!=true&&!info.audio_cd&&!(info.audio_tracks!=null&&info.audio_tracks>0&&info.data_tracks==0);
                if(info.media_presence!=MediaPresence.ABSENT&&(info.audio_tracks!=null||info.data_tracks!=null||info.media_size!=null||(filesystem_data&&info.capacity!=null))) {
                    var media=section(media_section);
                    if(info.audio_tracks!=null)row(media,_("Audio tracks"),info.audio_tracks.to_string());
                    if(info.data_tracks!=null)row(media,_("Data tracks"),info.data_tracks.to_string());
                    size_row(media,_("Reported media size"),info.media_size);
                    if(filesystem_data)size_row(media,_("Recorded data"),info.used_estimated?null:info.used);
                    if(filesystem_data)size_row(media,_("Filesystem capacity"),info.capacity);
                }
            } else if(info.category!=DeviceCategory.TAPE_DRIVE&&(info.capacity!=null||info.volume_size!=null)) {
                var storage=section(storage_section);size_row(storage,_("Capacity"),info.capacity);
                if(info.capacity==null)size_row(storage,_("Volume size"),info.volume_size);
                if(info.show_usage){var usage_row = new DeviceUsageRow(); usage_row.bar.fraction = (double)info.used / (double)info.capacity; storage.append(usage_row);}
                if(info.usage_allowed){size_row(storage,info.used_estimated?_("Used (estimated)"):_("Used"),info.used);size_row(storage,_("Available"),info.available);}
            }
            if(info.has_hardware){var summary=section(hardware_section);row(summary,_("Connection"),info.connection);row(summary,_("Device type"),info.hardware_type);row(summary,_("Model"),info.model);row(summary,_("Supported media"),info.supported_media());var details=new DestinationRow();details.title=_("Hardware Details");details.activated.connect(()=>push_subpage(hardware_page));summary.append(details);}
            rebuild_hardware(info);
        }
        void identifier(DeviceSection group,string title,string value) {
            if(value=="")return;
            var item=new CopyPropertiesRow(title,value);
            var copy=item.copy_button;copy.tooltip_text=_("Copy")+" "+title;
            attach_copy(copy,get_clipboard(),value);group.append(item);
        }
        static void attach_copy(Gtk.Button button,Gdk.Clipboard clipboard,string value){button.clicked.connect(()=>clipboard.set_text(value));}
        void clear_hardware() {
            foreach (var section in new DeviceSection[] {hardware_view.device_section, hardware_view.storage_section, hardware_view.filesystem_section}) section.clear_rows();
        }
        void rebuild_hardware(DeviceInfo info) {
            clear_hardware();
            if(!info.connected){row(section(hardware_view.device_section),_("Status"),_("Disconnected"));return;}
            if(info.vendor!=""||info.model!=""||info.serial!=""||info.revision!=""||info.connection!=""||info.media_compatibility.length>0){
                var device=section(hardware_view.device_section);
                identifier(device,_("Manufacturer"),info.vendor);identifier(device,_("Model"),info.model);identifier(device,_("Serial number"),info.serial);identifier(device,_("Revision"),info.revision);identifier(device,_("Connection"),info.connection);identifier(device,_("Supported media"),info.supported_media());
            }
            if(info.device!=""||info.block_object!=""||info.drive_object!=""||info.backing_file!=""||info.backing_object!=""||info.partition_uuid!=""||info.partition_scheme!=""||info.physical_size!=null||info.volume_size!=null||info.media_size!=null){
                var storage=section(hardware_view.storage_section);
                identifier(storage,_("Device path"),info.device);identifier(storage,_("Backing file"),info.backing_file);identifier(storage,_("Backing block object"),info.backing_object);identifier(storage,_("Block object"),info.block_object);identifier(storage,_("Drive object"),info.drive_object);identifier(storage,_("Partition UUID"),info.partition_uuid);identifier(storage,_("Partition scheme"),info.partition_scheme);size_row(storage,_("Physical device size"),info.physical_size);size_row(storage,_("Reported media size"),info.media_size);size_row(storage,_("Volume size"),info.volume_size);
            }
            if(info.uuid!=""||info.mount_point!=""||info.filesystem!=""||info.read_only!=null){
                var filesystem=section(hardware_view.filesystem_section);identifier(filesystem,_("Filesystem UUID"),info.uuid);identifier(filesystem,_("Mount point"),info.mount_point);row(filesystem,_("Filesystem"),info.filesystem);if(info.read_only!=null)row(filesystem,_("Read only"),info.read_only?_("Yes"):_("No"));
            }
        }
        void stop() {if(stopped)return;stopped=true;if(tape_monitor!=null){tape_monitor.cancel();tape_monitor=null;}token.cancel();generation++;if(refresh_source!=0){Source.remove(refresh_source);refresh_source=0;}foreach(var id in handlers)monitor.disconnect(id);handlers={};if(provider_handler!=0){provider.disconnect(provider_handler);provider_handler=0;}}
        protected override void dispose(){
            if (template_disposing) { base.dispose(); return; }
            template_disposing = true;
            if (token != null) token.cancel();
            stop();
            dispose_template(typeof(DevicePropertiesDialog));
            base.dispose();
        }
    }
}
