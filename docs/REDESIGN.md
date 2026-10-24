# Native Files redesign — implementation and verification

Implemented in the existing Vala/GTK4/libadwaita application. The HTML reference is not embedded, and no replacement application was created.

## Implementation decisions

- Keep a single native Files window title and the existing Adw tab system. Tabs stay visible, use `majoris-document-tabs`, have compact widths, and display meaningful Recent/Favorites/Home labels.
- Navigation has Back, Forward, Up, Refresh, a unified breadcrumb/entry container, and permanent search. Breadcrumbs navigate; blank space edits the path. Ctrl+L, Alt+D, Enter, Escape and F5 are handled. Relative paths resolve against the current filesystem folder. Existing location completion remains available.
- A separate command row uses official Majoris controls and existing native actions: New Folder, Cut, Copy, Paste, Rename, Share, Move to Trash, Sort, Grid/List/Columns/Gallery, view settings and Preview. Share exposes native folder sharing and supported Nearby providers. Permanent deletion retains its separate action and confirmation flow.
- The main Files sidebar stays visible. Recent and Favorites precede Folders and Locations. Bookmarks, devices, network, cloud accounts, tags, saved searches and Trash remain integrated. Unchanged inventory no longer rebuilds every sidebar row when unrelated metadata changes.
- New windows default to Recent. Explicit launch locations and session restoration retain their existing paths. Legacy Home Overview session locations migrate to Recent.
- Recent uses actual Gtk.RecentManager records, their recent dates, and the existing grouped models. Favorites uses MetadataStore. Both keep source-folder captions/columns, search, selection, keyboard navigation and an Open Source Folder context action. Favorites changes and recent-manager changes refresh collections.
- Destination commands are guarded for virtual locations, including action activation and clipboard completion. Source operations still target the real selected files. Existing drop rejection for virtual destinations remains in place.
- Grid, List, Gallery and filesystem Columns remain native. A virtual collection has no directory hierarchy, so selecting Columns there presents its files through the native List model. Status counts, selection counts and selected sizes stay at the bottom.
- Official GTK4 light/dark styles are bundled unchanged from the supplied theme ZIP, with its MIT license and spinner asset. StyleManager selects the scheme. Application CSS adds only semantic layout rules, including the 9px location container and 7px breadcrumb corners. Official generic controls and window-control geometry remain owned by the theme.
- ChooserWindow keeps its compact/adaptive sidebar behavior, restricted view choices, filters, and existing acceptance/portal flow. Desktop command controls are excluded from chooser mode.
- Avoid removing/reinserting already-correct ColumnView columns during display restoration. This resolved invalid-widget diagnostics in the themed native visual fixture.

## Validation

Built and tested in WSL Debian using GTK 4.18.6, libadwaita 1.7.6, Vala 0.56.18 and Meson 1.7.0. Existing configured prefix: `/usr`.

Commands executed:

```sh
meson setup build --prefix=/usr
meson compile -C build
meson test -C build --print-errorlogs
# Final complete run after the last source changes:
meson compile -C build -j 8
meson test -C build --no-rebuild --print-errorlogs
```

Final result: **11 suites passed, 0 failed, 0 skipped**: core, cloud, replacement-crash, archive-crash, image-decoders, firewall, filesystem, ui, session, portal and redesign.

The new redesign suite covers default Recent and sidebar inventory, native toolbar/tab presence, parsing both official theme variants, Favorites persistence and live removal, collection search, destination-command rejection, source-folder navigation, real clipboard copy/paste, Recent date groups, the Columns collection fallback, Ctrl+L/Alt+D, relative-path submission, Escape, history, and legacy Home migration. Existing suites cover chooser behavior, filesystem actions, drag/drop policies, tab routing, detailed session restoration and portal compatibility.

`git diff --check` passes. Existing compiler warnings in generated C remain; no compiler errors.

## Native visual verification

The existing `visual-check` executable ran in isolated HOME/XDG directories under Xvfb/X11 with Cairo. Both light and dark runs completed with `G_DEBUG=fatal-criticals`; there were no application GTK critical failures after the column-restoration fix. Desktop service messages about unavailable RealtimeKit/PipeWire/GVfs mounts or bus shutdown can still appear in this minimal environment.

