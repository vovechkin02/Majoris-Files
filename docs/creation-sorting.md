# Inline creation and shared column sorting

Both browser bars still use the installed Majoris Toolbar. Navigation Refresh and
the empty-space Refresh menu entry are removed. New Folder, Cut, Copy, Paste,
Rename, Share and Trash no longer create secondary-toolbar buttons or groups.
Their GActions, keyboard shortcuts, contextual menus and compact File Actions
menu remain. Dynamic Share entries are included only when applicable.

OperationManager owns new_folder(), new_file() and create_default(). Exclusive
asynchronous GIO mkdir/create operations retry EXISTS with numbered default names;
the new-file stream closes before history is recorded. Both methods return GFile.
CREATE_FILE is appended to the enum (value 8), preserving saved history values.
Undo checks object identity and refuses nonempty/changed-kind new files. Empty
files go to Trash, protecting concurrent writes from permanent deletion. Folder
undo only deletes an empty directory. Redo uses exclusive creation and refuses
to overwrite a conflicting object. Renaming remains a separate history step.
Redo retargets dependent history guards only when both URI and the previous
identity match, including multi-step rename chains after recreating an object.

The window captures the Browser, destination, selection context and creation
epoch before awaiting the operation. Browser retains a pending edit with handlers
for selection-model item changes and directory load completion. It disconnects
these handlers on activation, cancellation, navigation or a load failure. DirectoryModel reconciles actual metadata
by GFile identity, waiting for enumeration settlement when necessary. Existing
monitor rows are reused. Enumeration publishes the existing 128-item GIO batches
in one ListStore splice, reducing repeated grouped-view rebuilds. Writable
capability notifications update action sensitivity during enumeration. Browser selects the matching object, scrolls through
the existing view-specific paths and starts the existing FilenameCell transaction.
Navigation, view changes, tab switches and cancellation invalidate editor requests.
The item itself remains created. No timer guesses when model data is available;
the existing bounded frame retry is used only for virtualized cell realization.
Chooser New Folder shares this path and handles inline renaming without changing
portal response handling. New File is not exposed in the chooser.

Native ColumnViewColumn sorters enable header interaction. ColumnViewSorter
primary column/order changes feed Browser.set_sort(); the existing custom sorter
continues to order every backing model. A guard synchronizes sort_by_column()
without recursion. Attribute comparison is shared by header and browser sorters,
with URI tie breaking. Selection is restored by URI, including Columns contexts
and Folders First changes. Child columns use the same Browser sorter; activation
reads their sorted selection model. Focus and pointer input set the actual column
destination, including an empty child column, and cancel obsolete edit requests.
Extension sorting retains asynchronous preparation, cancellation and failure
reporting; indicators restore the applied state after completion or failure.
Display persistence remains the existing folder settings mechanism. Stateful
Browser actions back native radio entries for every supported sort column,
including extension columns, and a checked direction entry. View Settings and
the existing window actions reflect the same shared sort key/direction. Descending
changes direction on the current key. No CSS was changed.

Verification uses the existing toolbar, inline rename, menu and portal suites,
plus tests/creation-sorting.vala: 1,500 items, all four views and grouping,
identity/focus/default-name selection, real X11 header clicks, reverse direction,
selection retention, collision numbering, rename/creation undo-redo and modified
file protection. Set MAJORIS_CREATION_EVIDENCE to capture integration screenshots.

File creation Undo uses the destination backend's Trash support. If that backend
cannot trash the file, Undo reports the backend error and retains the object.
The history fixture therefore uses a UUID-named directory under the user cache,
where GIO supports Trash, rather than WSL's internal /tmp mount.
