# Implementation and release status

Sidebar update, 26 October 2026: the shared Files/chooser sidebar now uses one Home
and Favorites destination, deduplicated XDG Folders, persistent System Drive first
under Devices, then Network and Trash. GTK bookmark UI/storage access was removed;
collections and cloud accounts remain available through the locations menu. The
Meson suite passes 13/13 groups. See [sidebar.md](sidebar.md) for identity mechanisms,
modified files, screenshots/tests and the physical-device verification limits.

The release/package assessment below describes the 22 October build; the existing
package artifact has not been rebuilt for this sidebar-only source update.

Assessment: 22 October 2026. The supplied final feature-gap instructions have been
implemented in the existing Vala/GTK4/libadwaita architecture. Automated and isolated
real-service checks are recorded below. Production approval still requires the
Majoris VM and hardware checks in [vm-acceptance.md](vm-acceptance.md). This is an
unsigned development build, not a claim of completed OS acceptance.

The full original 102-section specification and expanded Section 79 were not in
these attachments. The comparison in [release-matrix.md](release-matrix.md) covers
the supplied audits and final task; completeness against unseen requirements
cannot be asserted. Nautilus was a reference, not a replacement implementation.

## A. Issues resolved

| Original limitation | Implemented change and source | Regression evidence |
|---|---|---|
| Cloud account presence did not establish file capabilities | Explicit opt-in versioned per-file D-Bus adapter; real state, quota, progress, materialize/pin/evict/retry/cancel; owner-restart invalidation. `src/cloud/files.vala`, browser, chooser, preview, Properties | `tests/cloud.vala`: actual materialization, limits, cancellation, offline/quota, pin/evict. [Protocol](cloud-files.md) |
| Remote selections could fail portal mediation | Native filesystem URI for actual GVfs/FUSE paths; bounded retained imports with stable-source, space, progress and cancellation checks. Save verifies usable filesystem mediation and overwrite. `src/chooser/{window,import}.vala` | Actual SFTP/WebDAV Open/Save, twice-overwrite, imports, limits/cancel/disconnect, FUSE and no-FUSE; actual SMB and Flatpak document grants |
| Hidden shares lacked real visibility policy | Owned registry overlay sets browseable=no, preserves R/F/D ACLs, detects outside changes; narrow Polkit service. `sharing-service/visibility.vala`, `src/sharing/` | Actual Samba browse enumeration, direct hidden access, denied write, allowed write, POSIX restriction and administrator-change refusal |
| Firewall detection could misstate the host | Read-only backend detection; only owned firewalld policy may change, only home/work; unsupported/unmanaged reported. `sharing-service/firewall.vala` | Owned-rule/refusal/privacy fixtures; live Majoris firewalld/Polkit remains unverified |
| Replacement and batch rename interruption could strand files | Durable staging, source/target guards, native fsync and atomic exchange/fallback, journal reconciliation; batch rename fixed intent and identity. `src/operations/{manager,replacement-journal,rename-recovery,durability}.*` | Process termination at 25 replacement/rename/edit phases; real ENOSPC preserves old target/input; filesystem operation/Undo tests |
| RAW/HEIF/AVIF/HDR paths incomplete | LibRaw embedded thumbnail/limited full decode; libheif orientation/alpha, ICC/NCLX conversion and PQ/HLG SDR tone mapping; bounded timed AVIF on libheif >=1.23. `src/preview/image-decoders.*` | DNG, HEIC, static/timed AVIF, alpha/ICC, PQ/HLG and corrupt fixtures |
| Playback decoded untrusted media in UI process | Sandboxed GStreamer worker, bounded raw video/PCM protocol, cancellation, seek/pause/play, deadlines, error propagation. `src/preview/playback*`, `sandbox.vala`, `media.vala` | Actual H.264, HEVC, WebM/MKV, MP3, AAC, FLAC, Opus playback, pause/seek; malformed protocol and corrupt media |
| Encrypted multipart extraction and remote archives incomplete | Password via stdin; bounded sandbox extraction; volume validation, fsynced publication with incomplete marker; remote files/folders staged and published by backend rename. `src/archive/` | Encrypted round trip/hash, wrong password, missing/corrupt volume, 5 crash phases; real SMB/SFTP/WebDAV creation/extraction |
| Indexed search still walked covered trees | Conservative coverage interface; skip only authoritative covered roots, preserve uncovered/exhaustive fallback and Unicode infix semantics. `src/search/` | Actual TinySPARQL; covered/mixed/exhaustive fixtures; 10k/100k browsing and indexed search benchmarks |
| Rotation was temporary preview only | Save JPEG lossless MCU transform (explicit quality fallback) / lossless 8-bit PNG; preserve metadata, durable replacement and byte-exact persisted Undo/Redo. `src/actions/rotation.vala`, preview rotation helper, operation history | JPEG/PNG pixels/dimensions, restart Undo/Redo, external modification refusal and crash intent recovery |
| Grouped Grid lacked full-width headers | Virtualized section/row model, shared global selection and range keyboard handling, responsive columns and stable section labels. `src/views/{grid-rows,browser}.vala` | Group model/UI selection, keyboard/regroup, rendered wide/narrow windows |
| External columns/Nearby lacked reliable completion | Async complete metadata sort snapshot with bounds and cancellation; live enable/disable, restart/uninstall invalidation. Versioned external Nearby transfer adapter. `src/extensions/manager.vala`, `src/views/column-provider.vala`, `src/actions/nearby.vala` | Real D-Bus example/fixture, changed sort values, crash/restart, invalid/slow responses, transfer bytes/cancel |
| ISO defaults and package data incomplete | Scoped directory default, chooser registration, sharing service/state and Samba foundation data; explicit codec/decode dependencies | Meson install/package validation; OS default selection still requires ISO acceptance |

