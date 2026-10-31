# Tags

Tags have stable database identities. Files owns the tag data and behaviour;
Majoris-Theme continues to own all control, dialog, sidebar and menu styling.
There are no new CSS rules in Files. Only user-supplied tag colours are drawn by
`TagMarker`; a tag without a colour uses a neutral outlined marker.

## Storage and migration

The existing SQLite database, WAL/full-sync durability and recovery workflow are
retained. The new tables are:

```sql
CREATE TABLE tag_definitions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE COLLATE BINARY,
  color TEXT NOT NULL DEFAULT '',
  position INTEGER NOT NULL DEFAULT 0,
  sidebar_visible INTEGER NOT NULL DEFAULT 1
);
CREATE TABLE file_tag_assignments (
  uri TEXT NOT NULL,
  tag_id INTEGER NOT NULL REFERENCES tag_definitions(id) ON DELETE CASCADE,
  ordinal INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (uri, tag_id)
);
CREATE INDEX assignments_by_tag ON file_tag_assignments(tag_id, uri);
CREATE TABLE tag_uri_aliases (
  name TEXT PRIMARY KEY,
  tag_id INTEGER NOT NULL REFERENCES tag_definitions(id) ON DELETE CASCADE
);
```

The URI primary key indexes file membership; the reverse index serves collection
lookups. `ordinal` preserves legacy assignment display order. Definitions use
exact UTF-8/BINARY uniqueness: `Work` and `work` are separate tags; exact duplicate
names are rejected. New names support Unicode, are limited to 128 characters,
and reject surrounding whitespace, commas and control characters. Existing
legacy names are retained, including names outside the new editor's limits.

A single `BEGIN IMMEDIATE` transaction imports explicit definitions, preserves
names/colours/positions, discovers implicit CSV names, deduplicates relationships,
creates aliases, adds missing defaults, and writes `state['tags-schema-v1'] =
'complete'`. Failure rolls back all new tagging tables and relationships and
leaves the store unavailable with its existing recovery path. The marker is
checked again after obtaining the transaction lock, so concurrent startup does
not rerun migration.

The five initial definitions are Work/#EF4444, Projects/#F59E0B,
Personal/#3B82F6, Important/#A855F7 and Archive/#9CA3AF, in that order and initially
visible. Existing exact-name matches retain their definitions and assignments;
missing defaults are appended after existing ordering. Defaults are seeded once,
not reconciled on every launch. Renaming or deleting one never recreates it.
AUTOINCREMENT prevents historical deleted IDs being reassigned to another tag.

Legacy tables/CSV columns are retained as inert recovery snapshots. Normal UI,
search and grouping do not read them. Compatibility string methods adapt to the
relational tables and never write a competing CSV source of truth.

## Interfaces

Manage Tags uses a native PreferencesDialog/ListBox. New Tag creates a focused
inline editor. F2/Rename, Enter, Escape and focus departure handle rename; errors
stay beside the editor. Each row has a colour marker and a labelled sidebar
visibility switch. Rows reorder through native drag/drop or Alt+Up/Alt+Down.
Native sorting retains the row objects, focus and selection. Delete Tag is one
selection-level action with an explicit confirmation that files are preserved.

The palette offers seven named presets, No Colour and GTK's native ColorDialog
for custom opaque colours. Native toggle state identifies a selected preset;
custom selection is labelled. Colours never become row backgrounds or file-name
text colours.

The shared TagAssignmentDialog is opened from Tags… and Properties/General/Tags.
It filters definitions case-insensitively and displays native checked, unchecked
and inconsistent states. A mixed/unchecked tag is added to the entire captured
selection; removing a checked tag removes only that relationship. Other tags and
Favorites remain intact. Each bulk operation commits once and notifies once.
Creating a tag here creates its definition and all selected relationships in the
same transaction. Hidden sidebar tags remain available in this dialog.

Properties retains its compact summary and shows up to three colour markers for
a common tag set. Multiple differing sets display Mixed tags. The main context
menu stays text-only with one Tags… action; Manage Tags… appears once in the
application menu, with no new toolbar button.

## Sidebar, collections and file operations

Visible tags appear in their configured order after Devices and before
Network/Trash. The same MetadataStore instance feeds Places and the Browser.
Definition changes update the tag projection without re-enumerating physical
devices. Membership changes do not rebuild the sidebar. GTK marker drawing uses
the existing sidebar row/heading/hover/selection treatment.

New locations use `majoris:///tag-id/<id>`. Legacy `majoris:///tag/<encoded-name>`
locations resolve through explicit aliases and then names; numeric legacy names
are never interpreted as IDs. A rename retains the collection URI, history and
session identity. Hiding only removes the sidebar shortcut. Deleting redirects
an open collection to Favorites. Empty collections use a native empty-state page.
Unavailable files are skipped without deleting assignments or definitions.

Tag collections expose real GFiles from any directory, are virtual/read-only
destinations, show source locations, and retain normal opening, preview,
clipboard, inline/batch rename, Trash, Properties, Favorites and source-folder
navigation. Grid, List and Gallery work normally; Columns uses the existing
virtual-collection List fallback. Membership refresh preserves matching selected
URIs and restores scrolling, with generation checks against stale navigation.

Sidebar tag DropTargets use the normal file-list payload and GTK feedback. They
call only the bulk assignment API. They do not dispatch copy/move/link jobs or
conflict dialogs. Virtual object payloads are rejected; files dragged from a
collection still carry their underlying real URIs. Restricted choosers do not
install assignment targets or management actions.

`MetadataStore.relocate` updates memberships, metadata and identity URIs in one
transaction, including descendants of renamed/moved directories. Destination
relationships belonging to replaced objects are cleared. Existing rename,
move, batch recovery and undo/redo paths already call this method. Copy retains
the established policy: source tags are not implicitly propagated to new copies.

Search/grouping use relationships. Saved-search v4 stores a resolved tag ID and
reads v1–v3 formats; renames do not detach an already resolved tag filter. Group
by Tags retains the existing sorted combination and Untagged policy.
Native chooser selection returns the real URI. Save and creation
controls reject virtual destinations and require a real writable folder.

## Notifications and lifecycle

Definition, assignment and general metadata signals are distinct. Bulk assignment
uses one transaction and one assignment/general event. A coalesced directory/WAL
monitor checks SQLite `data_version` to detect other connections, including the
portal process. Self-writes do not echo; definition fingerprints avoid sidebar
refreshes for unrelated external changes. UI/database observers disconnect on
close/disposal. Static drawing/sorting/callback factories avoid retaining widgets
through their own callback data.

## Verification

Build with Meson and run the existing suite, plus the dedicated `tags` and
`tags-ui` tests. For representative native screenshots with Majoris-Theme:

```
meson setup build --reconfigure
meson compile -C build
GTK_A11Y=none ADW_DISABLE_PORTAL=1 meson test -C build --num-processes 1 --print-errorlogs
python3 tools/capture-tags.py ../Majoris-Theme
```

The capture runner uses Xvfb/Openbox, xcompmgr and generated Theme CSS without installing
new system settings. It writes light/dark management, selection, palette,
creation/rename, assignment/search/mixed states, sidebar, empty/populated
collections, Properties and tag-drop results at normal scale, 2x and 125% text.
It needs GTK4/libadwaita, xdotool, ImageMagick, Openbox and xcompmgr. Screen-reader
speech and live disconnected-network recovery still need a desktop/service
session beyond the native fixture checks.

