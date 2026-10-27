# Majoris Theme integration — 27 October 2026

Files now opts into the shared sidebar, Grid, Details and List components. Files
owns models, item factories, artwork, navigation and preferences; the installed
theme owns painting, typography, state transitions and standard/compact geometry.
No Majoris Theme source or packaging/application identifiers were changed.

Use Majoris Theme **0.1.0 with the 26–27 October 2026 data-view finalisation**
(the supplied `Majoris-Theme (20261027-005051)` snapshot) or later. The 0.1.0
version alone does not identify the required component revision. GTK4/libadwaita
requires the theme's supported user CSS installation or its StyleManager bridge;
`GTK_THEME` alone is insufficient. Files does not load a developer source path or
bundle the theme. The capture runner installs independent copies into an isolated
`XDG_CONFIG_HOME/gtk-4.0`, including relative imports, assets and supplied fonts.
The normal application remains functional with an unstyled Majoris class set.

## Implementation

- Sidebar icon/label margins are removed; a 16px icon and 8px Box spacing compose
  each native row. Labels expand, align to the start and ellipsise. Native headers
  use `majoris-sidebar-heading`; the first modifier is applied only when there is
  no preceding destination. Rebuilds use the same header function.
- New ordinary windows prefer 224px. The existing sidebar-width setter, bounds and
  chooser restoration remain intact. The preferred width survives reparenting
  into the narrow overlay. No stored settings are migrated or reset.
- Both plain and nested grouped grids use `majoris-data-grid`. A centred direct
  child `majoris-data-tile` owns the painted selection. Its artwork overlay uses
  `majoris-data-artwork`, keeping asynchronous thumbnails and cloud badges in a
  stable allocation. Selection checkboxes overlay the artwork instead of adding
  another line below filenames. Decoding, caching and cancellation are unchanged.
- The shared factory has two existing layout branches: Grid tiles and horizontal
  `majoris-data-cell` content. Details, Finder Columns and Gallery all use 16px
  icons without application cell margins; each consumer selects its native theme
  family. Metadata cells wrap their labels in the shared data-cell component.
- Stored 32/64/128 icon values continue to round-trip. Compact adds
  `majoris-density-compact`; Standard and Large remove it on every native view,
  including subsequently created panes and grouped grids. Density updates do not
  replace selection models or reload thumbnail caches.
- Large is a narrowly scoped Files presentation: a 192×224 tile, 160px artwork,
  128px icon and 176px filename width. There is no new theme token or CSS family.
  Optional metadata captions and enlarged accessibility text can naturally grow
  a tile vertically; text is never clipped to enforce the normal target.
- Grouped grids use the same tile pitch (144/104/208px) and measured viewport
  width instead of estimating filename widths from font metrics. Headings use
  16px insets/separation and 8px bottom spacing; the initial heading avoids
  duplicating the grid's outer inset. The structural outer ListView is unstyled.
- Details uses `majoris-data-column`, with optional body column separators off.
  Native column widths, visibility, resizing and the existing sorting paths are
  unchanged. No proportional column-width callback was added.
- The 650px breakpoint now applies to ordinary windows and choosers. Toolbars
  scroll horizontally when needed, allowing the window to actually reach the
  breakpoint. The sidebar toggle stays outside that scrolling area. The same
  sidebar widget moves between parents, closes after navigation, and restores
  its desktop width. The original 180–300px overlay bounds remain unchanged.
- Files CSS now contains only two bar-inset rules, using 4px vertical and 16px
  horizontal padding. No local data-view colours, typography, radii, states or
  theme-wide width rules were introduced.

## Measured before and after

The baseline is committed Files revision `349f4c0`, built independently under
`build/theme-baseline-source` against the same supplied theme. Measurements are
native GTK allocations at 100%, in logical pixels. Widget content dimensions
exclude CSS padding; painted tile dimensions include it. Row allocation includes
its CSS margin, so sidebar pitch is 36px while the painted row is 32px.

| Measurement | Before | After |
|---|---:|---:|
| New ordinary sidebar width | 180 | 224 |
| Sidebar row / pitch | 33 / 37 | 32 / 36 |
| Sidebar icon / icon-to-label gap | 16 / duplicate margins | 16 / 8 |
| Standard grid content / painted tile | 84×106 / native expanding cell | 112×144 / 128×160 |
| Compact painted tile | No shared contract | 96×128 |
| Standard / compact artwork | No separate allocation | 96×96 / 64×64 |
| Standard Details row | 56 | 40 |
| Compact Details row | Icon-driven | 32 |
| Details complete header | 32, raised buttons | 32, shared flat header |
| Details / standalone-list icon | 24 (32 for Large) | 16 |
| Finder Columns / Gallery rows | Icon-driven | 40 / 32 |
| Navigation / command bar | 44 | 40 |
| Status bar | 29 | 25 |

