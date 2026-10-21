# Release verification matrix

This pass is **partial implementation, not release completion**. The supplied
remaining-features task and Nautilus chooser/portal/XML references were reviewed.
The original 102-section specification and complete expanded Section 79 were not
provided, so a full comparison against them cannot be asserted.

Automated tests run in Debian 13 WSL with GTK 4.18.6, libadwaita 1.7.6 and Vala
0.56.18. Headless X11 tests exercise application code; they are not Flatpak,
Wayland, hardware, firewall or external Windows-client acceptance.

| Requirement | Existing implementation / changes in this pass | Code paths | Automated coverage | Manual acceptance / remaining limitation |
|---|---|---|---|---|
| Open, multiple Open, Save, folder selection | Existing shared browser and portal retained | chooser/window.vala; portal/backend.vala | Existing UI and portal suites | Actual installed GTK/Flatpak routing and document permissions not verified |
| SaveFiles | Added bounded filename parsing, folder UI, conflict naming and ordered results through existing authenticated requests | chooser/options.vala; chooser/window.vala; portal/backend.vala | core validation; portal/save-files; filesystem destination checks | Real sandbox writes, case-insensitive filesystem behavior and concurrent external name creation need acceptance; results are not reservations |
| Remote chooser results | Existing native/FUSE normalization retained; explicit durable Open import added with byte/time limits and cleanup | chooser/import.vala; chooser/window.vala | Local copy/hash and cancellation fixtures | Actual SMB/SFTP/WebDAV/cloud mediation unverified; Save and folders need GVfs/FUSE; import edits do not write back |
| Chooser cancellation/security/parenting | Existing ownership, Close, concurrency and parent bridge retained | portal/backend.vala; portal/parent.c | Existing portal authorization/concurrent cancellation | Wayland/X11 external parenting, focus and caller exit acceptance pending |
| Detached devices | Mount removal cancels/invalidate acceptance, clears selection, navigates Home | chooser/window.vala | No physical mount-removal test | USB/network removal and recovery need actual hardware/service test |
| Adaptive browser/chooser | Added Adwaita sidebar overlay at narrow breakpoint, retains wide paned sidebar | views/browser.vala | UI adaptive sidebar transition | Broad size, keyboard, accessibility and display acceptance pending |
| Folder sharing UI | Shared Properties/standalone page, existing state loading, graphical accounts, explicit authenticated-user policy | sharing/settings.vala; dialogs/dialogs.vala; window/window.vala; application/file-manager.vala | Inventory/policy parser fixtures; no real Samba mutations | Windows read/write/deny/change/removal not verified; advanced ACLs refuse editing; share rename disabled while shared |
| Shared Folders | Queries actual usershares; Open/Edit/Copy/Stop actions | sharing/sharing.vala; sharing/settings.vala; window/extra-actions.vala | Inventory parser fixture | smb.conf shares administrator managed; live external changes require reopening; emblems and clients outstanding |
| Sharing authorization/firewall/ISO | Existing Polkit service retained | sharing-service/main.vala; data/*Sharing* | Existing policy validation only | Owned firewall rules, trusted-network approval, hidden shares and exact ISO configuration outstanding |
| Animated/extended images | Existing sandbox static-image decoder preserved | preview/helper.c; preview/sandbox.vala | Existing preview fixtures | Animation, extended codec/color metadata and persistent rotation outstanding |
| Audio/video | Dedicated audio presentation with GTK controls and cancellation cleanup added | preview/preview.vala | Build and existing provider suite | Actual playback, metadata/artwork, fullscreen, probing/isolation and video thumbnails outstanding |
| Text/Office/remote previews | Existing bounded text, sandbox extracted Office text and thumbnail downloads retained | preview/preview.vala; preview/office.vala; preview/thumbnail.vala | Existing preview fixtures | GtkSourceView/encoding UI, formatted Office rendering and remote preview materialization outstanding |
| Properties/metadata/permissions | Sharing integrated; existing general/permissions preserved | dialogs/dialogs.vala; dialogs/permissions.vala; operations/permissions.vala | Existing multi-selection and account fixtures | Unified metadata/Open With sections, EXIF/XMP/media extraction and ACL acceptance outstanding |
| Batch rename | Existing basic templates and preflight retained | window/extra-actions.vala; operations/manager.vala | Existing file-operation tests | Metadata templates, full preview UI, temporary ordering and complete grouped recovery outstanding |
| Indexed/full-text search | Existing recursive GIO/text fallback retained | search/search.vala; search/filters.vala | Existing search/filter/content tests | Indexed provider, PDF/Office content, ranking and indexing preferences outstanding |
| File operations/recovery | Existing operations/journal/retry retained | operations/manager.vala | Filesystem/UI conflict, undo/retry tests | Durable replacement recovery, remote Trash and expanded workflows/acceptance outstanding |
| Archives | Existing libarchive and encrypted ZIP retained | archive/archive.vala; archive/native.c | Existing archive roundtrip | Native multi-volume/encrypted 7z and broader progress outstanding |
| Splitting/checksums | Optional manifest; SHA-256/SHA-512 UI and pasted/file verification added; checksum error closes stream | split/split.vala; dialogs/split.vala; dialogs/checksum.vala | Parser tests; split-without-manifest fixture; existing split/join | 100 GB benchmark and arbitrary filesystem capability detection outstanding; unknown limits are not invented |
| Cloud | Existing libcloudproviders discovery/actions retained | sidebar/cloud.vala; models/accounts.vala | No real-provider fixture | Per-item availability/materialization/quota capability interfaces outstanding |
| Extensions | Existing internal action/column interfaces retained | actions/registry.vala; views/column-provider.vala | Existing provider tests | External protocol/discovery/example/integration test outstanding |
| Shell/desktop/devices | Existing FileManager1, desktop portals, Nearby interface, UDisks retained; serialized byte-array handling fixed | application/file-manager.vala; actions/desktop.vala; actions/nearby.vala; devices/disk-images.vala | Existing UDisks inventory and Nearby flow tests | Shell search provider, real transport, wallpaper/email, mounts/Polkit/busy-device and persistent rotation acceptance outstanding |
| Localization/accessibility/performance | Existing theme behavior retained | application-wide | Existing UI tests only | Gettext coverage, full keyboard/screen-reader audit and required workload benchmarks outstanding |
| Packaging/release | No new runtime library dependencies; new Vala sources included in Meson | meson.build; debian/control | Meson build/test | Debian binary-package validation and complete ISO/platform acceptance outstanding |

## Reproducing automated verification

From the repository in Debian 13 with the dependencies in platform-integration.md:

```sh
meson setup build --prefix=/usr  # use meson setup --reconfigure build when configured
meson compile -C build
meson test -C build --print-errorlogs
```

The new fixtures do not change the host's Samba or firewall policy. The import
fixture supplies its own temporary destination. No real share or SMB account is
created by the automated tests.

## Required platform acceptance

Use a disposable Majoris VM, separate Windows SMB client and a Flatpak test caller.
Install the built Files components with the documented portal routing. Run local
Open/multiple/Save/folder/SaveFiles requests through public portal APIs; read/write
the returned files inside the sandbox, and verify unselected paths and cancelled
requests receive no new access. Repeat with GVfs SMB/SFTP/WebDAV and a disconnected
USB mount. Test explicit remote imports separately, confirming the local copy is
retained and changes do not modify the remote source. Repeat external-window focus,
modality and cancellation under both X11 and Wayland.

Create a test folder through Properties → Sharing, configure SMB credentials in
the existing GUI, then verify read-only, authenticated-user, guest and read/write
policies from Windows. Change policy, reconnect clients, remove sharing and confirm
denial. Check POSIX permissions independently. Do not declare the sharing release
criterion met until owned trusted-network firewall policy is implemented and tested.

Run all media/document/image, batch rename, search, archive, extension and workload
scenarios in section 18 of the supplied task after their remaining implementations
exist. No manual scenario in that list has been declared passed by this report.
