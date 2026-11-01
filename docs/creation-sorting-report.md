# Toolbar, inline creation and column sorting completion report

1. **Removed controls:** navigation Refresh, empty-space Refresh, and the seven
   secondary-toolbar operation buttons (New Folder, Cut, Copy, Paste, Rename,
   Share and Move to Trash). Their obsolete groups, separator and responsive
   references are gone; both rows still use Majoris.Ui.Toolbar.

2. **Preserved operations:** all existing win.new-folder, cut, copy, paste,
   rename, share-folder and trash actions remain, with context/application menus,
   shortcuts and adaptive overflow. Sharing now supplies a menu model directly.
   F5, monitoring, internal reloads, Retry, search and collection refresh remain.

3. **New Folder:** OperationManager creates a real directory immediately and
   returns GFile; Browser selects, scrolls and starts the existing inline editor.
   Escape retains the folder. Enter only renames the existing object.

4. **New File:** the shared path creates an empty extensionless file with async
   GIO and closes its stream before recording history. Inline naming uses the
   normal rename operation, including extension warnings.

5. **Collisions:** exclusive mkdir/create retries EXISTS as New Folder/New File,
   then (2), (3), etc. Files and folders both reserve names; no overwrite or
   preliminary query-then-create race is used.

6. **Async coordination:** captured Browser, destination, selection model and
   creation epoch guard editor activation. DirectoryModel waits on settlement,
   queries real metadata and merges by GFile identity. Pending activation listens
   to selection-model item changes and directory completion, and disconnects on
   success, cancellation or directory failure. Either monitor/callback
   order works. Navigation, tab/view changes and cancellation invalidate focus
   requests while retaining successful filesystem creation.

7. **FilenameCell reuse:** no new editor was added. The same item-associated
   InlineRename transaction handles all views, grouping, recycling, selection,
   scrolling, validation, Enter, Escape, Tab and focus-leave submission. Monitor
   reload completion re-presents an active editor at its current sorted position.

8. **History safety:** CREATE_FILE is appended as enum value 8; existing kinds
   and v1/v2/v3 journal parsing remain compatible. Undo checks identity and refuses
   a nonempty new file or nonempty new folder. Empty files go to Trash. Redo
   creates exclusively and updates matching dependent redo guards after a new
   identity is assigned, including successive renames. Failed renaming leaves
   creation history intact.

9. **Native headers:** ColumnViewColumn sorters and ColumnViewSorter primary
   column/order notifications feed Browser.set_sort(). Header clicks use GTK's
   native interaction and indicators, without custom gestures or styling.

10. **Shared sorting:** the existing Browser sorter orders every view; native
    header sorting is an input to that state, not another ordering layer. Numeric
    size, timestamp seconds/microseconds, natural names, provider comparison,
    Folders First and grouping remain shared. URI tie-breaking stabilizes equal
    names from different locations; selections restore by URI in all contexts,
    including Folders First changes. Child columns wrap their directory models
    with the shared sorter and activate the item from the sorted model.

11. **Descending fix:** win.descending toggles direction on current.sort_key.
    It no longer substitutes Name. Existing named sort actions remain available.

12. **Consistent indicators:** guarded sort_by_column() updates native headers;
    Browser radio/check actions expose all supported keys in Sort menus. View
    Settings, window action states, folder preferences and tabs follow that state.
    Async extension failure restores the applied header state; removed extension
    columns cancel pending preparation and cannot stay active.

13. **Responsive/chooser:** wide toolbars emphasize view configuration; narrow
    overflow preserves file actions and dynamic Share. Location/search/view
    controls retain the existing adaptive architecture. Eligible chooser New
    Folder uses inline creation; pending renaming cannot return a stale URI.
    Empty child-column focus/clicks set the correct physical destination and
    invalidate old creation requests when the column context changes.
    New File is not exposed in restricted chooser modes.

14. **Modified files:** browser.vala, filename-cell.vala, directory-model.vala,
    manager.vala, window/window.vala, chooser/window.vala; tests/toolbars.vala,
    tests/menus.vala; new tests/creation-sorting.vala; meson.build; README.md,
    docs/toolbar-integration.md, docs/menus.md, docs/architecture.md and the new creation/sorting docs;
    tools/capture-creation-sorting.py and generated evidence. No application CSS
    or Theme source was modified. The pre-existing Majoris-Files.zip is untouched.

15. **Build:** Meson configuration and compilation were executed in Debian WSL
    with GTK 4.18.6 and the installed majoris-ui-gtk4 library. Full compilation
    succeeded. Configure/build logs are saved with the evidence.

16. **Automated verification:** all 22 Meson suites passed with zero failures,
    skips or timeouts. The 10,000-file directory benchmark enumerated in 0.356 s,
    recorded 329 main-loop heartbeats and reported 60,728 KiB RSS. Coverage
    includes 1,500-item creation across all four views and grouped Grid, real
    X11 header clicks (Name, Size, Type, Modified, Created, Accessed and provider),
    sort-menu synchronization, async D-Bus extension success/failure/removal,
    numeric bytes, natural numeric names, Unicode/multi-selection, missing
    metadata, equal-name URI ties, non-sortable headers, empty directories,
    Folders First and grouping, nested-column creation/sorting, persistence,
    tabs, monitor ordering, chooser modes, journal reload, rename chains,
    conflicts, invalid names, modified files and nonempty folders.

17. **Visual verification:** light/dark capture runs passed with the supplied
    Majoris Theme. Required captures were visually reviewed: clean desktop/narrow
    toolbars, the real-pointer empty-space menu, inline creation in all views and
    a nested column, and single active Name/Size/Modified sort indicators.
    The [evidence index](../artifacts/creation-sorting/README.md) links the captures. The capture runner activates the Theme in isolated GTK
    configuration and uses the installed Toolbar library; it does not add Files
    styling. Large grouped views are functionally tested without a full-tree
    bitmap capture.

18. **Platform limits:** execution uses headless WSL/X11, rather than a live
    Majoris desktop. Real SMB/SFTP connections, live provider outages and physical
    devices were not exercised. Backend failures propagate through GIO. Undo
    retains new files when their backend does not support Trash. Headless GTK
    tests run with GTK_A11Y=none because no stable accessibility bus is available.
