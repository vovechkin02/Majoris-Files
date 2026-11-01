# Grid caption correction — completion report

## 1. Root cause

Virtual collections assigned `caption_key = "Location"`, forced caption
visibility regardless of the user's preference, and allowed a saved Location
value to reach the Grid item factory. This affected plain and grouped grids.

## 2. Browser caption logic

One `valid_grid_caption()` rule now validates caption keys against registered
columns while excluding None, Name and Location. `update_grid_caption()` is used
for factory setup, binding, display changes and unbinding. Invalid/disabled
captions have both their text cleared and their widget hidden.

## 3. View Settings

Location is absent from Grid Metadata Caption. None, Size, Type and Modified
remain, along with other existing non-Location metadata choices. List Columns
still includes Location. No column provider or `column_text()` implementation
was removed or changed.

## 4. Saved preferences

Location and unknown saved values normalize to None before rendering and are
persisted to their existing `caption:<URI>` key. The migration does not rewrite
the display blob, grouping, sorting, icon size, selection-checkbox preference or
unrelated state. Tests compare the original saved display blob and grouping,
then reopen with fresh stores/windows to verify Size persistence and legacy
fallback persistence. Saving a caption also validates its value.

## 5. Recycled tiles

Every bind recomputes caption text and visibility. Unbinding immediately clears
and hides the label. Hidden labels reserve no caption layout space; filenames,
icon requests and thumbnail handling retain their existing implementation.
The fixture scrolls a 1,200-file directory and retains old tile widgets to assert
that they cannot retain visible/stale captions after None is selected.

## 6. Collections and grouping

Recent, Favorites and Tags no longer force captions. Ordinary directories,
search results, remote-backed item models and grouped grids use the same rule.
The None/Size/Type/Modified matrix is exercised in ordinary, Recent, Favorites,
Tags and saved-search contexts, with grouping enabled and disabled. Group
headings remain visible. Grid/List/Columns switching and invalid saved values
are covered as well.

## 7. Details, paths and other views

The Details Location column remains visible for virtual collections and retains
its rendering, saved width, resizing and Location sorting. The tests also
exercise selection and the Source Folder action. Existing file-path tooltips are
asserted against each bound FileItem. File URIs, Properties, Copy Path, the
location bar and file-opening behaviour are unchanged. No metadata was globally
removed from FileItem.

## 8. Modified files

* `src/views/browser.vala`: caption policy, preference migration and factory resets.
* `tests/grid-captions.vala`: native UI, persistence, collections and recycling regressions.
* `meson.build`: registers the new test executable/suite.
* `artifacts/grid-captions/`: build/test logs, captures and this report.

Neither `data/theme/files.css` nor Majoris Theme was modified. No dependencies,
custom styling, icons, filesystem operations or metadata architecture changes
were introduced.

## 9. Build and verification

The required Meson setup, complete build and regression commands were executed
in Debian WSL: **24 suites passed, 0 failed, 0 skipped**. The production and
portal binaries linked successfully. The full suite uses `GTK_A11Y=none ADW_DISABLE_PORTAL=1` for the
headless test session, with all existing tests retained.

* `setup.log` and `build.log`: Meson configuration and production/portal build.
* `tests.log`: full regression results.
* `fixture-tests.log`: native caption fixture and visual capture run.
* `geometry-check.json`: 14 captures, 44 grid tiles, no visible caption labels
  when None is selected, no path captions and no overflowing tile text.
* `contact-sheet.png`: all seven requested views in both palettes.

The visible metadata labels in the capture set occur only in the explicitly
enabled Size view. Details screenshots intentionally retain directory paths.

Reproduce the themed native capture:

```sh
MAJORIS_CAPTION_THEME=/path/to/Majoris-Theme/theme/Majoris \
MAJORIS_CAPTION_EVIDENCE="$PWD/artifacts/grid-captions" \
dbus-run-session -- xvfb-run -a env GTK_A11Y=none ADW_DISABLE_PORTAL=1 \
GDK_BACKEND=x11 GSK_RENDERER=cairo GSETTINGS_BACKEND=memory \
build/grid-caption-tests
```

## 10. Limits

Visual verification uses the existing Majoris Theme under Xvfb, not a full GNOME
session. The remote rendering case uses injected SFTP-backed FileItems rather
than a live remote server. The fixture clears grouping before replacing a
collection model to avoid GTK 4.18 header-teardown warnings; grouped rendering
and grouping/view switches are asserted independently. No warnings or existing
tests are suppressed. No known caption-path issue remains in the corrected
rendering paths.
