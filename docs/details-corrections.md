# Details section, metadata and focus corrections — 27 October 2026

Ungrouped Details and Gallery now detach their native section-header factory.
Details starts its first data row immediately below the 32px column-header region.
The existing shared group factory is reused when grouping is enabled. Metadata
remains theme-owned 12px/400 text: native measurements found no ink clipping.
Selection and keyboard focus remain GTK states, without Files-specific painting.

## Confirmed causes and changes

The previous application always assigned `group_headers()` to both ColumnView and
Gallery's ListView. With grouping set to None, binding hid the label but retained
its 16px top and 8px bottom margins in a section-header widget. The backing
SortListModel still exposes a section encompassing the ungrouped list, so GTK
allocated that invisible header. Native instrumentation reproduced a **24px gap**.

`Browser.update_group_headers()` now assigns the shared factory only when
`group_key != "None"`, and assigns null otherwise. Both `set_group()` and
`load_display()` call it. The factory no longer creates permanently hidden empty
labels. No CSS offsets, global header rules, row padding changes or drawing
workarounds were added. The internal ListView in ColumnView remains unstyled by
the standalone list family.

Details and Gallery were tested through two complete cycles of every supported
grouping: Type, Modified Date, Size, Tags, Recent Date and None. Name is not a
supported grouping in this application; Name sorting remains supported. Real
headings remain visible, None removes their allocation, and restoring a saved
folder grouping reinstalls or removes the same factory. Grouped Grid continues
using its existing structural outer list and native nested grids.

The selection investigation uncovered an existing Columns pane-width defect:
its ListView requested 220px, but its enclosing ScrolledWindow discarded that
minimum and could allocate just 24px. Pointer events then missed the intended
rows. The pane scroller now has `min_content_width = 220`, matching the existing
intended pane width. No Columns navigation or selection model was replaced.

The sidebar, toolbar geometry, filesystem backend, operation services, application
identifiers, packaging, density preferences and theme stylesheet are unchanged.

## Native measurements

The baseline was built independently from committed Files revision
`dee2dd12de6e24e03abe13f14a98db8838b1367f`, with the same current instrumentation
and fixture directory contents. Values are logical GTK pixels, measured from
widget bounds relative to the actual window.

| Measurement | Before | After |
|---|---:|---:|
| Column-header top | 174 | 174 |
| Complete column-header height | 32 | 32 |
| Header bottom | 206 | 206 |
| First ungrouped data-row top | 230 | 206 |
| Empty section-header gap | 24 | **0** |
| Standard data-row height | 40 | 40 |
| Compact data-row height | 32 | 32 |
| Ungrouped Gallery first-row offset | Empty section allocation | 0 |
| Filename icon / gap | 16 / 8 | 16 / 8 |

The same zero-gap result holds in light/dark at 100%, 200% and enlarged native
font settings, including after repeated grouping and saved-setting restoration.

### Metadata investigation

The Size, Type, Modified and extension-column factories already use
`majoris-data-cell` containing a `majoris-data-metadata` label. There are no
metadata-specific font overrides, vertical margins or height requests. Native
measurements therefore justified retaining the existing production construction.

At normal text size, effective metadata typography is 12px/400. Pango resolves
**Plus Jakarta Sans 9pt**, which corresponds to 12px at 96dpi. The native label
allocation is 23px high inside the 39px standard / 31px compact cell allocations;
the row's separator brings the complete row to 40px / 32px. The measured Pango
baseline is approximately 12.456px within the layout and approximately 15.456px
within the label after its 3px layout offset. Selected and unselected cells retain
that baseline. The report records exact values for every tested scale/font setting. The enlarged
`gtk-font-name=Plus Jakarta Sans 14` preference condition was exercised; the theme's
explicit 12px metadata role remains 12px at 96dpi in that condition. This is not a
claim that the preference scales CSS pixel typography.

`18 bytes` and `gjpqy` use a 13px ink height at normal size; their ink spans y=6–19
inside the 23px label after accounting for layout offset. Uppercase, long metadata
and timestamps likewise fit the actual label and parent cell. The tests measure
ink extents plus Gtk.Label layout offsets, not just logical line height. GTK's
forwarded allocation baseline can be -1; the independently recorded Pango baseline
and rendered baseline are used for text alignment checks.

All requested strings are exercised through a native test ColumnProvider:
`18 bytes`, `24 bytes`, `Folder`, `Plain text document`, `Modified`, `Favorites`,
`Files`, `Format`, `ABCDEFGHIJKLMNOPQRSTUVWXYZ`, `gjpqy`, full and short
timestamps, and a long metadata value. The normal Size/Type/Modified columns are
also captured. Ellipsisation of intentionally long horizontal values is retained.
No confirmed vertical clipping remains and no font-size or row-height workaround
was introduced. Small-font rasterisation differences should not be treated as
allocation clipping without contradictory ink-bound evidence.

The old screenshot runner isolated XDG_DATA_HOME without preserving the user's
installed fonts. Since the supplied Theme tree does not bundle the font files,
this hid Plus Jakarta Sans and could produce Cantarell fallback. The runner now
copies already installed Plus Jakarta Sans font files into its isolated data
installation when the theme does not bundle them, installs the supplied fontconfig
aliases and records `font-resolution.txt`. No fonts were downloaded or added to
the application/theme source. Native Pango resolution, rather than just the CSS
family list, is asserted by the new verifier.

### Selection and focus investigation

Grid, Details, Gallery and root Columns panes retain their native selection
models. The tests send real X11 pointer clicks and arrow keys with xdotool; they
do not set GTK state flags, invent selected classes or focus a row solely to paint
an outline. They verify:

