# Toolbar and document composition

Files now appends Back, Forward, Parent Folder and Other Locations directly to
`Majoris.Ui.Toolbar`, followed by the expanding address/search composite and
search controls. The explicit vertical separator and both navigation groups are
removed. Parent Folder retains a direct reference for breakpoint visibility.
Commands already used direct children: the flexible alignment spacer, segmented
view selector and chooser dropdown are retained without application margins.
No Theme sources or application CSS changed.

Only HeaderBar remains an Adw.ToolbarView top bar. A vertical Gtk.Box with zero
spacing contains TabBar, the recovery banner and TabView, in that order. The
native tab model, actions, overview and recovery callbacks remain attached.

## Native measurements

Measurements use real GTK border-box bounds, not declared spacing alone.

| Boundary or component | Logical pixels |
|---|---:|
| Adjacent navigation controls, including Other Locations → address | 4 |
| Adjacent commands controls | 4 |
| Segmented selector internal gap | 2 |
| Toolbar horizontal outer insets | 8 |
| Document TabBar height | 40 |
| Normal toolbar height | 40 |
| Normal toolbar control height | 32 |
| Tabs → navigation, banner hidden | 0 |
| Tabs → banner → navigation, banner revealed | 0 extra |
| Navigation → commands | 0 |
| Commands → following content surface | 0 |
| Navigation scroll/bin excess height | 0 |

The structural Theme divider and tab selection indicator remain visible. The
address/search grid retains its own 8px field separation and flexible 3:1 tracks.
The enlarged-search stress case allocates 51px to navigation and 40px to
commands. Toolbars grow naturally; no fixed toolbar height is imposed. Its
trailing controls remain reachable through the existing horizontal scroller.
The existing navigation sizing callback changes its request only when the
measured natural height changes. Native assertions confirm that the bin and
scroll window allocate exactly the toolbar height, so no sizing correction was
needed for this wrapper.

## Runtime and reproduction

Tested with GTK 4.18.6 and libadwaita 1.7.6 in Debian/WSL using Xvfb and Cairo.
The system-installed Toolbar library predates the sibling Theme source (its
previous tests expected `spacing == 0`). Validation instead uses the current
public Theme implementation, compiled into a temporary library without editing
Theme source or replacing the system installation:

```sh
mkdir -p /tmp/majoris-current-ui
cd /tmp/majoris-current-ui
valac --pkg gtk4 --library majoris-ui-gtk4 -H majoris-ui-gtk4.h \
  -X -fPIC -X -shared -X -Wl,-soname,libmajoris-ui-gtk4.so.0 \
  -o libmajoris-ui-gtk4.so.0 /path/to/Majoris-Theme/ui/toolbar.vala
cd /path/to/Majoris-Files
meson compile -C build toolbar-tests
LD_LIBRARY_PATH=/tmp/majoris-current-ui \
MAJORIS_TOOLBAR_OUTPUT=artifacts/toolbar-composition \
python3 tools/capture-toolbars.py /path/to/Majoris-Theme
python3 tests/verify-theme-geometry.py --toolbars artifacts/toolbar-composition
meson test -C build theme-layout toolbars --print-errorlogs
```

The capture fixture covers 480, 650, 800 and 1100px in Files, open chooser and
save chooser modes. It checks Parent Folder and Sort breakpoint visibility,
compact search, overflow, wrapper allocations, control margins and native
horizontal-scroll bounds. Existing navigation, keyboard focus, search,
segmented selector, file actions and preview checks remain. Tab checks cover
switching, duplicate, pin/unpin, left/right reordering, close, close others,
close right, overview and transfer into a second window.

Evidence is in `artifacts/toolbar-composition`: PNG captures and matching native
allocation JSON, with a machine-readable `allocations.json` summary. Appearance
variants include light/dark, scale 2 and enlarged text. Screenshots are native
GTK captures without retouching. The X11 pointer fixture now converts logical
coordinates to physical pixels for scale 2.

## Validation results

- Final `majoris-files` and `toolbar-tests` builds pass.
- Registered `theme-layout` and `toolbars` tests pass (2/2).
- Existing Files geometry/glyph checks pass for all six historical variants.
- The new allocation verifier passes all six appearance variants and all 78
  responsive/recovery allocation trees, including outer insets, composite gaps
  and commands/content adjacency.
