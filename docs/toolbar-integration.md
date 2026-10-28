# Universal Majoris Toolbar integration

Files consumes `Majoris.Ui.Toolbar` from the installed `majoris-ui-gtk4` package.
The required API is the Theme's Vala library, version 0.1.0+, SONAME 0. There is
no copied Toolbar source, private shared library, purpose-specific subclass or
Files-owned Toolbar stylesheet. GTK 4.18+ is required consistently by Meson and
Debian metadata.

## Migrated strips

| Source | Universal Toolbar contents |
|---|---|
| `src/views/browser.vala` — navigation | Sidebar toggle; history group; Up, Other Locations and Refresh group; separator; existing location stack; Search; Search Options; narrow Search action. |
| `src/views/browser.vala` — commands | New Folder/Cut/Copy/Paste group; separator; Rename/Share/Trash group; expanding spacer; Sort; segmented Grid/List/Columns/Gallery; View Settings; Preview; narrow File Actions menu. Chooser mode retains only its reduced view controls. |
| `src/preview/pdf.vala` | Previous page, page counter, next page, zoom in/out. Counter uses the public metadata class. Compact density. |
| `src/preview/sandbox.vala` | Image zoom in/out, fit and preview-only rotation. Compact density; persistent rotation remains a separate file action. |
| `src/preview/animation.vala` | Play/pause, zoom in/out and fit. Compact density; animation timers/cancellation/reduced-motion behavior remain native. |

All strips use the public append/group/separator/spacer APIs. Existing callbacks,
GActions, tooltips and accessible labels remain application-owned. The New Folder
icon-and-label child has the documented 8px gap and 16px artwork and opts into
`majoris-toolbar-action`. Standalone controls are designated by `append_control`;
custom composites use `append_widget`.

The location stack still contains its existing breadcrumb box, entry, scroller
and completion popover. Its public `majoris-location-*` styling and editing state
are preserved. The Toolbar does not traverse those internals. Breadcrumbs use the
existing drop handler and retain click/middle-click navigation.

The view switcher is a single `majoris-toolbar-segmented` box with native grouped
ToggleButtons. It is inserted intact with `append_widget`. Programmatic changes
update the selected segment through the existing `set_view` path. Native Arrow/Tab traversal and Space activation preserve keyboard focus and
selection. No new key dispatcher intercepts existing Alt+Left/Right history or
other browser shortcuts. The existing global Space preview action temporarily
yields while a universal toolbar owns focus, allowing native button/segment Space
activation; file-content quick preview and its action name/shortcut are retained.

## Responsive layout

Standard density is used for both browser rows. At the existing 650px breakpoint,
Up/Refresh hide but remain available through Alt+Up/F5. Other Locations and
Collections remains visible, preserving access to tags, saved searches and devices. The same SearchEntry
is moved into a Search popover using public mutation methods; Ctrl+F opens it.
Returning to a wide window reinserts the entry beside the location stack.

File operations, selection actions and Sort move into a native overflow MenuModel
using the same `win.*` actions and current Share model. Their original groups and
separator explicitly hide together. The view segments and settings remain readily
accessible. EXTERNAL horizontal scrollers provide a final keyboard-focus scrolling
fallback without a visible scrollbar. No fixed toolbar heights or negative offsets
are imposed; larger fonts can increase allocations.

Navigation and commands both request the Theme's inset divider. There are no
Files border/padding rules for either toolbar, and no doubled outer wrapper padding.
The only remaining application layout CSS is `.files-status`.

## Audit boundaries

`Adw.ToolbarView`, `Adw.HeaderBar` and `Adw.TabBar` are unchanged structural/window
components. Headerbar New Tab, progress and menus stay in the headerbar. Chooser
accept/cancel, form/footer button rows, Search Filters, sharing-dialog form buttons
and per-record action-row suffixes remain ordinary layouts. The horizontal image
comparison in `preview/thumbnail.vala` is content, not a toolbar. Breadcrumbs,
segmented controls, sidebar rows, file cells, columns, and icon/label children are
also ordinary composites. `Gtk.MediaControls` and `Gtk.Video` retain complete GTK
playback semantics; there was no extra Files-owned playback strip to replace.

## Build and packaging

Meson requires `dependency('majoris-ui-gtk4', version: '>=0.1.0')` and links it through
the existing executable/test dependency array. Debian Build-Depends and runtime
Depends use the documented package name `majoris-ui-gtk4`; `${shlibs:Depends}` also
tracks SONAME 0. `debian/rules` continues using normal debhelper/Meson/shlibdeps.
`xdotool` is declared for native keyboard regression tests. No custom loader or
VAPI paths are required after installing the library outputs.

