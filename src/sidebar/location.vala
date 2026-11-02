namespace MajorisFiles {
    // One resolver for row activation, Open, Open in New Tab and Mount. Device
    // objects, rather than row indexes or synthetic device URIs, identify work.
    public class SidebarLocations : Object {
        public static Volume? volume(Place place) { return place.volume ?? (place.mount == null ? null : place.mount.get_volume()); }
        public static Drive? drive(Place place) {
            var selected = volume(place);
            return place.drive ?? (selected == null ? (place.mount == null ? null : place.mount.get_drive()) : selected.get_drive());
        }
        public static Mount? current_mount(Place place) {
            var selected = volume(place); return selected != null ? selected.get_mount() : place.mount;
        }
        public static bool system(Place place) {
            var mount = current_mount(place);
            return place.system || place.file.equal(File.new_for_path("/")) || (mount != null && mount.get_root().equal(File.new_for_path("/")));
        }
        public static bool browsable(Place place) {
            if (place.tape_sysfs != "" || (place.device_info != null && place.device_info.category == DeviceCategory.TAPE_DRIVE)) return false;
            if (current_mount(place) != null) return true;
            if (place.device_info != null && place.device_info.media_presence == MediaPresence.ABSENT) return false;
            var selected = volume(place); if (selected != null) return selected.can_mount();
            if (place.drive != null) {
                foreach (var volume in place.drive.get_volumes()) if (volume.get_mount() != null || volume.can_mount()) return true;
                return false;
            }
            return !place.file.get_uri().has_prefix("majoris:///device/");
        }
        public static bool can_eject(Place place) {
            if (system(place) || place.tape_sysfs != "" || (place.device_info != null && place.device_info.category == DeviceCategory.TAPE_DRIVE)) return false;
            var mount = current_mount(place);
            var selected = volume(place); var device = drive(place);
            return (mount != null && mount.can_eject()) || (selected != null && selected.can_eject()) || (device != null && device.can_eject());
        }
        public static bool same(Place a, Place b) {
            if (a == b) return true;
            var av = volume(a); var bv = volume(b);
            if (av != null || bv != null) return av != null && av == bv;
            var ad = drive(a); var bd = drive(b);
            if (ad != null || bd != null) return ad != null && ad == bd;
            if (a.mount != null || b.mount != null) return a.mount != null && a.mount == b.mount;
            if (a.cloud != null || b.cloud != null) return a.cloud != null && a.cloud == b.cloud;
            if (a.tag != null || b.tag != null) return a.tag != null && b.tag != null && a.tag.id == b.tag.id;
            return a.file.equal(b.file) && a.tape_sysfs == b.tape_sysfs;
        }
        public static File? ready_location(Place place) {
            if (place.tape_sysfs != "" || (place.device_info != null && place.device_info.category == DeviceCategory.TAPE_DRIVE)) return null;
            var mounted = current_mount(place); if (mounted != null) return mounted.get_root();
            if (volume(place) != null || place.drive != null || place.file.get_uri().has_prefix("majoris:///device/")) return null;
            return place.file;
        }
        public static async File resolve(Place place, Gtk.Window? parent, Cancellable token) throws Error {
            token.set_error_if_cancelled();
            if (place.tape_sysfs != "" || (place.device_info != null && place.device_info.category == DeviceCategory.TAPE_DRIVE))
                throw new IOError.NOT_SUPPORTED(_("This device does not contain a browsable filesystem."));
            var ready = ready_location(place); if (ready != null) return ready;
            Volume? volume = SidebarLocations.volume(place);
            if (volume == null && place.drive != null) {
                var candidates = new Gee.ArrayList<Volume>();
                var volumes = place.drive.get_volumes();
                if (volumes.length() == 0 && place.drive.can_poll_for_media()) {
                    yield place.drive.poll_for_media(token); volumes = place.drive.get_volumes();
                }
                foreach (var item in volumes) if (item.get_mount() != null || item.can_mount()) candidates.add(item);
                if (candidates.size == 0) throw new IOError.NOT_FOUND(_("No browsable media is available in this drive."));
                if (candidates.size == 1) volume = candidates[0];
                else {
                    if (parent == null) throw new IOError.NOT_SUPPORTED(_("Select a volume to open this drive."));
                    var choice = new Adw.AlertDialog(_("Choose a Volume"), _("This drive contains more than one filesystem."));
                    choice.add_response("cancel", _("Cancel")); choice.close_response = "cancel";
                    for (int i = 0; i < candidates.size; i++) choice.add_response(i.to_string(), candidates[i].get_name());
                    string response = yield choice.choose(parent, token);
                    if (response == "cancel") throw new IOError.CANCELLED(_("Cancelled"));
                    int index = int.parse(response);
                    if (index < 0 || index >= candidates.size) throw new IOError.INVALID_ARGUMENT(_("The selected volume is unavailable."));
                    volume = candidates[index];
                }
            }
            Mount? mount = volume == null ? place.mount : volume.get_mount();
            if (mount == null && volume != null) {
                if (!volume.can_mount()) throw new IOError.NOT_MOUNTED(_("This volume cannot be mounted."));
                try {
                    if (!(yield volume.mount(MountMountFlags.NONE, new Gtk.MountOperation(parent), token)))
                        throw new IOError.FAILED(_("The volume could not be mounted."));
                } catch (IOError.ALREADY_MOUNTED e) { }
                token.set_error_if_cancelled(); mount = volume.get_mount();
                if (mount == null) throw new IOError.NOT_MOUNTED(_("Mounting completed without an available filesystem root."));
            }
            token.set_error_if_cancelled();
            File result = mount == null ? place.file : mount.get_root();
            if (result.get_uri().has_prefix("majoris:///device/")) throw new IOError.NOT_MOUNTED(_("This device is not available for browsing."));
            return result;
        }
        public static async void remove(Place place, bool eject, Gtk.Window? parent, Cancellable token) throws Error {
            if (system(place)) throw new IOError.NOT_SUPPORTED(_("The System Drive cannot be unmounted or ejected."));
            token.set_error_if_cancelled(); var operation = new Gtk.MountOperation(parent); var mount = current_mount(place);
            var selected = volume(place); var device = drive(place);
            bool success;
            if (eject) {
                if (mount != null && mount.can_eject()) success = yield mount.eject_with_operation(MountUnmountFlags.NONE, operation, token);
                else if (selected != null && selected.can_eject()) success = yield selected.eject_with_operation(MountUnmountFlags.NONE, operation, token);
                else if (device != null && device.can_eject()) success = yield device.eject_with_operation(MountUnmountFlags.NONE, operation, token);
                else throw new IOError.NOT_SUPPORTED(_("This device cannot be ejected."));
            } else {
                if (mount == null) throw new IOError.NOT_MOUNTED(_("This volume is no longer mounted."));
                if (!mount.can_unmount()) throw new IOError.NOT_SUPPORTED(_("This volume cannot be unmounted."));
                success = yield mount.unmount_with_operation(MountUnmountFlags.NONE, operation, token);
            }
            if (!success) throw new IOError.FAILED(_("The device operation did not complete."));
        }
    }
}
