# Device Properties

Device Properties is a read-only inspection path, separate from ordinary file
and folder Properties. It never mounts a volume, enumerates user files, opens a
block/tape device, or invokes a storage-management method.

## Architecture

* `DeviceInfo` is a typed snapshot. Nullable sizes and booleans distinguish
  unknown values from real zero/false. Filesystem, volume, physical-device and
  removable-medium sizes have separate fields.
* `DeviceInformationProvider` is the injectable asynchronous, cancellable dialog
  interface. `DeviceInfoProvider` combines GIO filesystem attributes and one
  UDisks2 ObjectManager snapshot. Its protected I/O methods and injectable GIO
  inventory support deterministic tests without querying host storage.
* The resolver matches Unix device identifiers, UDisks symlinks and exact mount
  roots. It does not use labels as identities. Multiple matches are ambiguous:
  hardware is omitted. Btrfs associations are conservatively omitted because
  one mounted subvolume can span multiple devices. Logical devices without a
  reliable Drive relationship retain their logical/block information; encrypted
  mappings expose the reported backing-object relationship.
* `DevicePropertiesDialog` uses native libadwaita preferences groups and the
  shared `PropertiesInformationRow`. The header contains an icon and name.
  Information, Storage/Disc Information and Hardware adapt to known fields.
  Hardware Details groups Device, Storage and Filesystem information, including available partition UUID/scheme and media compatibility. It uses native navigation and keyboard-accessible copy buttons.
* `Places` retains the dedicated `/` entry and GVolumeMonitor inventory, adds
  empty removable readers/drives, and asynchronously discovers Linux `stN`
  tape entries. Rewinding/non-rewinding aliases produce one sidebar entry.
  The sysfs inode distinguishes a replacement tape device reusing the same name.
  Sysfs and `/dev` directory notifications refresh this optional inventory.

## Storage and media semantics

Root capacity comes from `GFile.query_filesystem_info_async`, independently of
any physical-drive association. The same API supplies mounted-volume capacity,
used space, free space, filesystem type and read-only state. Attribute types
are checked. When used space is absent, total minus available is explicitly
labelled **Used (estimated)**. Reserved space need not make used plus available
equal capacity. Invalid or inconsistent figures suppress the usage bar while
preserving known measurements. Native progress semantics and text rows expose
usage without depending on colour.

Unmounted devices show reported volume and hardware sizes without used/free
figures. Opening Properties does not mount them. Optical media have no ordinary
usage bar; reported media size, recorded bytes, tracks, blank state and
filesystem capacity are conditional. Free filesystem bytes are never described
as writable disc capacity. No nominal disc capacities are guessed. Audio-only
media skip filesystem capacity queries when identified. Media presence and mount
state are separate, and floppy insertion remains unknown when change detection
is unsupported.

Tape inspection reads only sysfs identity/model/vendor metadata. It never opens
`/dev/stN` or `/dev/nstN`, issues tape ioctls, or runs tape commands. Cartridge,
position, technology and capacity are omitted without a reliable backend.
Status is explicitly unavailable when sysfs supplies no status. Tape Properties
offers a bounded manual Refresh action as well as removal notifications.

Portable GVfs devices use their actual URI scheme and receive a minimal view.
Loop interfaces and loop-backed partitions identify disk images and expose their
reported backing file. Unknown categories remain generic storage.

## Integration and lifecycle

Sidebar device menus include Properties even without a mount or medium. System
Drive never receives eject/unmount controls. Ordinary Properties entry points
route `/` and exact GVolumeMonitor roots to Device Properties, excluding symbolic
links. Ordinary directories below `/mnt` or `/media` retain folder Properties.
The shared chooser receives the same read-only action and no new management
commands. Existing mount/eject actions remain outside the inspection provider.

GVolumeMonitor changes and relevant UDisks PropertiesChanged/ObjectManager
signals trigger coalesced refreshes. Each refresh cancels its predecessor,
clears obsolete storage/media rows, reconciles original GIO object identity and
rejects stale callbacks. A new object reusing an old device path is not adopted.
Removable media can change within the original connected GDrive. Closing
cancels requests, removes queued refresh work and disconnects dialog observers.
The shared provider owns one set of backend subscriptions, not one per row.

No Files-specific CSS was added. The installed Majoris Theme owns all styling.
No new library dependency is required: GDBus uses existing GIO; `udisks2` remains
the existing runtime dependency. No tape utility is required.

## Verification

Run in Debian with the repository's normal build dependencies:

```sh
meson setup build --reconfigure
meson compile -C build
meson test -C build --print-errorlogs
```

For headless WSL, use `GTK_A11Y=none ADW_DISABLE_PORTAL=1` and, where necessary,
`--num-processes 2` for the test command. These are test-session settings, not
production changes.

`tests/device-properties.vala` covers typed storage calculations, fake UDisks
objects, injected GIO/UDisks failures, root statistics, unmounted inspection
without mutations, reused identities, tape discovery/deduplication, adaptive
dialog fields, disconnection, cancellation, hardware navigation and actual
release of closed dialogs. Existing menu tests assert the System Drive
Properties action and absence of management actions.

Capture the twelve representative states and Hardware Details in both palettes:

```sh
mkdir -p artifacts/device-properties
MAJORIS_DEVICE_THEME=/path/to/Majoris-Theme/theme/Majoris \
MAJORIS_DEVICE_EVIDENCE="$PWD/artifacts/device-properties" \
dbus-run-session -- xvfb-run -a env GDK_BACKEND=x11 GSK_RENDERER=cairo \
GSETTINGS_BACKEND=memory GTK_A11Y=none ADW_DISABLE_PORTAL=1 \
build/device-properties-tests
```

Images `light-00` through `light-11` (and `dark-*`) show System Drive, internal
HDD, external USB SSD, USB flash drive, unmounted NTFS, empty DVD drive, data DVD,
audio CD, FAT12 floppy, SCSI tape, ISO image and disconnected state. The hardware
images exercise a long serial identifier. All displayed values are fixtures.
These captures do not establish physical optical/floppy/tape operation or a
full GNOME session's accessibility, scale and hotplug behaviour. No physical
storage hardware is claimed as tested.
