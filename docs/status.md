# Implementation status

This is an initial implementation, **not a completed production replacement for
Nautilus**. The supplied 102-section specification and expanded section 79 remain
the acceptance criteria. A successful build is not feature completion.

Implemented: multi-window/tab browsing, navigation/history/breadcrumbs, Grid and
List views, Column selection/action integration and Gallery views, incremental monitored enumeration,
shared places/bookmarks/devices, GVfs navigation, cancellable recursive filename
search with type/MIME/size/date/tag/favorite/owner filters, saved filter persistence,
named/color/ordered tags, local birth-time identity reconciliation, metadata recovery,
native file clipboard interoperability, image/text/PDF/media and CommonMark/archive preview,
local image thumbnail caching, asynchronous copy/move/rename/trash/delete, basic
folder merging, conflict details and rename, persistent undo/redo and identifiable
Trash undo, interrupted-job records, recursive counts and multi-item properties,
permissions with owner/group IDs and recursive file/folder modes, ACL editing
through platform utilities, batch rename with preflight,
archives with AES-256 ZIP creation and password-based extraction, streaming
split/join/checksum manifests, filesystem-limit splitting,
graphical usershares with Polkit service, and FileManager1 integration.
Home has configurable favorites/recent/download/recommendation sections with
local usage only. Crash recovery restores window/tab locations, selected tabs
and views. It also restores search filters/scopes, selected files and scroll
positions in Grid/List/Gallery. Column sessions now store the root and column chain,
per-column selections and scroll positions; local selection recovery is tested.
Remote/disconnected column chains still need platform acceptance.
Tab context operations and detached-tab routing are implemented.
Native file drag/drop supports folder targets and spring navigation; folder rows
support middle-click tabs. Bookmark drags reorder entries and preserve labels using
optimistic concurrency checks. File drops move within a verified local filesystem,
copy across filesystems or when identity cannot be verified, and honor Ctrl copy,
Shift move and Ctrl+Shift local symbolic links. Links use cancellable operations and
identity-checked persistent undo/redo. Local text/JSON/XML content search is bounded to 4 MiB;
Search Home scans recursively. Search Everywhere scans Home and mounted roots,
deduplicates overlapping roots, reports unreadable folders and closes cancelled
enumerators. Saved searches preserve their scope and accept earlier formats.
Quick Actions have a typed provider registry and
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
Per-folder view controls offer compact/standard/large icons, selection checkboxes,
folders-first/mixed sorting, additional sort fields, and 14 metadata columns with
visibility, order and width controls. Grid metadata captions are configurable per
folder. Extension column providers supply display text and comparison for sorting.
Column browsing cancels stale loads and disconnects removed branch selections.
Per-folder grouping supports type, modified-date ranges, size ranges and tag sets.
List/Gallery show section headings; Grid preserves grouped ordering. Tag groups
refresh when metadata changes, and sorting remains available within groups.
Location entry suggests recent paths and
matching folders, with bounded cancellable enumeration and credential-free history.
Unavailable locations have a Retry banner in both file browsing and the chooser.
PDF, image, font, CommonMark and archive previews use a bubblewrap helper with no network or
home-directory access, read-only input, process time/memory limits and cancellation.
Image previews support fit/zoom, EXIF orientation and preview rotation.
Markdown offers Source/Rendered views with styled headings, emphasis, strong text,
code, lists, quotes and link labels. Embedded HTML/JavaScript and image URLs remain
inert text; the renderer performs no downloads or code execution. Font samples
include family/style, alphabet, digits and a sentence. Image/PDF thumbnail providers
use the helper and the freedesktop cache. At most four helper processes run at once.
Undo/redo stores file identities, refuses replacement files and serializes history
actions; legacy history without identities cannot safely be reversed.
Failed/cancelled copy, move and link jobs can retry remaining top-level items in the
current session. Completed items are not replayed; retries retain ordinary conflict
checks. Failed jobs preserve progress and cancellation is shown explicitly.
Nested merge conflicts offer Rename, Keep Both, Replace, Skip, Replace All and
Skip All with both sizes and timestamps. All-item policies apply through the job's
nested conflicts; replacement backups are restored if transfer fails.
Permissions offer asynchronous platform account/group lookup and numeric fallback;
properties show SELinux context where available.
Multi-selection properties list types, shared location, common tags and permissions,
update recursive byte totals, and open the permissions editor for the captured
selection. Bulk favorite controls reflect whether all selected items are favorites.
Disk-image quick actions delegate read-only loop creation, partition/filesystem
mounting and unmount/detach to UDisks. Inventory selection is tested; actual mounts,
Polkit cancellation and busy-device handling require a disposable Majoris VM.
Validation currently includes 42 core/filesystem/UI/portal cases plus a separate
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
cloud-provider materialization handling, complete recovery for detached devices,
accessibility audit, and actual Flatpak/document-portal end-to-end verification.
SaveFiles is not implemented or advertised (backend interface version 1).

Other outstanding specification areas include:

* Remote/disconnected Column-view recovery and broad tab transfer acceptance.
* Broad external drag negotiation/tab-hover acceptance and Grid section headings.
* Conflict thumbnails, journal operation grouping, remote
  Trash reconciliation and durable job restart. Current GIO transfers do not offer
  a safe pause/resume facility; pause controls are intentionally unavailable.
* Indexed/full-text document search and indexed relevance ranking.
* Animated images, office previews, media metadata and controls
  audit, remaining media/cache parser isolation, remote thumbnail policies and
  thumbnail providers beyond image/PDF.
* ACL integration acceptance, custom-icon backend acceptance and association UI
  refinement.
* Encrypted 7z creation, multi-volume archive creation and arbitrary filesystem
  capability detection. ZIP encryption protects contents; entry names remain visible.
* Samba policy separation, hidden shares, owned firewall rules, shared-folder
  inventory/status/emblems, and a full authorization/integration test fixture.
* Cloud-provider and Nearby Share integrations; disk-image system acceptance;
  wallpaper/image rotation; sharing portals; full preference and shortcut UI.
* Translation coverage, a11y/keyboard audit, adaptive narrow-window layout,
  packaging review and performance benchmarks.

Do not use the current tree as the default file manager/portal on a production
image until these gaps and system-level acceptance tests have been resolved.
