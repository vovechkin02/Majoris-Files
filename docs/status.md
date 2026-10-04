# Implementation status

This is an initial implementation, **not a completed production replacement for
Nautilus**. The supplied 102-section specification and expanded section 79 remain
the acceptance criteria. A successful build is not feature completion.

Implemented: multi-window/tab browsing, navigation/history/breadcrumbs, Grid and
List views, initial Column and Gallery views, incremental monitored enumeration,
shared places/bookmarks/devices, GVfs navigation, cancellable recursive filename
search with type/MIME/size/date/tag/favorite/owner filters, saved filter persistence,
favorites/tags, native file clipboard interoperability, image/text/PDF/media preview,
local image thumbnail caching, asynchronous copy/move/rename/trash/delete, basic
conflicts and journal, properties/basic permissions, batch rename with preflight,
archives, streaming split/join/checksum manifests, filesystem-limit splitting,
graphical usershares with Polkit service, and FileManager1 integration.

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

* Home dashboard sections and local recommendations; session crash recovery.
* Full tab context menu/transfer behavior and middle-click on file rows.
* Column selection/action integration, configurable columns/grouping, density,
  checkboxes, drag/drop, spring-loaded navigation, and location autocomplete.
* Folder conflict merging, conflict metadata comparison and rename response,
  persistent undo/Trash undo, and durable jobs.
* Named/color/order tag management, local inode/device identity reconciliation,
  indexed/full-text search, Search Everywhere, and metadata corruption recovery UI.
* Animated image/font/Markdown/archive/office previews, media metadata and
  controls audit, parser sandboxing, remote thumbnail policies and non-image
  thumbnail providers.
* ACL/owner/group/recursive permission editing, multi-item metadata properties,
  custom icons and full application-association management.
* Encrypted and multi-volume archives, unmanifested joins, complete split dialog
  sizing/preflight UI, and arbitrary filesystem capability detection.
* Samba policy separation, hidden shares, owned firewall rules, shared-folder
  inventory/status/emblems, and a full authorization/integration test fixture.
* Cloud-provider, Nearby Share and Quick Action registries; scripts; disk images;
  wallpaper/image rotation; sharing portals; full preference and shortcut UI.
* Translation coverage, a11y/keyboard audit, adaptive narrow-window layout,
  notification policy, packaging review and performance benchmarks.

Do not use the current tree as the default file manager/portal on a production
image until these gaps and system-level acceptance tests have been resolved.
