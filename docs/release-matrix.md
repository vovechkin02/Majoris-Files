# Final feature matrix

Assessed against the supplied remaining-feature audits and final task on 22 October
2026. The complete original specification and expanded Section 79 were not supplied;
their independent full comparison remains unavailable. “Implemented” describes
code plus executed regression evidence, not production OS acceptance.

| Requirement | Final behavior / evidence | Remaining qualification |
|---|---|---|
| Per-file cloud states and operations | Implemented: capability adapter, progress/quota, materialize/pin/evict/retry/cancel, live badges and chooser/preview; actual D-Bus fixture | Vendor adapters and real accounts unverified; account-only providers explicitly unsupported |
| Remote Open | Implemented: actual SMB/SFTP/WebDAV FUSE originals and retained import fallback; size/space/cancel/disconnect | Imported copy is explicitly separate; cloud depends on provider |
| Remote Save/overwrite | Implemented: actual SMB/SFTP/WebDAV writes and repeated overwrite, document portal mediation | No-FUSE remote Save explicitly refused; no invented writeback |
| Public portal / native chooser API | Executed actual Flatpak public portal and Gtk.FileDialog local cases and SMB cases; selected grants and unselected denial | Real Majoris Notepad, Wayland parenting/focus, concurrent apps and device removal require VM |
| SaveFiles and cancellation | Implemented ordered safe names, collisions, no premature files, request lifecycle | Names are not reservations; case-insensitive races require backend acceptance |
| True hidden shares | Implemented browseable=no owned overlay; actual browse omission and direct access | Actual Windows client not run |
| Samba R/F/D / POSIX | Actual read denial/write denial/allowed write and restrictive POSIX fixture, hidden-share ACL update | Windows, advanced POSIX ACL and guest combinations remain VM gates |
| Clients/emblems/inventory | Implemented bounded owner-scoped clients, live inventory and emblems | Real multi-client disconnect/status and Polkit denial require VM |
| Firewall | Implemented safe detection and opt-in owned home/work policy, unsupported explicit | Real runtime/permanent lifecycle and denial unverified |
| Replacement recovery | Implemented staged native publication, fsync, guarded recovery; file/directory crash phases and ENOSPC | Remote backend cannot provide native durability guarantees |
| Batch rename | Implemented pre-mutation durable intent, fixed identities and recoverable cycles; crash fixtures | Power-loss hardware/filesystem acceptance unverified |
| RAW/HEIF/AVIF/HDR | Implemented LibRaw/libheif/ICC/NCLX/PQ/HLG SDR rendering; synthetic and generated decoder fixtures | Broad real-camera corpus and HDR hardware unverified; timed AVIF >=1.23 |
| Animation | Bounded existing animation viewer plus timed AVIF; thumbnails and reduced motion retained | Broad variable-timing corpus depends on installed decoder |
| Video/audio previews | Actual eight codec/container fixtures, pause/seek, metadata/thumbnail fixtures | Speaker/GPU and broad tagged corpus require VM |
| Decode isolation | Implemented sandbox worker for playback as well as image/document/archive preview, bounded raw output | ISO namespace policy must permit sandbox |
| Encrypted multipart archive | Implemented password stdin, limits, volume verification, crash-safe incomplete state | Deliberately stranded sets require validation/recovery |
| Remote archive | Actual SMB/SFTP/WebDAV input file/folder and output extraction/create | Backend must support final rename; failed complete local output retained |
| Indexed search | Implemented authoritative coverage, Unicode ranking, uncovered fallback; actual TinySPARQL and benchmarks | Unknown coverage deliberately recurses; content coverage not guessed |
| Saved image rotation | Implemented JPEG/8-bit PNG, metadata, durable persisted Undo/Redo; tests and crash fixtures | Non-perfect JPEG requires explicit lossy confirmation; 16-bit PNG refused |
| Grouped Grid | Implemented full-width headers, virtualized rows, range/keyboard selection and regroup preservation; UI/render checks | Real screen reader/large-font acceptance remains |
| External extensions / columns | Implemented versioned external process, restart/uninstall/cancel/bounds, actual async metadata sort and live columns | Third-party adapters must obey documented protocol |
| Nearby Share | Implemented peer/transfer/cancel adapter with actual fixture byte transfer | No bundled transport; feature unavailable without capable provider |
| Accessibility / devices | Labels, keyboard and mount-loss behavior preserved, headless tests | Physical USB/MTP/PTP/optical/busy/eject and screen reader not available |
| Desktop / Debian / ISO | Package data, MIME defaults, FileManager1/search/portal/service integration; unsigned package build | ISO must select Majoris defaults and avoid competing FileManager1 activation; VM acceptance open |

Detailed changes/dependencies/results: [status.md](status.md). Reproducible OS gates:
[vm-acceptance.md](vm-acceptance.md). Production acceptance is not yet certified.
