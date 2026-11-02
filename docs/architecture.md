# Architecture

Files is a Vala application using GTK4, libadwaita, GIO and Meson. The executable
is `majoris-files`, the application ID is `com.majoris.files`, and UI and service
classes live in the `MajorisFiles` namespace.

`DirectoryModel` incrementally enumerates batches of 128 entries, owns its
cancellable and GFileMonitor, and coalesces monitor events. Each `Browser` owns
its history, filters, selection, search and preview lifecycle. Files tabs and
`ChooserWindow` use this same browser and `Places` composition. The sidebar uses
XDG standard folders, one root filesystem entry and GVolumeMonitor device events;
GTK bookmarks never populate it. Collections and cloud accounts remain accessible
in the shared locations menu. Network navigation uses GVfs and
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
rename, move, folder and empty-file creation, and non-replacing copies. Replacement retains the
previous destination at a temporary sibling until transfer succeeds. Copy undo
requires confirmation and moves copied content to Trash, since it may have been
edited since the copy. History is private SQLite state; backend file identifiers,
device/inode and creation timestamps are checked before reversal. Unverifiable
legacy entries are retained but cannot be reversed. New-file creation undo refuses
nonempty files and uses Trash; new-folder undo refuses nonempty folders. Redo
recreates exclusively and retargets matching dependent identity guards so later
renames remain reversible. History actions are serialized.
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
Text reads at most 256 KiB; images and PDFs have explicit size limits. Complex
preview decoders run in bounded bubblewrap workers with read-only input and no
home/network. Media uses the isolated GStreamer playback worker and a GtkMediaStream
adapter receiving validated raw RGBA/PCM, with autoplay off. Archive operations
retain their worker/cancellation paths; encrypted 7-Zip extraction is sandboxed.
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

`ReplacementJournal` persists intent before local replacement staging. File/tree
data and containing directories are synchronized before/after atomic exchange;
unsupported exchange uses a journaled rename fallback. Snapshot guards refuse
concurrent modifications. Recovery recognizes both preserved-original locations
and never overwrites current data. Batch rename records its fixed staging paths
before moving names and commits history with journal removal in one SQLite
transaction. Image rotation preserves the original bytes for Undo; interrupted
Undo/Redo exchanges reconcile their guarded intent before further history actions.

The indexed search provider talks to the system TinySPARQL service through bound
queries; it never opens the system index database. Only completed queries with
certified scope coverage skip traversal. Unknown/excluded roots, content coverage,
remote scopes and explicit exhaustive search retain GIO reconciliation. Shell
search reuses this controller. No stale index is described as instant filesystem
consistency.

Rich metadata and thumbnails use the preview sandbox. Formatted Office conversion
uses a trusted UNO script with macros/updates disabled and returns bounded PDF
bytes; the regular PDF presentation handles navigation. GStreamer playback now
runs in a separately sandboxed worker. A GtkMediaStream/GdkPaintable adapter keeps
GTK video/audio controls, accepts bounded raw RGBA/PCM packets, supervises startup
and playback stalls, and handles seeking/cancellation/decoder failure. The GUI's
audio pipeline accepts PCM only and does not demux/decode the source file.

Image helpers use LibRaw, libheif and LittleCMS, including supported timed AVIF
sequences and PQ/HLG-to-SDR conversion. Grid grouping uses a virtualized row model
with section boundaries and bounded grid slices sharing the existing selection.
Cloud state is a separate capability-driven adapter interface over provider-owned
GIO entries; account discovery alone never fabricates per-file state.

Extensions use versioned session D-Bus, bounded replies and deadlines, with no
in-process dynamic loading. User manifests are opt-in. The complete external
contract and its remaining limitations are in `docs/extensions.md`.

## GtkBuilder composition and resource ownership

Future declarative UI belongs in `data/ui/*.ui`, rather than in procedural Vala
widget assembly. XML owns permanent hierarchy, static labels, menus, control
properties, accessibility and shared Theme classes. Vala owns dependency
injection, actions, filesystem work, async lifetimes, models and runtime content.
Majoris-Theme owns visual presentation; Files does not install a CSS provider.

`data/files.gresource.xml` bundles every interface under `/com/majoris/files/ui/`.
Meson compiles the resource into `core` exactly once per executable. This is
intentional: `Dialogs` is also used by core-only operation tests, so its prompt
and password templates must be available without linking the complete browser.
The application, portal, visual fixtures and separately linked tests all receive
their own registered resource. Installed binaries never read source-tree UI files.

Application-owned reusable widgets use Vala composite templates:

```vala
[GtkTemplate (ui = "/com/majoris/files/ui/example.ui")]
public class Example : Gtk.Box {
    [GtkChild] private unowned Gtk.Label summary;
    public Example(MetadataStore metadata) {
        // Bind injected state and application behavior after template initialization.
    }
}
```

