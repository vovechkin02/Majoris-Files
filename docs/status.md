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
Untrusted cached thumbnails are validated and decoded in the sandbox; only
sanitized output is decoded in the UI. Font thumbnails are supported. Thumbnail
preferences offer Local/All/Never; remote downloads have byte and time limits,
at most two concurrent downloads, private temporary files and cleanup on cancellation.
Office/OpenDocument ZIP formats have sandboxed bounded text previews; formatting,
images, spreadsheet formula evaluation and legacy binary Office formats are omitted.
Preferences now cover activation mode, folder/view/density defaults, extension
display and rename warnings, selection checkboxes, hidden files, delete confirmation,
per-folder memory, recursive search, previews, thumbnails, media auto-play and Home.
The keyboard-shortcuts dialog is available from the menu and Ctrl+?.
Desktop actions use the Wallpaper and Email portals; wallpaper has desktop preview
and email opens a composer with attachments. Nearby Share has a typed provider
interface and a tested device-selection/confirmation workflow; transport belongs
to an installed provider and no custom wireless protocol is implemented.
libcloudproviders accounts supply sidebar roots, icons, sync/error status and
provider-owned account actions, with live account/provider updates.
Undo/redo stores file identities, refuses replacement files and serializes history
actions; legacy history without identities cannot safely be reversed.
New multi-file jobs share a persistent journal group. Undo/redo preflight every
group identity before reversal. History is capped at 100 entries; whole groups are
discarded at that limit rather than advertising a partial operation as undoable.
Failed/cancelled copy, move and link jobs can retry remaining top-level items in the
current session. Verified source/destination retry plans are persisted and restored
for explicit retry after restart. Restored retries refuse replaced sources or target
folders, and never auto-resume. Completed items are not replayed; retries retain ordinary conflict
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
Validation currently includes 51 core/filesystem/UI/portal cases plus a separate
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
SaveFiles is implemented through the existing isolated request lifecycle (backend
interface version 1; the backend interface does not use the public portal's version
numbers). It selects a destination folder, validates bounded NUL-terminated names,
preserves caller order and generates unique names for existing and repeated outputs.
It never creates the returned destinations. D-Bus roundtrip tests cover this flow.
Non-FUSE remote Open selections offer an explicit, durable local import, limited
to 64 MiB and 60 seconds. The UI explains that edits do not update the original.
Remote Save and folder selection still require a usable GVfs/FUSE bridge; no
temporary-file writeback is advertised. Removed mounts invalidate pending chooser
acceptance, clear selections and navigate Home with an error message. Real removable
device and remote document-portal acceptance remain pending.


Narrow browsing now moves the locations sidebar into an Adwaita overlay below
650 pixels, with the locations toggle opening that overlay. Navigation dismisses
it. Wide windows retain the resizable paned sidebar. Secondary toolbar controls
and the preview pane collapse; view selection remains in View Settings.
Narrow preview requests open the existing preview dialog. The browser
sets an explicit minimum size for Adwaita breakpoint allocation. Headless visual
acceptance covers a 500-pixel window; very small windows,
remote locations and a full keyboard/accessibility audit remain pending.
Other outstanding specification areas include:

* Remote/disconnected Column-view recovery and broad tab transfer acceptance.
* Broad external drag negotiation/tab-hover acceptance and Grid section headings.
* Conflict thumbnails, remote
  Trash reconciliation, durable replacement-backup transaction recovery, and
  interrupted-job acceptance for archives/permissions/other operations. Current GIO transfers do not offer
  a safe pause/resume facility; pause controls are intentionally unavailable.
* Indexed/full-text document search and indexed relevance ranking.
* Animated images, formatted/legacy Office previews, media metadata and controls
  audit, remaining media parser isolation, remote thumbnail platform acceptance and
  thumbnail providers beyond image/PDF/font.
* ACL integration acceptance, custom-icon backend acceptance and association UI
  refinement.
* Encrypted 7z creation, multi-volume archive creation and arbitrary filesystem
  capability detection. ZIP encryption protects contents; entry names remain visible.
* Samba policy separation, hidden shares, owned firewall rules, shared-folder
  live status/emblems, and a full authorization/integration test fixture.
* Cloud quota/per-item availability/materialization extensions and real-provider
  acceptance; Nearby Share transport-provider/system acceptance; disk-image system
  acceptance; wallpaper/email portal acceptance and file image rotation; indexing
  and network preference UI.
* Translation coverage, a11y/keyboard audit and broad adaptive acceptance,
  packaging review and performance benchmarks.

Do not use the current tree as the default file manager/portal on a production
image until these gaps and system-level acceptance tests have been resolved.

## Current implementation pass

Sharing now queries `net usershare info --long` for current usershare state, exposes
the same Sharing page in folder Properties and the standalone sharing dialog,
offers a graphical multi-account picker and lists usershares in Shared Folders.
The inventory provides Open, Edit, Copy Address and Stop Sharing. Unresolved ACL
accounts remain visible and removable. Advanced/mixed ACLs disable editing rather
than being silently widened. Share names are locked while editing an existing share.
Filesystem permissions remain authoritative. These changes do not complete hidden
shares, firewall policy, emblems, connected-client status or SMB enforcement acceptance.

Checksums now expose SHA-256/SHA-512 calculation and verification against a pasted
value or a bounded GNU-style checksum file. File records are matched by filename;
missing and duplicate matches fail. Cancellation/error closes checksum streams.
Raw splitting has an optional SHA-256 manifest setting, enabled by default.
Audio previews use a dedicated presentation and GTK playback controls; stream
metadata, artwork, decoder isolation and actual codec playback acceptance remain open.

See [the release matrix](release-matrix.md) for changes, code paths, coverage and
unresolved requirements. The original 102-section specification and the full
expanded Section 79 text are not present in this checkout or the supplied task
attachment; full comparison against those documents remains pending.