- Pointer selection retains selected state without `FOCUS_VISIBLE`.
- Keyboard navigation produces genuine native focus with `FOCUS_VISIBLE`.
- Clicking the search entry removes file-view focus while preserving selection.
- Switching through all four views preserves the selected file identity.
- Ascending/descending sorting preserves the selected file identity.

The installed Majoris classes supply the shared selected backgrounds and keyboard
outlines. Initial inspection found an older generated Theme rule painting Details
on `:focus-within`, even for pointer focus. The final supplied generated Theme
contains the corrected shared `:focus-visible` rule. Final native captures use
that version, and `theme-focus-audit.json` records the actual installed CSS hashes
and any unconditional Details focus-within rules. Files adds no competing visual
rule. **Deploy the corrected Theme build as well as Files**; an older Theme can
still paint pointer focus as an outline despite correct application GTK states.
No Majoris-Theme files were modified by this task. No additional Theme change was
required by the final native measurements.

## Evidence

All PNGs are unedited native GTK window captures. Each adjacent JSON contains
widget hierarchy, absolute bounds, native state flags, overflow settings, Pango
logical/ink extents, layout offsets, effective/resolved fonts, font resolution and
baselines. Full-cell/label geometry is preserved rather than cropped.

- [Light ungrouped Details](../artifacts/details-corrections/light/details-ungrouped.png)
- [Dark ungrouped Details](../artifacts/details-corrections/dark/details-ungrouped.png)
- [Before light Details](../artifacts/details-corrections/before/light/details-ungrouped.png)
- [Before dark Details](../artifacts/details-corrections/before/dark/details-ungrouped.png)
- [Grouped Details](../artifacts/details-corrections/light/details-grouped.png)
- [Metadata probe](../artifacts/details-corrections/light/details-metadata.png)
- [Mouse-selected Details](../artifacts/details-corrections/light/details-mouse-selected.png)
- [Keyboard-focused Details](../artifacts/details-corrections/light/details-keyboard-focused.png)
- [Mouse-selected Grid](../artifacts/details-corrections/light/grid-mouse-selected.png)
- [Keyboard-focused Grid](../artifacts/details-corrections/light/grid-keyboard-focused.png)
- [Header positions](../artifacts/details-corrections/geometry/header-gap.json)
- [Metadata metrics](../artifacts/details-corrections/geometry/metadata-metrics.json)
- [Selection/focus states](../artifacts/details-corrections/geometry/focus-selection.json)
- [Installed theme audit](../artifacts/details-corrections/geometry/theme-focus-audit.json)

Corresponding screenshots cover light/dark, both densities, 200% scale, enlarged
fonts, Gallery and Columns, grouped/ungrouped Grid, and focused/unfocused selection.
The unchanged sidebar is present in the full-window captures.

## Build and reproduction

Run in Debian/WSL with GTK4/libadwaita, Meson, Xvfb and xdotool installed:

```sh
meson setup build --reconfigure
meson compile -C build
meson test -C build --print-errorlogs
MAJORIS_EXPECT_THEME=1 \
MAJORIS_CAPTURE_BINARY="$PWD/build/details-corrections" \
MAJORIS_CAPTURE_OUTPUT="$PWD/artifacts/details-corrections" \
python3 tools/capture-theme-integration.py /path/to/Majoris-Theme
python3 tests/verify-details-corrections.py
```

The runner installs independent copies into the normal isolated GTK4 user-override
location. Files never loads CSS from a developer source tree. It still functions
under another GTK theme; the new `details-corrections` Meson target also tests the
native lifecycle and input behavior under the isolated default theme.

Rebuild the pre-fix baseline with `python3 tools/build-details-baseline.py`, then:

```sh
MAJORIS_CAPTURE_QUICK=1 MAJORIS_DETAILS_BASELINE=1 \
MAJORIS_CAPTURE_BINARY="$PWD/build/details-before-source/build/details-corrections-before" \
MAJORIS_CAPTURE_OUTPUT="$PWD/artifacts/details-corrections/before" \
python3 tools/capture-theme-integration.py /path/to/Majoris-Theme
```

The existing visual-check fixture now accepts optional
`MAJORIS_VISUAL_THEME_CONFIG` and `MAJORIS_VISUAL_THEME_DATA` paths for the same
installed override/font mechanism; its default remains an isolated default-theme
run. Its obsolete assertion that a 500px ordinary window remains wide was updated
to assert the already implemented adaptive behavior. Existing visual and theme
integration coverage was retained rather than removed.

## Results and limits

All **15 Meson tests pass**, with no failures or skips. Native correction geometry,
metadata and input checks pass for all six theme/scale/font combinations. The
existing visual-check fixture was also run, including light/dark theme overrides.
The existing theme-integration fixture passes in Meson under the default theme.
Pre-existing compiler warnings remain visible in `build/details-compile.log`.

Validation used GTK 4.18.6/libadwaita 1.7.6 with a real X11 display supplied by
Xvfb in Debian WSL. This establishes native widget allocation and input behavior,
not GNOME/Mutter/Wayland acceptance. Real network/removable hardware, physical
pointer drag-and-drop and fractional compositor scaling remain target-desktop
checks. Existing UI, filesystem, clipboard/drop-policy, sorting, grouping, cloud,
portal/chooser, preview, tab and thumbnail tests were retained; they are not a
claim of exhaustive manual testing of every hardware/service combination.

Intermittent `pixman_region32_init_rect: Invalid rectangle` renderer diagnostics
and environment portal/GVfs shutdown messages remain in native logs. They were
not suppressed and did not fail the completed fixtures. No screenshot was edited
to conceal clipping, the gap or focus states.