The template GType is `MajorisFilesExample`, with a parent matching the Vala
class. Template child IDs match the bound fields. Widgets instantiated *inside*
another template are constructed through GObject, which does not invoke a Vala
creation method: constructor-independent wiring belongs in `construct`, and
dependency-dependent wiring belongs in an explicit `configure` method. Custom
child GTypes are ensured in the owner's static construction before instance
initialization. `FilenameCell` uses `construct` for this reason.

Each template class clears its children with `dispose_template(typeof(Class))`
before chaining to its parent's dispose method. Clear an owned native single-child
property (`child`, `content` or `extra_child`) first, so the native parent does not
retain a stale child pointer. Stop owned async work and disconnect external
signals before clearing child bindings; callbacks that can run during teardown
check the component's disposal flag.

Native final types, including GtkStack and GtkScrolledWindow, are composed inside
templates or loaded from small standalone resources. Known children in composite
templates use GtkChild bindings; standalone resources are parsed at creation or
factory setup, never on ordinary row updates. Template adapters live beside their
subsystems (`views/item-widgets.vala`, `dialogs/ui-components.vala`,
`preview/ui-components.vala`, `sharing/ui-components.vala`).

## Shared controls and runtime UI

Browser's permanent split views, scrollers, view stacks, native file views,
preview panes, recovery slot and status area are in `browser.ui`. Navigation
fields use `navigation-fields.ui`; responsive search/sidebar reparenting remains
Vala behavior. Both toolbars remain `Majoris.Ui.Toolbar`. Static controls are
loaded once from `navigation-controls.ui`, and enter the toolbar through
`append_control`, `append_widget`, `append_spacer` and supported group APIs. The
preview toolbars use the same contract with `preview-controls.ui`. Raw GtkBuilder
packing must not bypass the shared control setup. No shared Toolbar ABI change
or Files-specific toolbar implementation is required.

Grid tiles and file rows use `grid-item.ui` and `list-item.ui`; Columns and Gallery
reuse the latter. Metadata cells and sidebar/tag rows have their own templates.
FilenameCell exposes its label as a GtkBuilder internal child, so Grid/List XML
configures wrapping and alignment on the same label used by inline editing.
SignalListItemFactory remains necessary because Browser owns identity-based edit
transactions, selection contexts, thumbnails, controllers and explicit unbinding.
BuilderListItemFactory cannot replace those bind/unbind responsibilities with
simple property expressions. Templates are constructed during setup, with models
and data updated during binding; views remain virtualized.

Runtime construction is limited to models/controllers, shared Toolbar creation,
temporary native alerts/services, data-driven breadcrumbs/completions, virtualized
group slices, arbitrary provider metadata and native single-widget data leaves.
Repeated multi-widget presentations use templates even when their instances are
created in response to runtime data. The line-by-line exceptions are recorded in
[`ui-construction-audit.md`](ui-construction-audit.md), regenerated with
`python tools/audit-ui-construction.py` and checked by Meson.

`menus.ui` defines application, tab, selection and custom-icon menus. Static
address commands are bundled with the navigation controls. Extend those models in
XML; compose selection/capability/provider-dependent sections in Vala. Actions
still resolve through their original widget ancestry (`app`, `win`, `place`,
`identity` and provider groups); resource ownership does not establish action
scope. Popovers retain the native menu presentation without pointer arrows.

## Adding and checking interfaces

For a new dialog or reusable row, add its focused `.ui` file and Vala template
adapter, preserve injected constructor parameters, and add the source to Meson's
appropriate core/UI source set. Register the resource in `files.gresource.xml`,
the XML path in `po/POTFILES`, and its GType in `tests/ui-resources.vala`. Static
user-facing strings use `translatable="yes"` and the `majoris-files` domain.
Gettext language autodetection handles both Vala and GtkBuilder XML; forcing the
entire extraction to C# would silently omit XML messages.

The default build checks XML syntax, resource coverage, duplicate IDs/properties,
GtkChild/GtkCallback names, translation extraction membership, template parents
and the absence of application CSS. Runtime tests register and construct every
template, parse every standalone resource, and exercise window action ancestry
and the overview callback. GtkBuilder's own validator checks standalone native
resources. Existing UI, portal, operation, menu, tag, property and inline-edit
tests continue to verify behavior. Run:

```sh
meson setup build --reconfigure
meson compile -C build
ADW_DISABLE_PORTAL=1 meson test -C build --num-processes 1 --print-errorlogs
python tools/audit-ui-construction.py --check
```

Serial execution avoids exhausting a desktop session's per-user inotify limit
when many isolated GVfs/D-Bus graphical fixtures start simultaneously. It does
not omit or disable tests.

All styling comes from GTK/libadwaita and Majoris-Theme. The status area uses the
existing `majoris-statusbar` contract. Data, location, sidebar-heading, document-tab
and toolbar class families match the shared Theme templates. The existing
`files-sidebar` class is retained as a semantic test/inspection hook; it has no
Files stylesheet or replacement styling rule.
