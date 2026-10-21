# Release completion matrix

Status is assessed against the supplied remaining-feature audit. **Partial** means
that either implementation or required verification remains. A passing narrow
fixture is not evidence for an entire feature family. The original specification
and complete expanded Section 79 were not supplied; their full comparison is open.
Source paths below are relative to `src/` unless otherwise stated.

| Feature / task | Implementation | Tests / evidence | Status and outstanding work |
|---|---|---|---|
| Remote Open (2.1) | `chooser/import.vala`, `chooser/window.vala`: configurable limits, progress, space and source checks, cancellation, retained imports | Filesystem import/hash/cancellation fixtures | Partial: real large SMB/SFTP/WebDAV/cloud transfers and receiving-application lifetime acceptance pending; direct backend results are local/FUSE paths |
| Remote Save (2.2) | Chooser verifies destination and overwrite; usable GVfs/FUSE destinations go through document portal | Chooser destination tests; local real Flatpak save | Partial: actual writable SMB/SFTP/WebDAV, disconnect and overwrite acceptance pending; non-FUSE writeback is unsupported and explicitly rejected |
| Portal routing/security (2.3–2.4) | `portal/backend.vala`, registration/config, shared request lifecycle | `tests/portal.vala`; actual Flatpak public Open/multiple/Save/folder/SaveFiles/cancel and Gtk.FileDialog five modes in `tests/flatpak-*` | Partial: actual concurrent Flatpak callers, external parent focus/modality, caller exit and alternate GTK selection APIs remain |
| SaveFiles (2.5) | Bounded names, ordered outputs, existing/repeated-name avoidance, no premature output creation | Core parser, component D-Bus, actual sandbox writes and host contents | Partial: case-insensitive backend and concurrent external creation acceptance; returned names are not reservations |
| Parenting/devices/a11y (2.6–2.8) | X11/Wayland parent bridge, mount-loss invalidation, cancellation, browser keyboard controls | Headless chooser/cancellation and adaptive tests | Partial: real X11/Wayland parent ownership/focus, five removal scenarios and screen reader audit |
| Hidden shares (3.1) | Existing usershare creation preserved | No true browseability fixture | Partial: a per-share non-browseable policy is not implemented; a dollar suffix is not advertised as that policy |
| Samba per-user policy (3.2) | `sharing/sharing.vala`, `sharing/settings.vala`: individual R/F/D, mixed policies, external-change refusal | ACL parse/policy tests | Partial: Windows/Samba effective permission enforcement, mixed filesystem ACL and guest configurations |
| Shared emblems/live inventory (3.3,3.5) | Shared state poll and immediate reconciliation; directory emblems and reload after outside policy changes | UI/shared-state component coverage | Partial: real Samba external-change/rename/removal acceptance |
| Connected clients (3.4) | Polkit service checks caller-owned usershare; bounded smbstatus JSON filtered to that share | `tests/firewall.vala` client privacy filtering | Partial: actual server sessions, authorization denial and stale/disconnected clients |
| Firewall (3.6) | `sharing-service/firewall.vala`, bundled firewalld policy, graphical opt-in/close, owned-rule validation, last-share reconciliation | Owned-policy scope/refusal tests | Partial: real firewalld runtime/permanent behavior and Polkit denial; other firewall backends are explicitly unsupported |
| Samba acceptance (3.7) | Graphical share/account/password/start/stop workflows | Component tests only | Partial: disposable Majoris VM plus Windows client still required; no developer-host Samba configuration was changed |
| Animated images (4.1) | `preview/animation.vala`, bounded sandbox frames, playback, fit/zoom, reduced motion | Real multi-frame GIF fixture | Partial: broad GIF/WebP decoder/timing fixtures and large-animation UX; WebP animation depends on installed decoder |
| RAW/HEIF/AVIF/HDR (4.2) | Installed system image decoders remain usable | Existing image tests | Partial: explicit decoder coverage, camera RAW and HDR/color-managed paths remain |
| Video/audio metadata (4.3–4.4) | `preview/media.c`, `metadata/details.vala`: streams, codecs, duration, tags, sanitized artwork, season/episode where tagged | Sandboxed generated video fixture and metadata fields | Partial: real MP4 sound, codec matrix, artwork/metadata varieties and full playback controls audit |
| Video thumbnails (4.5) | Sandboxed representative frame and existing thumbnail cache/policy | Video thumbnail fixture | Partial: remote/codecs/rotation and cache invalidation acceptance |
| Text (4.6) | GtkSourceView, syntax detection, encoding choices, binary checks, bounded content | UI text/source-view tests | Partial: broad encoding fixtures and full text keyboard/accessibility acceptance |
| Office (4.7) | Isolated LibreOffice UNO to PDF with macros/updates disabled; page navigation/zoom; explicit extracted-text fallback | Real ODT and formatted two-page DOCX rendered to PDF; DOCX indexed extraction | Partial: broader DOCX/XLSX/PPTX and legacy layout corpus, cancellation and hostile macro/link corpus |
| Remote preview/security (4.8–4.9) | Configurable policy, explicit download, bounded streaming/temp cleanup; bubblewrap isolation for metadata/image/PDF/font/Office/archive preview | Sandbox and preview fixtures | Partial: real remote failures, full parser fuzz corpus; GtkMediaFile playback still decodes in main process |
| Indexed search (5) | `search/indexed.vala`: system LocalSearch/Tracker connection, bound queries, relevance, deduplication, GIO fallback | Real PDF and DOCX extractor output indexed in TinySPARQL fixture | Partial: actual system miner/index lifecycle, stale remote content and large ranking workloads |
| Batch rename (6) | `dialogs/batch-rename.vala`, `operations/rename-plan.vala`: live preflight, ordering/metadata, swap-safe staging and grouped history | Rename template/error tests; swap/tag preservation; restarted Undo/Redo | Partial: case-insensitive backend, missing/varied real media metadata, crash during temporary staging, granular per-file progress |
| Archives (7) | `archive/sevenzip.vala`, native numbered volume reader, password stdin, compression/progress and staged outputs | Actual volume create/verify/extract/hash; encrypted create/verify; wrong-password refusal | Partial: encrypted 7z extraction compatibility, remote archive staging, broader multipart and hostile archive corpus |
| Split/join/checksum (8) | Existing filesystem limit handling, cancellation/identity cleanup, optional manifest, SHA-256/SHA-512 GUI verification | Split/join/manifests and checksum fixtures | Partial: 100 GB run, disk-full/interruption boundary corpus and arbitrary backend limit reporting |
| Ordinary actions (9.1–9.2) | Copy To/Move To/Duplicate/grouped folder/paste-link, shared operations/journal/retry | Filesystem operations and persistent history tests | Partial: every new GUI action across remote/backends, permission/cancel and Undo boundary corpus |
| Conflicts (9.3) | Size/date, replace/skip/keep both/all, merge and rename | UI merge/conflict choice tests | Partial: both sandboxed thumbnails are displayed asynchronously and covered by UI fixtures; broad conflict/backend acceptance remains |
| Replacement recovery (9.4) | `operations/replacements.vala`: durable pre-backup records, committed identity, nonoverwriting graphical recovery | Persisted interrupted-backup/new-output fixture | Partial: all output is not staged before publication; kill-at-every-boundary and directory transaction reconciliation remain |
| Remote Trash (9.5) | GIO trash errors are surfaced; permanent delete remains explicit | Existing local Trash identity/Undo fixtures | Partial: actual remote backend capability and reconciliation tests |
| Context menus (9.6) | Selection/type/native/clipboard-aware actions, extension refresh, Shift+F10/Menu | Existing action/provider tests | Partial: exhaustive mixed-selection and keyboard focus acceptance |
| Properties (10) | General/Metadata/Sharing/Permissions/Open With, EXIF/XMP/media fields, backend permission refusal | Existing multi-selection/account tests and shared metadata fixtures | Partial: real POSIX ACL/ownership authorization, remote capability UX, complete image/media field corpus |
| Cloud (11) | Existing libcloudproviders roots/status/menus/actions retained | Existing discovery code; no real per-file provider fixture | Partial: provider-neutral per-file availability/offline/materialization/progress/errors/quota and capability-driven context actions remain |
| Extensions (12) | `extensions/manager.vala`: versioned D-Bus actions/metadata/columns/Properties, opt-in user manifests, isolated example | Real separate checksum service lifecycle/action/metadata/column/property/failure/disable test | Partial: column sorting with lazy bounded cache and invalidation, broader malicious/slow/version fixtures and live enable/disable column refresh |
| Shell search (13.1) | `application/shell-search.vala`, installed SearchProvider2 registration, bounded results, activation/selection | D-Bus protocol/activation fixture in portal suite | Partial: actual shell lifecycle and desktop search UX |
| FileManager1 (13.2) | Existing D-Bus windows/select/Properties retained | Existing protocol/session tests | Partial: external desktop multi-URI and caller lifecycle acceptance |
| Nearby/desktop actions (13.3,13.5) | Existing real-provider interface, wallpaper/email portals, opt-in user scripts and extension actions | Existing mock provider/action fixtures | Partial: real transport, wallpaper/email parent integration and persistent image rotation |
| Disk images/devices (13.4) | Existing UDisks integration and mounted-location handling retained | Existing inventory tests | Partial: hardware/mount/Polkit/busy-device and filesystem acceptance |
| Grid groups (14.1) | Existing type/date/size/tag group ordering; List/Gallery section headings | Existing model grouping tests | Partial: Grid still lacks visible section headings |
| Adaptive layout (14.2) | Existing overlay sidebar retained, secondary controls/preview collapse | 500-pixel sidebar transition and other UI tests | Partial: very narrow Column/Gallery/preview, tablet, high DPI and long localized labels |
| Accessibility (14.3) | Existing controls/tooltips, keyboard navigation and context shortcuts | Headless control flows | Partial: full focus ordering, semantic names, touch, screen reader and reduced-motion audit |
| Preferences/localization (14.4–14.5) | Network/indexing/extension preferences, gettext initialization/POTFILES/template generation | Template target builds | Partial: remaining dynamic strings, translations/catalogs and locale acceptance |
| Performance (15) | Bounded async directory/search/preview work; optional directory benchmarks | 10k: 0.279 s / 59,424 KiB RSS; 100k: 2.743 s / 378,184 KiB RSS; main-loop heartbeats verified | Partial: complete view sorting/filtering, thumbnails, huge search/archive/split workloads, long sessions and leak profiling |
| Packaging (16) | Debian dependencies updated, optional example, service/policy/search/gettext/Office helper installed | dpkg-checkbuilddeps, staged installation, unsigned Debian binary package build including six suites; desktop/AppStream validators | Partial: Debian package builds successfully; broader package lint and exact Majoris ISO configuration/defaults acceptance remain |
| Automated/system testing (17–18) | Core/filesystem/UI/portal/session/firewall suites and separate real Flatpak harness | See reproducible commands below | Partial: all unexecuted cases listed above remain release gates |