Inspected native screenshots for toolbar geometry, tab labels/widths, sidebar sections, indigo focus/selection, date grouping, source captions, content/status separation, and chooser preservation. No synthetic file cards or HTML rendering are used. The fixture uses small temporary folders rather than the mockup's demonstration assets.

| Appearance | Grid | List | Recent | Chooser |
|---|---|---|---|---|
| Light | [Grid](redesign-screenshots/light-grid.png) | [List](redesign-screenshots/light-list.png) | [Recent](redesign-screenshots/light-recent.png) | [Chooser](redesign-screenshots/light-chooser.png) |
| Dark | [Grid](redesign-screenshots/dark-grid.png) | [List](redesign-screenshots/dark-list.png) | [Recent](redesign-screenshots/dark-recent.png) | [Chooser](redesign-screenshots/dark-chooser.png) |

Additional dialog and narrow-window captures and raw logs are in the ignored `build/screenshots/light/` and `build/screenshots/dark/` folders. Final test output is `build/redesign-final-tests.log`.

## Remaining limits

- Native screenshots were verified on Xvfb/X11, not a physical Wayland session or every display scale/font configuration.
- Nearby file sharing requires a compatible installed provider, as in the existing application. The toolbar does not invent a sharing transport.
- Live cloud accounts, network servers, physical devices and installed portal replacement were not exercised. Their existing integrations remain in place. No system file manager was replaced or installed, and filesystem tests use isolated temporary data.
- Virtual collections use List when Columns is selected because they have no filesystem hierarchy. Normal filesystem Columns behavior remains available.

## Changed files

| File | Change |
|---|---|
| `meson.build` | Bundle resources/theme source; register redesign regression executable/suite. |
| `src/actions/registry.vala` | Allow a Share menu restricted to existing Nearby sharing providers. |
| `src/sidebar/places.vala` | Recent/Favorites ordering, sections, remove Home Overview, avoid redundant inventory notifications. |
| `src/views/browser.vala` | Native navigation and command rows, persistent search, path editing, sidebar, collections, view controls, status geometry, safe column restoration. |
| `src/views/file-groups.vala` | Date grouping based on actual recent-manager dates. |
| `src/views/home.vala` | Replace obsolete overview composition with the native activity-source helper. |
| `src/window/window.vala` | Default Recent, tab styling/titles, command availability, source-folder action, native Share menu, paste guards. |
| `src/window/extra-actions.vala` | Guard destination-based extra actions in virtual locations. |
| `src/window/theme.vala` | Resource-backed official light/dark theme bridge. |
| `data/files.gresource.xml` | Theme/layout resource manifest. |
| `data/theme/gtk.css` | Official supplied light GTK4 theme, unchanged. |
| `data/theme/gtk-dark.css` | Official supplied dark GTK4 theme, unchanged. |
| `data/theme/colors.css` | Official light semantic values, unchanged. |
| `data/theme/colors-dark.css` | Official dark semantic values, unchanged. |
| `data/theme/assets/spinner.svg` | Official theme asset, unchanged. |
| `data/theme/files.css` | Semantic application layout and breadcrumb geometry. |
| `data/theme/LICENSE` | Supplied theme MIT license. |
| `data/theme/README.md` | Theme provenance and loading description. |
| `tests/redesign.vala` | Isolated native redesign regression tests. |
| `tests/session.py` | Assert new default Recent while retaining restoration checks. |
| `tests/visual.vala` | Optional dark capture, Recent capture name and permanent-main-sidebar assertion. |
| `docs/REDESIGN.md` | This implementation/verification report. |
| `docs/redesign-screenshots/light-grid.png` | Native light grid capture. |
| `docs/redesign-screenshots/light-list.png` | Native light list capture. |
| `docs/redesign-screenshots/light-recent.png` | Native light Recent capture. |
| `docs/redesign-screenshots/light-chooser.png` | Native light chooser capture. |
| `docs/redesign-screenshots/dark-grid.png` | Native dark grid capture. |
| `docs/redesign-screenshots/dark-list.png` | Native dark list capture. |
| `docs/redesign-screenshots/dark-recent.png` | Native dark Recent capture. |
| `docs/redesign-screenshots/dark-chooser.png` | Native dark chooser capture. |
