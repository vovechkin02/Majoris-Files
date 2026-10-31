# Finder-style tags implementation report

## 1. Database schema

SQLite remains the metadata store. `tag_definitions` holds an AUTOINCREMENT identity, unique name, colour, ordering and sidebar visibility. `file_tag_assignments` relates real file URIs to tag IDs, with a composite primary key and an indexed reverse lookup. Foreign keys cascade tag deletion to relationships only. `tag_uri_aliases` supports old name-based collection links. Legacy CSV columns remain inert compatibility data; normal tag operations use relationships.

## 2. Migration

One `BEGIN IMMEDIATE` transaction imports existing definitions and explicit/implicit CSV assignments, deduplicates relationships and retains assignment ordering, custom colours, remote URIs, Favorites and unrelated metadata. A persistent completion marker is committed with the migration. Failure rolls back and reports unavailable storage rather than using a partially migrated database. Automated fixtures cover existing databases, Unicode/case-only names, repeated reopening, rollback, duplicates, implicit tags and large imports.

## 3. Defaults

The initial migration installs missing defaults in this order, visible in the sidebar:

| Tag | Exact colour |
| --- | --- |
| Work | `#EF4444` |
| Projects | `#F59E0B` |
| Personal | `#3B82F6` |
| Important | `#A855F7` |
| Archive | `#9CA3AF` |

Existing matching definitions retain their customisation. Defaults are never reseeded after migration: renamed, recoloured, reordered, hidden and deleted defaults stay that way after reopening. Tests verify all five exact initial definitions and persistence of subsequent edits/deletion. Initialisation assigns no files.

## 4. Management window

The app menu has one Manage Tags entry. Native GTK/Adwaita rows provide colour controls and sidebar switches; one Rename and one Delete action operate on the selected row. Creation and renaming are inline, with validation errors, Enter submission and Escape cancellation. F2 renames; dragging rows or Alt+Up/Down reorders. Deletion asks for confirmation and explains that files remain untouched. Names have stable identities and exact Unicode uniqueness.

## 5. Colour picker

A native arrowless popover provides Red, Orange, Yellow, Green, Blue, Purple, Grey and No Colour, with accessible labels and selected states. Custom Colour opens `Gtk.ColorDialog` with opaque colour selection. Small `Gtk.DrawingArea` markers display stored user colour data; no application CSS was added.

## 6. Sidebar

Visible tags appear beneath Devices in saved order with coloured markers and a Tags heading. Definition updates refresh this projection without volume enumeration. Assignment updates do not rebuild the sidebar. Hiding a tag retains its relationships and accessible collection URI. Metadata changes from other connections are coalesced through SQLite data-version monitoring.

## 7. Assignment window

The text-only Tags action and Properties share one searchable checkbox dialog. It retains the real file/folder selection while users search and edit. New Tag creates a definition and assigns it atomically; Manage Tags opens the shared manager. Properties shows common/mixed text and compact colour markers and refreshes as metadata changes.

## 8. Mixed selection

Checks distinguish all, none and mixed membership. Toggling applies only that tag's delta to the complete captured selection, preserving every unrelated tag. A bulk change uses one transaction and one assignment notification. Tests cover mixed selections, filtering, creation and repeated toggles.

## 9. Drag and drop

Sidebar tag targets accept real files and folders and add relationships. They do not invoke the operation manager or move/copy the originals. Native DropTarget dispatch tests cover one file, multiple files and a folder, verify membership, verify originals remain, and verify the job count does not change. Chooser mode excludes assignment drop targets.

## 10. Virtual collections

New collection URIs use `majoris:///tag-id/<id>`. Legacy name links resolve through migration aliases. Collections list the original real GFiles across directories, show locations, support selection and existing file actions, and refresh membership while preserving selection/scroll. Columns uses the existing virtual List fallback. Empty collections show a native empty state. Rename updates collection titles; deleting an open tag redirects to Favorites. Missing/unavailable files are skipped without deleting their metadata.

## 11. Search and grouping

Search uses structured membership with no new search backend. Saved-search format v4 stores a stable tag ID while retaining readers for v1–v3. Tag rename preserves the filter identity. Group by Tags retains the existing combined-label and Untagged policy, using relational queries rather than CSV splitting.