## Reproducible verification

On the supported Debian toolchain with dependencies from `debian/control`:

```sh
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
meson test -C build --benchmark --print-errorlogs
meson compile -C build majoris-files-pot
DESTDIR="$PWD/build/staging" meson install -C build --no-rebuild
dpkg-checkbuilddeps
```

The real Flatpak fixture additionally needs Flatpak, xdg-desktop-portal,
xdg-desktop-portal-gtk, FUSE, Xvfb and an available document-portal FUSE mount.
It creates private application/runtime/configuration data and a minimal test
runtime from installed runner libraries. It does not install production libraries
or remotes into the user's Flatpak installation. On WSL, run in a private mount
namespace (replace 1000 with the unprivileged runner UID):

```sh
sudo unshare --mount --propagation private env MAJORIS_TEST_UID=1000 \
  python3 tests/flatpak-session.py build/flatpak-client build/flatpak-host \
  --privileged-namespace
```

Only the namespace setup is privileged; clients and desktop services run as the
specified unprivileged UID. The fixture replaces `/run/user` only inside that
private namespace. Network namespace sharing is required for Xvfb's abstract X11
socket on this runner; the app receives no general host filesystem grant.

Run remaining Windows SMB/firewall, Wayland parenting, USB, cloud and sound
acceptance in a disposable Majoris VM with dedicated fixture data. Record version,
backend, denied authorization, cancellation, disconnection and saved-byte results.
No such tests are claimed by headless WSL component coverage.

## Executed verification snapshot

On Debian 13 WSL (GTK 4.18.6, libadwaita 1.7.6, Vala 0.56.18): all six suites
passed (18 core, 11 filesystem, 25 UI, 5 portal/extension/shell and 2 firewall/client
cases, plus the session script). Eleven real Flatpak caller flows passed through
the public and document portals. The generated DOCX retained its two-page structure
and both pages' expected text in the rendered PDF. Translation-template generation,
staged installation, build-dependency checking and desktop/AppStream validation
passed. The unsigned amd64 package and debug-symbol package built in an isolated
Linux source copy, including the same six test suites. Packages are development
artifacts; these results do not close the remaining release gates in the table.
