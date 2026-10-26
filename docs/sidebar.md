# Sidebar composition and deduplication

Implemented 26 October 2026. `Places` supplies the same ordered navigation model to
Files and all chooser modes:

```
Home
Favorites
Folders
  Desktop, Documents, Downloads, Pictures, Music, Videos
Devices
  System Drive
  available volumes/devices
Network
Trash
```

The Folders and Devices strings are row headers, not selectable destinations.
Home retains the current Home/Recent experience (`recent:///`); the Home Folder is
available through Other Locations and Collections. Favorites remains the existing
explicit SQLite collection for both files and folders. No individual Favorite
appears in the sidebar. No GTK bookmarks are read, changed, imported or deleted;
the obsolete bookmark actions, context controls, drag reordering and write APIs
have been removed.

## Standard folders

`Environment.get_user_special_dir()` resolves the six configured XDG directory
kinds, in the order above. Each row uses a type-specific symbolic icon and a stable
folder-type label, even when the actual path is redirected or renamed. `GFile.equal`
compares normalized locations; the first configured kind wins when several kinds
resolve to one location. A directory disabled by pointing it at Home is omitted.
Unset paths are omitted. Configured missing/unavailable paths remain navigable
entries and report the existing browsing error when opened; Files never creates
folders to populate the sidebar. A monitor on `user-dirs.dirs`, with a short event
coalescing delay and GLib's special-directory-cache reload, applies changes live.

## System filesystem

`GUnixMountEntry.for("/")` identifies the mounted filesystem backing `/`, including
its source, filesystem type and filesystem root. A bounded snapshot of the Linux
mount table (`/proc/self/mountinfo`) supplies the kernel filesystem number plus
filesystem root, distinguishing separate anonymous tmpfs/overlay instances. This
is read on GIO inventory events, not hardware polling. It does not assume a block
device name or expose a physical disk as the root identity. A synthetic System Drive
row always opens `/`, always starts Devices and never receives mount/eject actions,
even when GVolumeMonitor omits it or mount-table lookup is unavailable.

GIO mounts at `/` or matching the root filesystem and filesystem-root identity are
reconciled with that row. Their related volumes, and an unmounted volume identifying
the root source, are excluded. Including the filesystem-root component avoids
merging independent Btrfs subvolumes into aliases merely because their source is
the same. The row remains available for ext4, Btrfs, encrypted/LVM and multi-device
root arrangements without adding storage information or management UI.

## Devices

GVolumeMonitor supplies drive, volume and mount lifecycle notifications; there is
no polling or raw-partition inventory. GIO applies backend/UDisks visibility hints.
Shadowed mounts, incidental internal system mounts and non-mountable unmounted
volumes are excluded. Mount roots are deduplicated with GFile identity and native
mount-table identities; related volume UUIDs/device identifiers are preferred to
object identity, with a process-lifetime object fallback only if identifiers are
unavailable. Display names never identify devices. Multiple volumes of one disk
remain separate, and different drives may share a label.

Order: root, internal, removable, optical, phone/camera, other mounted devices;
within a class, friendly names and stable identities break ties. GIO symbolic icons
are retained. An empty optical drive is included when GDrive and its icon identify
it; opening polls for inserted media or reports that a disc is needed. Existing
GtkMountOperation authentication/mount and appropriate unmount/eject actions remain.
Raw device placeholders cannot be used as file drop targets or opened in new tabs.

The shared locations popover retains Home Folder, Recent, tags, saved searches and
cloud accounts/provider account actions without extra permanent sidebar sections.
Network/GVfs, Connect to Server, search scope, Trash and portal grant handling remain
on their existing paths.

## Verification

`tests/places.vala` uses isolated HOME/XDG storage and a real GLib configuration
monitor. It covers folder order, redirection, normalization, duplicate/disabled/
missing locations, live configuration changes, fresh-process restart, unchanged
GTK bookmark contents, explicit file/folder Favorites and persistence. Device
projection fixtures cover root reconciliation, aliases, equal labels, multiple
partitions, disconnect, unmounted/optical/camera entries and visibility policy.

`tests/ui.vala` asserts the shared rendered model and Devices header during Open,
Open Multiple, Save and Select Folder, while retaining their result assertions.
`tests/redesign.vala` covers collection navigation and the existing native layout.
The final Meson build passed all 13 test groups with no failures or skips.
Light and dark Files/chooser renders were inspected; standard folder labels and
the persistent Devices heading are visible in both themes. Kernel identity tests
also cover root aliases, separate tmpfs instances, Btrfs roots and escaped paths.
The full suite and light/dark render checks are recorded under
`build/sidebar-*.log` and `build/sidebar-{light,dark}/`.

Physical attach/eject, optical insertion, MTP/PTP and encrypted-device authorization
were not available in this environment. Their production paths use GIO objects;
the inventory projection fixtures do not claim physical-hardware acceptance.

## Modified files

- `src/sidebar/places.vala`: shared composition, XDG refresh, root/device identities.
- `src/views/browser.vala`: typed sidebar rows, icons, headers, location menu and device actions.
- `src/window/window.vala`: remove obsolete bookmark action/menu and command rules.
- `tests/places.vala`: isolated model, configuration, Favorites and filesystem identity tests.
- `tests/ui.vala`: shared chooser structure, root navigation and retained drop-policy checks.
- `tests/redesign.vala`: Home model and retained tag/saved-search access.
- `tests/visual.vala`: standard XDG fixture and full-width chooser capture.
- `meson.build`: register sidebar tests.
- `po/majoris-files.pot`: refresh translated navigation labels.
- `docs/architecture.md`, `docs/status.md`, `docs/sidebar.md`, `debian/docs`: documentation and packaged report.
