# Device Properties implementation and evidence

All screenshots use injected values, native GTK/libadwaita widgets and the
existing Majoris Theme. See [the implementation guide](../../docs/device-properties.md)
for architecture, semantics and reproduction commands.

| Requested area | Implementation |
| --- | --- |
| 1. Architecture | Typed `DeviceInfo`, injectable `DeviceInformationProvider`, shared read-only `DeviceInfoProvider`, adaptive dialog and separate inventory. |
| 2. Classification | System, internal/removable volume, optical, floppy, tape, disk image, portable device and generic fallback; media presence is independent. |
| 3. GIO | Asynchronous, cancellable filesystem attributes, checked for presence and type; no directory-size scan. |
| 4. UDisks2 | One ObjectManager snapshot per refresh; exact device/symlink/mount relationships; Drive, Block, Filesystem, Partition, PartitionTable and Loop metadata. Relevant change signals refresh the dialog. |
| 5. System Drive | Always has Properties. `/` statistics remain filesystem statistics. No mount/eject/unmount commands. Ambiguous and multi-device physical associations are omitted. |
| 6. Internal/external storage | Mounted filesystem statistics and unmounted volume/hardware sizes remain separate. Properties never mounts a volume. |
| 7. Optical | Empty/inserted/blank media, audio/data tracks, reported media size and supported recorded/filesystem bytes. No writable-space assumptions or burning. |
| 8. Floppy | Metadata-based classification, conditional presence, actual backend capacity. Unsupported insertion detection remains unknown. |
| 9. Tape | Async `/sys/class/scsi_tape` discovery, one `stN` identity, optional hotplug directory monitors and bounded manual refresh. Vendor/model/path only when available; no tape device is opened. |
| 10. Hardware Details | Native Device/Storage/Filesystem subpage groups; identifiers and paths have copy buttons; partition UUID/scheme and backing relationships are conditional. |
| 11. Calculations | Nullable measurements, explicit estimated used space, reserved-space support and guarded ratios. Optical, tape and portable devices receive no ordinary disk bar. |
| 12. Sidebar | Properties on device entries, including unmounted/empty drives. Ordinary exact mount roots and `/` route to the same interface; file/folder Properties remains separate. |
| 13. Hotplug | Original GIO objects and tape sysfs inode identities are reconciled. Stale async results are cancelled/ignored, old rows are removed, disconnection is announced and observers disconnect on close. |
| 14. Files | New device model/provider/dialog and fixture tests; updates to Places, Browser, ordinary Properties routing, menu tests, Meson, Debian description, gettext source inventory and documentation. |
| 15. Dependencies | No new library or utility dependencies. Existing GIO/GDBus and runtime `udisks2` suffice. |
| 16. Automated verification | `setup.log`, `build.log`, `tests.log` and `fixtures.log` record the runs. Fixture tests cover calculations, UDisks mappings, injected production-provider I/O, tape discovery and dialog lifecycle. |
| 17. Visual verification | 26 light/dark native captures, plus JSON widget geometry. No overflowing text or zero-width bars were found in the geometry inspection. |
| 18. Physical hardware tested | None. All device-specific scenarios are fixtures. |
| 19. Limits | WSL/Xvfb is not a full GNOME hardware session. Real optical/floppy/tape hotplug, media behaviour and assistive technology require hardware/session testing. Tape cartridge/position/technology/capacity, optical duration and ambiguous backing-device details are omitted when no reliable metadata source supplies them. |

Screenshot indices (both `light-*` and `dark-*`):

| Index | State |
| --- | --- |
| 00 | System filesystem |
| 01 | Internal HDD |
| 02 | External USB SSD |
| 03 | USB flash drive |
| 04 | Unmounted NTFS volume |
| 05 | Empty DVD drive |
| 06 | Data DVD |
| 07 | Audio CD |
| 08 | FAT12 floppy |
| 09 | SCSI tape drive |
| 10 | Mounted ISO image |
| 11 | Disconnected device |
| hardware | Long serial identifier and grouped Hardware Details |

The initial headless run encountered accessibility-bus failures in existing
tests. The final regression command disables accessibility for the test session
and uses two concurrent tests. No production accessibility behaviour was changed.

Modified source/build files:

* `src/devices/device-info.vala` (new)
* `src/devices/device-provider.vala` (new)
* `src/dialogs/device-properties.vala` (new)
* `src/dialogs/properties.vala`
* `src/sidebar/places.vala`
* `src/views/browser.vala`
* `tests/device-properties.vala` (new)
* `tests/menus.vala`
* `meson.build`
* `debian/control`
* `po/POTFILES`
* `docs/device-properties.md` (new)

`artifacts/device-properties/` contains the verification evidence, not production
binaries or vendored libraries.

Final results: complete regression suite **23 passed, 0 failed**. After the final tape-inode identity change, all **5 affected suites passed** (device-properties, sidebar, Properties, menus and portal). The production and portal binaries linked successfully. All five device fixture groups passed; 26 themed captures passed geometry inspection.