The light and dark normal-size geometry matches, including at 200% scale.
Enlarged-text standard tiles grow to 165px high; this is intentional native
content growth. The report preserves every variant's actual dimensions.

## Evidence and reproduction

[Native screenshots and full widget trees](../artifacts/theme-integration/)
include selected items, standard/compact/large grid, grouped grid, both Details
densities, both Columns/Gallery densities, closed/open narrow sidebar and restored
sidebar. Each PNG is an unedited native Gtk.WidgetPaintable capture; each adjacent
JSON records the realised widget tree, content/allocation sizes, positions, fonts,
Pango logical/ink extents and forwarded GTK baselines. A `-1` baseline means GTK
has not forwarded a baseline to that widget, not a measured text baseline of -1.

- [Light grid](../artifacts/theme-integration/light/grid-standard.png)
- [Dark Details](../artifacts/theme-integration/dark/details-standard.png)
- [Narrow overlay](../artifacts/theme-integration/light/narrow-sidebar-overlay.png)
- [Before light grid](../artifacts/theme-integration/before/light/grid-standard.png)
- [Before light Details](../artifacts/theme-integration/before/light/details-standard.png)
- [Before dark Details](../artifacts/theme-integration/before/dark/details-standard.png)
- [Geometry reports](../artifacts/theme-integration/geometry/allocations.json)

Run from the repository in Debian/WSL:

```sh
meson setup build --reconfigure
meson compile -C build
meson test -C build --print-errorlogs
python3 tools/capture-theme-integration.py /path/to/Majoris-Theme
python3 tests/verify-theme-geometry.py
python3 tests/verify-theme-pixels.py
```

The capture matrix covers light/dark, GDK_SCALE=1/2, and an enlarged native
`gtk-font-name=Plus Jakarta Sans 14` setting. Portrait, landscape and square PNGs
exercise the existing asynchronous thumbnail pipeline. The geometry verifier
checks complete tile/artwork/row/header allocations, sidebar icon gaps, heading
insets and Pango logical/ink heights against native label allocations. The
integration fixture checks sidebar width restoration, native overlay parenting
and navigation closing the overlay. `theme-integration-fallback` runs the same
navigation/view/density fixture under the default theme in Meson.

For the reproducible baseline, run `python3 tools/build-theme-baseline.py`, then:

```sh
MAJORIS_CAPTURE_QUICK=1 \
MAJORIS_CAPTURE_BINARY="$PWD/build/theme-baseline-source/build/theme-integration" \
MAJORIS_CAPTURE_OUTPUT="$PWD/artifacts/theme-integration/before" \
python3 tools/capture-theme-integration.py /path/to/Majoris-Theme
```

Baseline density calls are deliberately disabled because the committed application
has no public density setter. Only genuine standard grid, Details and sidebar
captures are retained as baseline evidence.

## Validation results and limits

All **14 Meson tests pass**, with no failures or skips: core, filesystem, cloud,
archive/replacement crash recovery, image decoders, session, sidebar, UI, portal,
redesign, theme-layout and the native fallback integration. All six native themed
capture/geometry runs pass. The pre-existing compiler warnings remain visible in
`build/theme-integration-compile.log`; warnings were not suppressed for this work.

Xvfb/GTK 4.18.6/libadwaita 1.7.6 in Debian WSL provides the native evidence. This
is not a GNOME/Mutter/Wayland compositor. Fractional scaling, real removable
hardware, live network/cloud services and physical pointer-driven drag-and-drop
still require testing on the target desktop. Existing automated functionality
coverage was retained; it does not constitute exhaustive manual testing of every
file-manager operation or hardware combination.

The renderer logs intermittent `pixman_region32_init_rect: Invalid rectangle`
diagnostics during captures, without failing the fixture. These are preserved in
native logs. Native flat Details headers still show a subtle toolkit edge in the
unmodified screenshots; Files adds no shadow rule. The sidebar stripe is visible
in both variants: the theme specifies 2px width and 8px vertical insets, while the
WidgetPaintable exact-colour core measures 1×15px due to partial raster edge
coverage. The pixel report records that distinction rather than claiming every
edge pixel is fully opaque. No theme override was added for these observations.