The supplied Theme archive documents the package name and ABI and installs all
public outputs with Meson, but does not include a Debian control file for this
library (its Debian control belongs to login resources). For verification, the
unchanged upstream Meson outputs were staged outside Files and installed into WSL
as a local `majoris-ui-gtk4` validation package containing the library, VAPI, header,
`.deps` and pkg-config metadata. Production ISO packaging must ship those same
outputs under the documented package name. No guessed separate `-dev` package or
application-private copy was introduced.

## Reproduce verification

```sh
meson setup build --reconfigure
meson compile -C build
meson test -C build --print-errorlogs
python3 tools/capture-toolbars.py /path/to/Majoris-Theme
python3 tools/report-toolbars.py
python3 tools/build-debian.py
```

The theme-ownership test remains and now enforces the packaged dependency,
canonical Toolbar/segmented API, isolated location composite, lack of duplicated
styling and preserved data/sidebar contracts. `tests/toolbars.vala` exercises real
file callbacks, GActions, history, autocomplete/search/options, exclusive views,
actual X11 keyboard input, per-folder settings, tabs, overflow/search reparenting,
chooser controls, public mutations and native image/animation/PDF controls.
Existing UI/portal tests cover Open, Open Multiple, Save, Select Folder and SaveFiles.

Native evidence and realised allocation records are under
[`artifacts/toolbar-integration`](../artifacts/toolbar-integration/), with the
[geometry report](../artifacts/toolbar-integration/geometry.md). The capture runner
uses an isolated installed GTK4 user override, the official stylesheet and real
font files. It does not alter Files theme loading or system desktop settings.

## Final validation — 28 October 2026

- Final source build: 16/16 Meson suites passed, with no failures, skips or
  timeouts. The existing theme-ownership test passed.
- Clean Debian package build: 16/16 suites passed. The resulting
  `build/majoris-files_0.1.0-1_amd64.deb` declares GTK 4.18 and
  `majoris-ui-gtk4 (>= 0.1.0)`. Its executable requires
  `libmajoris-ui-gtk4.so.0`; extraction and launch succeeded using the installed
  system library, without `LD_LIBRARY_PATH`. Files itself was not installed.
- Upstream SDK validation: all three contract/API/external-consumer checks and
  all four light/dark, scale 1/2 geometry checks passed.
- Final Files evidence: 54 screenshots across light/dark, scale 1/2 and enlarged
  text. Each case includes ordinary, keyboard-focus, maximised, narrow, Open,
  Save, image, animation and PDF windows. All six native action runs passed.
- Measured standard toolbar rows are 40 logical pixels, with 32px ordinary
  controls, 28px compact preview controls, 16px artwork and 4px group gaps.
  Location shells remain 32px and breadcrumbs 26px, including under text stress.
  Enlarged text naturally grows browser rows to 51px and PDF rows to 49px;
  measured Pango ink/logical extents fit. No toolbar height is forced by Files.
- Final source audit and `git diff --check` passed. Obsolete `files-navigation`
  and `files-commands` styling is absent from application source and resources.

Validation ran under Debian/WSL with GTK 4.18.6, libadwaita 1.7.6 and native
X11/Xvfb windows. Physical GPU/Wayland sessions and production ISO installation
remain unverified. The supplied archive does not include a Debian recipe for
the UI library: production package-feed provisioning remains an external
prerequisite, as described above. Hosted CI against that feed was not run.
Existing compiler warnings and WSL portal/GVfs/PipeWire/service-shutdown warnings
remain; they did not fail the tests. No application clipping or toolbar runtime
failure was observed in the tested matrix.

## Changed-file inventory

- `src/views/browser.vala`: navigation/commands, location and segmented composites,
  responsive search and action overflow, breadcrumb drop integration.
- `src/preview/{pdf,sandbox,animation}.vala`: compact preview strips.
- `src/window/window.vala`: focus-aware quick-preview availability so native
  toolbar controls retain Space activation and content retains quick preview.
- `meson.build`, `debian/control`: packaged SDK/GTK requirements and native tests.
- `data/theme/files.css`: removal of the obsolete navigation/command inset rule;
  only the status row inset remains.
- `tests/{toolbars,redesign}.vala`, `tests/theme-layout.py`: native behavior and
  geometry contracts, updated ownership assertions.
- `tools/{capture-toolbars,report-toolbars,verify-toolbar-runtime}.py`: reproducible
  screenshot/allocation evidence and extracted-package runtime verification.
- `README.md`, `docs/{platform-integration,theme-integration,toolbar-integration}.md`:
  dependency, migration and validation documentation.
- `artifacts/toolbar-integration/`: final captures, allocation records, font
  resolution, native logs and geometry summary. No SDK source or library is
  vendored in Files.
