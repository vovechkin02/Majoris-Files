# Native Files design and theme integration

Files remains the existing Vala/GTK4/libadwaita application, with centred title,
visible tabs and sidebar, Recent/Favorites, search, separate command toolbar,
native views and status bar. Filesystem operations, clipboard, drag-and-drop,
session restoration, chooser and portal integrations retain their existing code.

## Theme ownership

GNOME installs, manages and activates Majoris Theme in light and dark appearances.
Files neither bundles theme stylesheets/assets nor changes GNOME settings. The
FilesTheme.ensure() entry point registers only data/theme/files.css at application
priority. It does not observe StyleManager or switch theme resources.

The resource manifest includes only Files-owned layout CSS. Navigation and command
rows each use 6px vertical and 12px horizontal CSS padding. Navigation has zero
widget margins and retains 4px child spacing. Section and status padding are the
only other application rules; generic controls and appearance belong to GNOME.

The location stack uses majoris-location-bar, breadcrumb buttons use
majoris-location-crumb, and the current folder uses majoris-location-current.
Separators use majoris-location-separator and the path entry uses
majoris-location-entry. majoris-location-editing follows the stack's visible entry
and clears on submission, Escape, navigation and cancellation. Breadcrumb clicks,
blank-space editing, Ctrl+L/Alt+D and existing path completion remain native.

Removed resources: gtk.css, gtk-dark.css, colors.css, colors-dark.css and
assets/spinner.svg, together with copied-theme provenance and licence documents.
The independent project LICENSE remains.

## Validation

The redesign suite checks toolbar margins/spacing, Files-only resource inventory,
layout padding, shared location classes, edit-state transitions, breadcrumb
activation, relative paths, Escape and history. Existing collection, clipboard,
chooser, session and portal tests remain registered.

Build and test with:

```sh
meson setup build --prefix=/usr # add --reconfigure for an existing build
meson compile -C build
meson test -C build --print-errorlogs
```

Verified on 26 October 2026 in Debian WSL with GTK 4.18.6, libadwaita 1.7.6,
Vala 0.56.18 and Meson 1.7.0. Reconfigured with prefix /usr, compiled
successfully, and ran meson test -C build --print-errorlogs: **12 passed,
0 failed, 0 skipped** (core, cloud, replacement-crash, archive-crash,
image-decoders, firewall, filesystem, ui, session, portal, redesign,
theme-layout). Native UI tests used Xvfb. Compiler warnings remain, including
existing generated-C warnings and GTK StyleContext deprecation. The full local
log is build/meson-logs/testlog.txt. git diff --check passes.

The screenshots in redesign-screenshots predate removal of the bundled theme;
they are historical and do not verify the current GNOME theme integration.
Actual installed GNOME Majoris Light/Dark visual verification remains required
when a desktop session is available. Xvfb tests alone do not establish that.
