# Architecture

Files is a Vala application using GTK4, libadwaita, GIO and Meson. The executable
is `majoris-files`, the application ID is `com.majoris.files`, and UI and service
classes live in the `MajorisFiles` namespace.

`DirectoryModel` incrementally enumerates batches of 128 entries, owns its
cancellable and GFileMonitor, and coalesces monitor events. Each `Browser` owns
its history, filters, selection, search and preview lifecycle. Files tabs and
`ChooserWindow` use this same browser. `Places` shares GTK bookmark storage and
uses GVolumeMonitor for attached devices; network navigation uses GVfs and
GtkMountOperation instead of handling credentials itself.

`MetadataStore` uses parameterized SQLite queries for favorites, multiple tags,
saved searches and state. Browsing continues if metadata storage cannot open.
Recovery preserves the original database and sidecars before creating a new one.
Managed rename/move updates URI records; local enumeration reconciles device,
inode and birth-time identities where the filesystem exposes them. Existing hard
links retain their distinct paths and remote identity reconciliation remains work.

Search predicates are shared by current-folder filtering and recursive GIO
enumeration. Everywhere shares a visited-folder/result set across Home and mounted
roots, and inaccessible folders are counted. Saved searches retain scope and typed
filter values and accept legacy plain
filename queries. Native clipboard publication provides GdkFileList, URI lists
and GNOME copy/cut data; paste reads the current desktop clipboard asynchronously.

`OperationManager` maintains concurrent cancellable jobs and a journal for
rename, move, folder creation and non-replacing copies. Replacement retains the
previous destination at a temporary sibling until transfer succeeds. Copy undo
requires confirmation and moves copied content to Trash, since it may have been
edited since the copy. History is private SQLite state; backend file identifiers,
device/inode and creation timestamps are checked before reversal. Unverifiable
legacy entries are retained but cannot be reversed. History actions are serialized.
Trash undo records only
an unambiguous newly created backend entry. Merged moves journal new child
transfers and recreate missing source parents on undo. Recursive deletion does
not follow symbolic links. Interrupted jobs are reported, never silently restarted.

`SplitService` streams 1 MiB buffers, hashes while splitting, validates manifest
types, names, order, sizes and hashes, and joins to a temporary sibling before
publishing without overwrite. Missing parts and insufficient space are rejected
before output creation. Oversized regular files on known constrained
filesystems can be split after confirmation; the source is retained.

Image/text/media/PDF preview providers share one cancellable presentation layer.
Text reads at most 256 KiB; images and PDFs have explicit size limits. Media
uses GtkMediaFile and the installed GTK GStreamer backend, with autoplay off.
PDF loading/rendering and libarchive work run on worker threads. Complex parsers
are currently in-process; a parser sandbox is still required for release.
Local image thumbnails use the Freedesktop cache naming and URI/mtime metadata.

Archive extraction uses libarchive, rejects traversal, symlinks, hard links and
special files, and extracts into a newly created directory. Cancellation/failure
removes that directory. Archive creation excludes symlinks and special files,
uses exclusive creation, and removes failed output.

The chooser portal runs in a separate process. It exports
`org.freedesktop.impl.portal.FileChooser`, not the public portal interface.
Only the current owner of `org.freedesktop.portal.Desktop` can invoke it. Each
request has a separate chooser, options, cancellation and response state.
Request Close is restricted to its invoking owner; owner disappearance cancels
the chooser. X11 and Wayland parent identifiers are imported through a small
native bridge. Results contain normalized `file://` URIs; GVfs locations without
a local FUSE representation require an explicitly approved local import for Open.
Imports are retained copies in the application data directory with configurable byte/time limits, free-space checks and progress;
Save never substitutes an import for the intended remote destination. SaveFiles
uses the same request lifecycle and validates/generates destination names without
creating them. Mount removal invalidates outstanding acceptance work.
xdg-desktop-portal performs
document registration and permission mediation; Files never grants sandbox
permissions directly.

Sharing uses unprivileged Samba usershares. A narrow Polkit-protected system
service can start the fixed `smbd.service` unit and provision only the calling
non-root account's SMB credentials through stdin. It accepts neither arbitrary
commands nor arbitrary account names. Per-account R/F/D policy and owned firewalld
integration are implemented; actual server/firewall acceptance remains open.

Sharing pages and the usershare inventory read the actual Samba usershare state.
Account selection uses the shared asynchronous system account directory. Mixed
R/F/D ACLs are preserved; unsupported ACL forms are displayed without editing. System-wide
smb.conf shares remain administrator managed. Narrow browsing reparents the shared
sidebar into AdwOverlaySplitView; wide browsing retains the resizable GtkPaned.

## Reference review

The supplied Nautilus tree was inspected for directory enumeration, asynchronous
operations, symlink semantics, undo ownership, bookmark storage, search batching,
thumbnail caching, chooser modes, portal request lifecycle and D-Bus interfaces.
Relevant sources included `nautilus-file-operations.c`, `nautilus-file-chooser.c`,
`nautilus-portal.c`, `nautilus-portal-request.c`, `nautilus-bookmark-list.c`,
`nautilus-search-engine-simple.c`, `nautilus-thumbnails.c`, and the portal XML.
The implementation is independently written; reference sources are not bundled
or installed with Files.

## Additional subsystem boundaries

`ReplacementJournal` persists intent before an existing destination is renamed
aside. Recovery validates preserved identities and restores without overwriting
current data. This is not yet a fully staged transaction for every output or a
complete crash journal for batch rename staging.

The indexed search provider talks to the system TinySPARQL service through bound
queries; it never opens the system index database. Recursive GIO search reconciles
results and remains the fallback. Shell search reuses this controller.

Rich metadata and thumbnails use the preview sandbox. Formatted Office conversion
uses a trusted UNO script with macros/updates disabled and returns bounded PDF
bytes; the regular PDF presentation handles navigation. GtkMediaFile playback
still runs in the GUI process and requires further isolation work.

Extensions use versioned session D-Bus, bounded replies and deadlines, with no
in-process dynamic loading. User manifests are opt-in. The complete external
contract and its remaining limitations are in `docs/extensions.md`.
