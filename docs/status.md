# Implementation status

This is an initial implementation, **not a completed production replacement for
Nautilus**. The supplied 102-section specification and expanded section 79 remain
the acceptance criteria. A successful build is not feature completion.

Implemented: multi-window/tab browsing, navigation/history/breadcrumbs, Grid and
List views, Column selection/action integration and Gallery views, incremental monitored enumeration,
shared places/bookmarks/devices, GVfs navigation, cancellable recursive filename
search with type/MIME/size/date/tag/favorite/owner filters, saved filter persistence,
named/color/ordered tags, local birth-time identity reconciliation, metadata recovery,
native file clipboard interoperability, image/text/PDF/media and basic Markdown/archive preview,
local image thumbnail caching, asynchronous copy/move/rename/trash/delete, basic
folder merging, conflict details and rename, persistent undo/redo and identifiable
Trash undo, interrupted-job records, recursive counts and multi-item properties,
permissions with owner/group IDs and recursive file/folder modes, ACL editing
through platform utilities, batch rename with preflight,
archives, streaming split/join/checksum manifests, filesystem-limit splitting,
graphical usershares with Polkit service, and FileManager1 integration.
Home has configurable favorites/recent/download/recommendation sections with
local usage only. Crash recovery restores window/tab locations, selected tabs
and views. Tab context operations and detached-tab routing are implemented.
Native file drag/drop supports folder targets and spring navigation; folder rows
support middle-click tabs. Local text/JSON/XML content search is bounded to 4 MiB;
Search Home scans recursively. Quick Actions have a typed provider registry and
opt-in executable user scripts with confirmation and local-path arguments.
Raw numbered parts can be joined after an explicit no-manifest warning.
Background completion/error notifications have a preference. Executable file
activation asks whether to run or choose an application. FileManager1 and the
application have session D-Bus activation files.
Quick Preview arrows traverse neighboring entries when a single item is selected.
Application defaults/reset and custom-icon controls use GIO/Freedesktop metadata.
The split dialog offers decimal presets, custom binary units, part count,
filesystem-compatible sizing, destination selection and output estimates. The
service checks all output conflicts, free space, size limits and part-count limits
before opening the source stream.
Validation currently includes 35 core/filesystem/UI/portal cases plus a separate
actual-executable crash-recovery suite. This does not substitute for the platform
acceptance work below.

Expanded #79 implemented: shared Open/single/multiple/Save/folder chooser,
filters and caller choices, suggested filename and simple extension inference,
overwrite confirmation, initial/current file options, Recent/Favorites/bookmarks,
device updates, GIO remote browsing, search, previews, path entry, folder creation,
request isolation/cancellation, portal caller and Close authorization, response
normalization, external parenting, service activation and backend declaration.
Private preferences are stored per authenticated application ID, separately for
Open and Save locations, with view, preview, sidebar width and window size.
Explicit caller locations
take precedence. Missing initial folders recover to the nearest existing parent.
Symlink-folder selection is supported. Tests cover successful backend selection,
D-Bus Close, concurrent cancellation and unauthorized backend/Close rejection.

Outstanding #79 release criteria: full parent-window verification on both display
servers, complete remote/FUSE and
cloud-provider materialization handling, rich error recovery for detached devices,
accessibility audit, and actual Flatpak/document-portal end-to-end verification.
SaveFiles is not implemented or advertised (backend interface version 1).

Other outstanding specification areas include:

* Session scroll/selection/search restoration and broad tab transfer acceptance.
* Configurable columns/grouping, density, checkboxes, bookmark drop/reordering,
  cross-filesystem drop-action policy and location autocomplete.
* Full nested conflict policies, journal operation grouping/identities, remote
  Trash reconciliation, pause/resume/retry and durable job restart.
* Indexed/full-text document search and Search Everywhere across mounted roots.
* Animated image/font/full Markdown/office previews, media metadata and
  controls audit, parser sandboxing, remote thumbnail policies and non-image
  thumbnail providers.
* Friendly owner/group account pickers, ACL integration acceptance, SELinux
  metadata, custom-icon backend acceptance and association UI refinement.
* Encrypted and multi-volume archives and arbitrary filesystem capability detection.
* Samba policy separation, hidden shares, owned firewall rules, shared-folder
  inventory/status/emblems, and a full authorization/integration test fixture.
* Cloud-provider and Nearby Share integrations; disk images;
  wallpaper/image rotation; sharing portals; full preference and shortcut UI.
* Translation coverage, a11y/keyboard audit, adaptive narrow-window layout,
  packaging review and performance benchmarks.

Do not use the current tree as the default file manager/portal on a production
image until these gaps and system-level acceptance tests have been resolved.
