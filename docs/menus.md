# Native text-only menus

Files owns content and actions; Majoris-Theme owns visual presentation. There are
no new menu rules in `data/theme/files.css`.

The single-file menu uses native sections: Open / Open With / supported Preview /
supported Extract; Cut / Copy / Rename / Move to Trash; Favorites / Tags; More
Actions; Properties. Directories substitute Open in New Tab for Open With and
Preview, and offer Share only when Properties' sharing capability check succeeds.
Multiple selections omit opening commands and use Batch Rename. Favorites applies
one consistent state to the whole selection. Trash exposes Restore, Delete
Permanently and Properties. Empty space exposes creation/paste only at writable
destinations, Sort By, Group By, View, Refresh and supported Terminal access.

More Actions contains Duplicate, Copy To, Move To, New Folder with Selection and
Create Link where supported; Compress, Checksums, Split/Join; image Quick Actions;
nonempty User Actions; and cloud commands from cached provider capabilities.
Sections and provider submenus are omitted when empty. Properties remains last.

Permissions (including advanced/recursive operations), General / Open With /
Change, and Sharing remain in Properties. A compact Icon menu beside the identity
area sets and resets the persisted GIO custom-icon metadata. Existing action
registrations and operation/recovery implementations remain available.

Compress uses the extended SevenZipDialog: ZIP, 7z, TAR and compressed TAR formats,
a destination selector, ZIP content encryption, 7z content/header encryption,
7z volume size and compression level. Inapplicable controls are disabled. Existing
ArchiveService and SevenZip backends perform the work. Extract chooses a parent
and a new destination folder, preserves the backend's no-overwrite policy and
validation, and asks for a password upon an authentication-related failure. Retry
uses the existing backend cleanup and security checks.

Native MenuModel adaptation recursively strips decorative icon attributes while
retaining other attributes, targets, action namespaces and nested links. Locations
and sidebar menus now use native PopoverMenu models and scoped actions. Native
state indicators and accelerators remain available. Files configures directly
owned popovers with has_arrow=false and menu buttons with direction=NONE.
Internally generated submenu arrows require the regenerated Majoris-Theme rules
in design/templates/gtk4.css.in and gtk3.css.in. GTK4's modelbutton/arrow hierarchy
was checked against realized GTK 4.18 widgets. No widget children are destroyed.

Pointer targeting uses the bound file identity, including Columns and grouped
Grid contexts, preserves a clicked multi-selection, and clears stale selection on
empty-space invocation. Keyboard invocation retains selection. Extension menu
refresh checks generation, location and selection identity, never reopens the
popover, and replaces the model contents. Stale extension failures no longer clear
a newer request's cached actions.

## Verification

Build and run the Meson suite. tests/menus.vala checks menu content, section and
submenu nonemptiness, Favorites convergence, recursive provider adaptation,
context targeting, Trash and virtual collections. Existing operation, archive,
permissions, chooser, sharing, extension, Properties and inline-rename coverage
remains in the suite. The updated Properties test checks the new icon menu.

On Linux with GTK4, Xvfb, Openbox, xdotool, xwd and ImageMagick installed:

```
meson setup build --reconfigure
meson compile -C build
GTK_A11Y=none meson test -C build --num-processes 1 --print-errorlogs
python3 tools/capture-menus.py ../Majoris-Theme
```

The capture runner loads generated Theme CSS from its source tree without
installing it and records light/dark single-file, folder, image, archive,
multi-selection, empty-space, More Actions, sidebar, application and overflow
menus at normal scale, 2x and 125% text. Native submenu activation and zero-width
arrow nodes are asserted with Theme loaded. Majoris-Theme's own menu fixtures
exercise check/radio state, disabled actions, shortcuts, keyboard activation,
dismissal, and enlarged text in GTK3/4.

Real cloud authentication, physical device hotplug/eject, remote read-only server
capabilities and screen-reader announcements still require their corresponding
platform/services; fixture tests cannot substitute for that integration coverage.
