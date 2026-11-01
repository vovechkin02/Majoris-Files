# UDisks2 media-family recognition

This extends the existing DeviceInfoProvider and Device Properties dialog. It
adds no media drivers, device-management operations or library dependencies.

## Identifier inventory

The central `MediaIdentity.describe()` table recognises all 35 identifiers in
[the UDisks2 Drive MediaCompatibility reference](https://storaged.org/doc/udisks2-api/latest/gdbus-org.freedesktop.UDisks2.Drive.html).
Descriptions are gettext strings. The raw `Media` string and complete
`MediaCompatibility` array remain in `DeviceInfo`, including unknown values.

| Identifier | Readable description | Family |
| --- | --- | --- |
| `thumb` | USB flash drive | Thumb |
| `flash` | Flash memory card | Card |
| `flash_cf` | CompactFlash | Card |
| `flash_ms` | Memory Stick | Card |
| `flash_sm` | SmartMedia | Card |
| `flash_sd` | SD card | Card |
| `flash_sdhc` | SDHC card | Card |
| `flash_sdxc` | SDXC card | Card |
| `flash_sdio` | SDIO | Card |
| `flash_sd_combo` | SDIO combination card | Card |
| `flash_mmc` | MultiMediaCard | Card |
| `floppy` | Floppy disk | Floppy |
| `floppy_zip` | Zip disk | Cartridge |
| `floppy_jaz` | Jaz disk | Cartridge |
| `optical` | Optical disc | Optical |
| `optical_cd` | CD | Optical |
| `optical_cd_r` | CD-R | Optical |
| `optical_cd_rw` | CD-RW | Optical |
| `optical_dvd` | DVD | Optical |
| `optical_dvd_r` | DVD-R | Optical |
| `optical_dvd_rw` | DVD-RW | Optical |
| `optical_dvd_ram` | DVD-RAM | Optical |
| `optical_dvd_plus_r` | DVD+R | Optical |
| `optical_dvd_plus_rw` | DVD+RW | Optical |
| `optical_dvd_plus_r_dl` | DVD+R DL | Optical |
| `optical_dvd_plus_rw_dl` | DVD+RW DL | Optical |
| `optical_bd` | Blu-ray Disc | Optical |
| `optical_bd_r` | BD-R | Optical |
| `optical_bd_re` | BD-RE | Optical |
| `optical_hddvd` | HD DVD | Optical |
| `optical_hddvd_r` | HD DVD-R | Optical |
| `optical_hddvd_rw` | HD DVD-RW | Optical |
| `optical_mo` | Magneto-optical disc | Optical |
| `optical_mrw` | Mount Rainier compatibility | Optical |
| `optical_mrw_w` | Mount Rainier writing capability | Optical |

`optical_mrw` and `optical_mrw_w` are capabilities. They appear in Supported
media and never become the primary inserted-media description. Audio-only CDs
retain their track-based description through GIO CDDA or reported audio tracks.

## Classification and presence

`DeviceCategory` now includes `MEMORY_CARD` and `REMOVABLE_CARTRIDGE`.
`MediaIdentity` separates format description, family resolution, reader naming,
presence presentation and icon preference. Current reported media takes
precedence over compatibility for the format description; compatibility is never
substituted for inserted media. An empty single-format reader may have a specific
reader Type, while several formats produce Memory card reader. Labels supplied
by GIO remain unchanged, including volume labels such as CAMERA.

Explicit system, tape, disk-image and portable identities are protected.
Optical, cartridge and conventional floppy families remain distinct. Flash-card
classification requires reported media removability; fixed MMC remains internal
storage when the hardware attributes indicate that. Thumb drives retain the
removable-storage category even with non-removable media. USB connection alone
never identifies a thumb drive. No form factor, SD variant, eMMC identity or
capacity is inferred from a filesystem size.

Presence remains Present/Absent/Unknown. UDisks absence is trusted only with
MediaChangeDetected and MediaAvailable, for a removable-media device; reliable
GIO automatic-media information is also retained. Missing values, unsupported
change detection and an empty Media string do not establish absence. Ordinary
non-removable storage has no No media inserted state. Confirmed absence clears
filesystem, partition identifiers and all volume/media usage values.

An unknown `flash_` identifier has a generic flash-card description and requires
removability for card classification. Unknown `optical_` identifiers use Optical
disc. Other unknown identifiers use Unknown media and the hardware-derived
generic category. No speculative CFexpress, CFast, XQD or SDUC identifiers exist.

## Shared snapshots and sidebar reconciliation

`DeviceInfoProvider.media_snapshot()` coalesces concurrent ObjectManager reads
and caches the immutable result. GVolumeMonitor and relevant UDisks signals
invalidate it. In-flight invalidated replies are retried; cancelled waiters do
not receive old results. The sidebar consumes one snapshot for its entire
inventory, without filesystem queries or synchronous D-Bus during row rendering.

Places retains its existing GIO inventory and deduplication. It applies media
metadata to current Place objects and emits presentation_changed for changed
entries. Browser updates the existing row image without rebuilding or replacing
its row, changing the selected row, or renaming volumes. Removed Place objects
cannot receive a result intended for a different entry. Empty readers use their
real GDrive; when one current volume appears, an open reader Properties dialog
adopts it and queries its mounted filesystem. Multiple volumes are not arbitrarily
collapsed into one filesystem. Replacement drives do not inherit old results.

The icon policy preserves suitable GIO icons, including specific custom icons.
Media-specific overrides consult Gtk.IconTheme.has_icon. Verified standard
fallbacks are media-flash-symbolic, drive-removable-media-symbolic,
media-floppy-symbolic, drive-optical-symbolic and drive-harddisk-symbolic.
There is no assumed dedicated Zip/Jaz resource: the removable-drive fallback is
used. No icons or CSS were added to Files or Majoris Theme.

## Properties and capacity

The existing native Information, Storage/Disc Information and Hardware sections
remain. Primary labels and Supported media use the translated central mapping.
Hardware Details preserves model, manufacturer, serial, connection, paths,
filesystem/partition identifiers, sizes and backing relationships. Unknown raw
identifiers remain in the snapshot for diagnostics rather than ordinary labels.

Mounted cards and cartridges use existing asynchronous GIO filesystem statistics,
including guarded usage bars and explicitly estimated used space when necessary.
Empty/unmounted media never get fabricated used/free values. Physical, inserted
media, partition and mounted-filesystem sizes remain separate. Optical media have
no ordinary usage bar. Mounted data and magneto-optical filesystems can expose
actual capacity without requiring a track count; audio-only and blank media do
not receive those filesystem figures. No media discovery operation mounts,
ejects, polls, rewinds, writes, burns or opens a raw device.

## Tests and reproduction

`tests/device-properties.vala` contains the independent 35-row expected-name and
category table, presence/embedded-media/precedence fixtures, shared-cache tests,
mock GDrive/GVolume/GMount lifecycle tests, the existing storage/identity tests,
and 14 new media UI fixtures in both appearances. A real Browser widget test
asserts that the same sidebar row receives family changes and restored fallback
icons. `tests/places.vala` covers icon availability/fallbacks, specific GIcon
preservation, label preservation, incremental notifications and deduplication.
All storage values are injected; no physical media is required.

```sh
meson setup build --reconfigure
meson compile -C build
GTK_A11Y=none ADW_DISABLE_PORTAL=1 meson test -C build --print-errorlogs
```

The environment variables are for headless WSL tests, not production behaviour.

Capture the 14 new views and reader Hardware Details in light and dark:

```sh
mkdir -p artifacts/media-recognition
MAJORIS_DEVICE_THEME=/path/to/Majoris-Theme/theme/Majoris \
MAJORIS_MEDIA_EVIDENCE="$PWD/artifacts/media-recognition" \
dbus-run-session -- xvfb-run -a env GTK_A11Y=none ADW_DISABLE_PORTAL=1 \
GDK_BACKEND=x11 GSK_RENDERER=cairo GSETTINGS_BACKEND=memory \
build/device-properties-tests -p /devices/media-dialog
```

The new views cover SD, SDHC, SDXC, CompactFlash, Memory Stick, SmartMedia, MMC,
an empty multi-format reader, Zip, Jaz, DVD-RAM, HD DVD, magneto-optical media and
unknown generic removable media. Hardware/session tests were not performed.
Linux can report a broad family or no medium identity; that limits specificity.
The existing guarded handling of Btrfs, logical/encrypted storage and tape
metadata remains in place.