## B. Dependencies and configuration

`debian/control` is authoritative. Added development dependencies: libraw-dev,
libheif-dev >=1.19, liblcms2-dev, libturbojpeg0-dev and libtiff-dev (decoder fixtures).
GStreamer base plugins are explicit build/runtime dependencies. Runtime decoder
libraries are resolved by dpkg-shlibdeps; optional audio/video codecs remain the
good/bad/libav recommendations. Timed AVIF uses a compile-time >=1.23 guard; older
supported libheif retains static decoding. No experimental GNOME library is needed.

The ISO must provide working GVfs/FUSE backends, document portal, bubblewrap user
namespaces, Polkit agent, keyring and media plugins. It must select the installed
Majoris chooser and directory defaults, provision the Samba usershare foundation,
and deliberately choose trusted firewalld zones. See [platform-integration.md](platform-integration.md).
No host Samba/firewall configuration was changed by these fixtures.

## C. Executed verification

See `build/final-tests.log`, `build/meson-logs/testlog.json`, and integration logs in
`build/`. Meson builds the application, portal, privileged service, helpers and test
clients. The final source run and the clean Debian package build both passed 10/10 groups with no failures or skips. Desktop-file and AppStream validation, POT generation, staged installation and `git diff --check` passed. The unsigned package is `build/majoris-files_0.1.0-1_amd64.deb` (with debug symbols, buildinfo and changes alongside it). The suite has ten groups: core, cloud, replacement-crash, archive-crash,
image-decoders, firewall, filesystem, UI, session and portal.

Additional executed checks: isolated actual Samba server; actual SFTP/WebDAV with
and without FUSE; real document portal/Flatpak public and Gtk.FileDialog flows;
actual tmpfs ENOSPC; encrypted multipart/crash fixtures; rendered windows/dialogs;
10k/100k directory and covered-search benchmarks. Benchmark timings are machine
observations, not guarantees: covered 10k-tree search returned 10 hits with zero
walked directories in 0.011s versus 0.731s/1001 directories exhaustive; mixed root
walked one directory; 9990 indexed results took 3.229s with main-loop heartbeats.

Majoris VM acceptance: **not executed**. Windows 11 client, physical devices,
screen reader, actual speakers/GPU/HDR display and commercial cloud providers were
not available. Reproducible scenarios and required evidence are in
[vm-acceptance.md](vm-acceptance.md).

## D. Remaining limitations

- Missing bundled integrations: no commercial per-file cloud adapter or Nearby
  transport is bundled. The implemented capability protocols require a provider;
  account-only libcloudproviders does not imply materialization support.
- Backend limits: remote Save requires usable GVfs/FUSE mediation; imports are
  retained copies and never write back. Remote archive publication needs a backend
  rename. Remote replacement cannot promise native POSIX fsync durability.
- Decoder limits: formats depend on installed libraries/plugins; timed AVIF needs
  libheif >=1.23. HDR is tone-mapped to SDR, not HDR-display output. RAW full decode
  is bounded; 16-bit PNG saved rotation is refused instead of losing precision.
- Recovery/storage: old rotation bytes are retained for persisted Undo. Retained
  remote imports and unreferenced historical backups can consume disk space.
  Incomplete archive markers deliberately refuse automatic use; validate all
  volumes with `7z t` before an administrator resolves a stranded complete set.
- Testing not performed: the VM/hardware/provider cases listed above. A final ISO
  production approval must not be inferred from headless fixtures.
- Known defects: no unresolved failure in the executed final regression suite.
  This statement does not establish the absence of defects in untested platforms.

## E. Feature matrix

The [final matrix](release-matrix.md) distinguishes implemented behavior, backend
limits and unverified OS acceptance. Packaging is unsigned and does not install,
activate or replace the developer's system file manager.
