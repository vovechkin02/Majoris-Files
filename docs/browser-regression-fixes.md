# Browser UI and scrolling regression fixes

## Causes and implementation

- The file-operation context gesture was installed on the entire Browser. Bubbled right-clicks from its toolbars and other controls therefore opened the directory menu. Both pointer and Menu/Shift+F10 controllers now belong to `Browser.file_surface`, the file-view stack. Item selection gestures and sidebar `place_menu()` are retained. Pointer sequences handled by the file menu are claimed; keyboard popup coordinates use the content surface.
- The breadcrumb had no location-specific context menu. Its existing stack now owns a `Gtk.PopoverMenu` and local actions for Copy Address (GFile URI), Copy Address as Text (GFile parse name), and Edit Address. Secondary clicks are claimed only in breadcrumb mode; the editable entry keeps GTK's native clipboard/selection menu. Breadcrumb blank-space editing accepts the primary button only. No unrelated history-clearing action was added.
- The duplicate sidebar toggle was explicitly reconstructed in the history toolbar group. That construction is removed. F9 toggles the existing pane/overlay and is listed in Keyboard Shortcuts, including in chooser Browser instances.
- The recent collection already used `recent:///`; its obsolete Home label and home icon were replaced by Recent and `document-open-recent-symbolic`. No Home or Bookmarks destination was added.
- Location and Search previously expanded independently. A four-track homogeneous Gtk.Grid inside the canonical Majoris Toolbar gives three tracks to Location and one to Search. A separate navigation breakpoint switches Search into its existing popover before its minimum width can clip the toolbar, using a text-scaled threshold. The 650px sidebar breakpoint and its state remain independent. Toolbar/theme geometry stays owned by Majoris UI; no application theme overrides were added.
- Grid put a non-scrollable Gtk.Stack directly inside Gtk.ScrolledWindow. GTK could introduce Gtk.Viewport, preventing the virtualized GridView/ListView from sharing the viewport adjustment and allocation expected by native scrolling. The stack now contains two scrollers, each directly parenting its native GtkScrollable view. `current_scroll()` returns the active Grid scroller; session-change signals observe both. This preserves the existing session restoration path and selection models without materializing all files.
- Grouped Grid retains the virtualized outer ListView and bounded GridSlice rows (at most sixteen cells). Nested grids request natural vertical scrolling policy. Keyboard focus waits for row allocation and retries the outer scroll while GTK refines estimated row heights, instead of a single idle attempt before a recycled target cell exists.
- The shared item factory was audited: bind always resets the ordinary GIcon before thumbnail work; refresh cancels prior jobs; callbacks check cancellation and item identity; unbind cancels/removes jobs; teardown disconnects display handlers. Density changes reconfigure live tiles. No factory rewrite or eager directory loading was needed.

## Modified implementation files

`src/views/browser.vala`, `src/window/window.vala`, `src/sidebar/places.vala`, `src/dialogs/shortcuts.vala`.

Regression updates: `tests/redesign.vala`, `tests/toolbars.vala`, `tests/ui.vala`, `tests/places.vala`, `tests/theme-layout.py`, `tests/theme-integration.vala`, and the redesign timeout in `meson.build`.

## Verification

The mapped fixture creates 1,500 files, waits for enumeration/selection, verifies direct GtkScrollable parenting and realistic adjustments, and checks rendered filename labels intersect the viewport at positions 0, 750, 1499 and back at 0. It covers None/Type/Modified Date grouping, Compact/Standard/Large density, and 600/1100px windows. Newly realized grouped rows can refine height estimates, so scroll-to-item requests are bounded and retried after allocation. Snapshots preserve the actual scroll position.

Additional mapped checks reach the final item in List, Columns and Gallery, and in Open, Open Multiple, Save, Select Folder and SaveFiles. Folder-only choosers use a separate fixture of 1,500 directories, preserving their real filtering policy. Existing portal response and security tests remain unchanged.

Toolbar tests use real X11 secondary-button input, inspect the actual menu labels, read clipboard results from both copy actions, verify Edit Address, and reject generic content menus after toolbar/sidebar clicks. They measure the address/search outer allocation ratio and check 700/800/1100px layouts. Existing chooser, mutation, preview and keyboard tests remain enabled.

Visual evidence is generated under `build/regression-evidence/`: light/dark Majoris Grid top/middle/bottom, grouped views, toolbar/navigation and chooser snapshots, and native location-menu screenshots. Window-only GTK snapshots omit native popover surfaces, so menu evidence additionally captures the X11 root surface.

### Results

- `meson setup build --reconfigure`: succeeded.
- `meson compile -C build` (Debian WSL, six build jobs): succeeded; existing generated-C/deprecation warnings remain.
- `GTK_A11Y=none meson test -C build --print-errorlogs`: **16 passed, 0 failed, 0 skipped, 0 timed out**. The expanded redesign suite completed in 94.26 seconds; its timeout is 180 seconds.
- `python tests/theme-layout.py` and `git diff --check`: passed.
- Measured full toolbar location/search outer-width ratios: approximately 3.08 in the fallback theme and 3.09 in Majoris. At 700/800px the compact search interaction is visible instead, with the location given the remaining width.
- Both final Majoris light/dark large-directory matrices passed (86.45/86.82 seconds), including all chooser modes. Both themed toolbar/action/clipboard/native-menu fixtures passed. An additional theme-integration run with requested `GDK_DPI_SCALE=1.5` completed and produced all responsive screenshots; exhaustive effective font scaling remains a manual check because the theme controls typography.
- Visually inspected real Majoris light/dark captures of the grouped heading, middle viewport, final files, Recent label, toolbar ratio and native location menu. Files near 1499 are visibly rendered, with ordinary icons when thumbnails are unavailable.

## Environment and limits

Built and tested through Debian WSL with GTK 4.18.6, installed majoris-ui-gtk4, Xvfb/X11 and Cairo. Headless runs use `GTK_A11Y=none` because independently launched accessibility buses can collide in this environment. Majoris Theme acceptance uses its existing `scripts/with-majoris-gtk4.sh` bridge and FORCE_DARK for dark captures. The native theme bridge emits pixman rectangle diagnostics during some grouped reallocations; Xvfb without a compositor shows black outside native popup shadows. These are recorded rather than hidden by application CSS. Physical Wayland sessions, real removable/remote devices, and an exhaustive font-scale matrix remain manual acceptance checks.