## 12. Rename and move

Existing operation hooks relocate metadata, identities and tag relationships transactionally, including descendants when a directory moves and destination replacement handling. Rename/undo and subtree relocation tests pass. Copy retains the existing policy of not propagating tags. An identity reconciliation no-op prevents repeated writes for unchanged URIs and avoids unrelated view reloads.

## 13. Open and Save dialogs

Tag navigation selects original real URIs in Open flows. Virtual collections are not writable destinations: Save/SaveMany, Select Folder with no real selected folder, and New Folder enforce real destination checks. The native chooser regression tests verify real selection output and rejection of virtual save destinations.

## 14. Modified files

Product sources: `src/metadata/store.vala`, `src/metadata/tags-dialog.vala`, `src/sidebar/places.vala`, `src/views/browser.vala`, `src/views/file-groups.vala`, `src/window/window.vala`, `src/window/extra-actions.vala`, `src/dialogs/properties.vala`, `src/search/search.vala`, `src/chooser/window.vala`, and `src/actions/registry.vala`. The menu helper also avoids replacing equivalent Share menus during unrelated updates.

Build/tests: `meson.build`, `tests/core.vala`, `tests/properties.vala`, `tests/redesign.vala`, new `tests/tags.vala` and `tests/tags-ui.vala`. Documentation/evidence: `docs/tags.md`, this report, `tools/capture-tags.py` and `artifacts/tags/`. No Files or Majoris-Theme CSS changed. Context menus remain text-only, with no per-tag submenu or separate Tags toolbar button.

## 15. Automated results

Executed under Debian WSL:

```sh
meson setup build --reconfigure
meson compile -C build -j 6
GTK_A11Y=none ADW_DISABLE_PORTAL=1 meson test -C build --num-processes 1 --print-errorlogs
```

The complete run passed **21/21 suites**, with no failures, skips or timeouts (`build/tags-completion-tests.log`). This includes existing operation, replacement, archive, filesystem, UI/session/portal, theme, sidebar, details, toolbar, inline rename, Properties and menu coverage, plus both new tag suites. After the final shared menu-button ownership correction, the build and focused checks passed again: menus (18.32 s), tags-ui (42.21 s), including the new weak-reference finalisation assertion (`build/tags-final-ui-tests.log`).

Tag coverage includes 1,000 definitions, 10,000 files, 20,000 memberships, large migration, indexed reverse-query plans, atomic rollback/bulk edits, cross-connection refresh and weak-reference finalisation of dialogs/markers. The large native assignment scenario also renders a 1,000-tag sidebar and opens a 10,000-file selection; one recorded run took about 0.89 s including a 0.5 s settle for window creation, and 0.13 s for assignment construction/state refresh. These are local measurements, not cross-platform guarantees.

## 16. Visual verification

`tools/capture-tags.py` loads the generated adjacent Majoris Theme without installing it. There are **78 PNG captures** under `artifacts/tags/normal`, `2x` and `large-text`: light and dark variants of management/defaults/selection, palette, inline creation/rename, assignment/search/mixed state, sidebar, empty/populated collections, Properties and drop assignment. Representative screenshots were inspected for labels, markers, spacing and menu decoration. Native controls supply styling and focus states. The capture runner uses ImageMagick and xcompmgr to include separate native popup surfaces and their transparency.

Examples: [defaults](../artifacts/tags/normal/manage-defaults-light.png), [palette](../artifacts/tags/normal/colour-palette-light.png), [mixed selection](../artifacts/tags/normal/mixed-assignment-dark.png), [collection at 2x](../artifacts/tags/2x/populated-collection-dark.png), [enlarged-text editor](../artifacts/tags/large-text/inline-create-dark.png).

## 17. Validation limits

Automated UI checks run in Xvfb/Openbox with GTK accessibility disabled for the headless environment. Accessible labels and checkbox states are present, but live screen-reader speech was not tested. The headless Cairo/native colour-chooser run emits nonfatal pixman rectangle diagnostics; the chooser selection assertions pass and the composited palette captures render correctly. Remote URI migration is tested; live disconnected remote servers and removable-volume reconnection need the corresponding services/devices. The copy policy intentionally remains unchanged. No unrelated ZIP attachment was modified, and no global theme was installed.
