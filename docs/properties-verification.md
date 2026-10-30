# Properties redesign verification

## Executed results

- Debian WSL build completed successfully using Meson 1.7.0, Vala 0.56.18,
  GTK 4.18.6, libadwaita 1.7.6 and majoris-ui-gtk4 0.1.0.
- Full serial Meson suite: **18/18 targets passed**, zero failures, skips or
  timeouts. Log: `build/properties-final-suite.log`.
- The application chooser footer was subsequently refined. All targets were
  rebuilt and the Properties target was rerun against that refinement. Logs:
  `build/properties-delivery-build.log` and `build/properties-delivery-test.log`.
- The themed, mapped Properties workflow also passed with the fixed footer.
  Log: `build/properties-footer-test.log`.
- `git diff --check` and `python tests/theme-layout.py` passed.

The complete run used:

```sh
meson setup build --reconfigure
meson compile -C build
PATH="$PWD/build/properties-tools/acl/usr/bin:$PATH" \
FONTCONFIG_FILE="$PWD/build/properties-tools/fonts.conf" GTK_A11Y=none \
meson test -C build --num-processes 1 --print-errorlogs
```

The final incremental verification rebuilt all targets and ran
`meson test -C build properties --print-errorlogs` with the same process-local
test dependencies. The existing inline-rename, chooser, portal, filesystem,
crash-recovery, theme, toolbar and layout tests remain registered and passed in
the complete suite.

## New regression coverage

`tests/properties.vala` exercises actual mapped GTK widgets, real temporary files
and isolated application-association settings:

- General is the sole main page; identity, location copying, Favorites, Tags,
  folder contents and multiple selection work. Clearing the caller's selection
  does not change the dialog snapshot.
- Ordinary files have no Items or recursive Contents row. Unknown sizes and
  physical allocation remain unavailable rather than showing fabricated values.
- Sharing is excluded for files, mixed selections, remote locations, roots,
  mount roots and symbolic links. Symbolic links retain Link Target information
  and are not counted as their target directory.
- Native subpage Back and repeated navigation retain the same PermissionsPage;
  real X11 Alt+Left returns without closing Properties.
- Application rows select one proposed default. No selection disables Apply.
  Setting and resetting a MIME association updates General and never launches
  the file. The retained standalone Open With action launches a temporary test
  application without changing its default association. Local-only applications are unavailable for a remote URI.
- Set Default and Reset stay mapped in a fixed native footer while the app list
  scrolls; the final test checks their dialog bounds and unchanged footer Y
  position after scrolling.
- Actual basic and advanced permission operations, mixed/bulk modes, preserved
  execute/special bits, separate file/folder modes, explicit recursion, cancelled
  recursion and confirmed recursion were checked on temporary files. Details
  opened after an edit was checked against the current filesystem mode.
- Real getfacl/setfacl roundtrips retain a named ACL entry through a masked mode
  change. Extended ACLs disable misleading simplified controls.
- Sharing's reveal-only toggle performs no mutation. Mixed account rights show
  Custom Access; guest access is cleared/disabled when authentication is
  restricted. Publishing, external-state detection, Reload and cancelled/confirmed
  Stop Sharing use isolated command and D-Bus fixtures.
- Extension names containing ampersands remain literal text, not markup.
- Actual image, WAV audio and generated Theora video metadata load. Relevant
  fields appear without unrelated media fields. Unknown extension fields,
  extension property rows, cloud state/quota/online-only status and provider
  failure isolation remain accessible.
- Closing Properties cancels its coordinator token; embedded pages share its
  explicit final-close cleanup. Standalone page/dialog entry points remain.

`tests/core.vala` adds a regression for empty account descriptions, which the
ownership picker exposed during verification.

## Visual evidence

`build/properties-majoris-evidence/` contains **28 PNG captures** and corresponding
widget-tree JSON files: the twelve requested scenarios in light/dark, plus video
Details and a larger-text narrow-window probe. Representative captures were
visually reviewed across the page types and both appearances. The chooser capture
was refreshed after adding its fixed native footer.

The existing neighbouring Majoris-Theme checkout and its unchanged
`scripts/with-majoris-gtk4.sh` bridge supplied the real GTK4 appearance. No theme
sources, desktop settings or user theme installation were changed. Plus Jakarta
Sans normal/italic fonts and their OFL licence were staged only under
`build/properties-tools/fonts/`, using the official Google Fonts repository:
https://github.com/google/fonts/tree/main/ofl/plusjakartasans

A process-local fontconfig file selected those fonts. Widget-tree evidence
resolved the normal heading to Plus Jakarta Sans Bold 10.5 (18-pixel logical
height) and the 20px larger-text probe to Plus Jakarta Sans Bold 15 (26-pixel
logical height). The larger text override exists only in the regression test;
production UI adds no stylesheet.

The themed run used Xvfb, software NGL, and both Adw.StyleManager appearances.
The full fallback-theme suite used Cairo. Native scrolling handles overflow in
long General/advanced/metadata sections, while dialog geometry remains stable.

## Environment-dependent limits

- Sharing operations and privileged helper calls were exercised through private
  fixtures. No production Samba share, account password or firewall policy was
  changed. Live network clients and administrator authorization still require
  normal Majoris VM/service acceptance.
- Remote URI presentation and association eligibility were tested without a live
  remote server. Real GVfs disconnection/reconnection remains a provider test.
- GTK accessibility semantics and count completion announcements use native APIs;
  the automated run disabled the accessibility bridge to isolate D-Bus sessions.
  A real screen-reader/Wayland/Mutter session was not exercised.
- Non-fatal Pixman rectangle diagnostics occurred during themed scaling/capture
  transitions. Representative saved renders were inspected; this report does not
  claim the underlying renderer/theme diagnostic is fixed.
- Compiler warnings remain. An early portal/extension test failed transiently;
  it passed under the debugger and in the final complete 18-target run.

See [Properties architecture and source changes](properties.md).

## Identity and Information separation — 31 October 2026

The identity is now a horizontal Gtk.Box containing the existing 48px image and
one selectable, wrapping heading label. The old identity_description() and all
count-driven identity subtitle updates were removed. No production CSS was added.

General uses a separate PropertiesInformationRow helper: native ActionRow titles
on the left and selectable suffix values aligned right. Long values ellipsize,
with the full value in a tooltip; Copy Location still copies the full native path
or URI. The shared value_row() used by advanced pages is unchanged.

Type and Size precede Location and Modified. Folders insert Contents after Size.
The existing FileCounts scan updates Size and Contents, preserves partial/error
states and cancellation, and continues updating exact/allocated storage in Details.
Ordinary files use their existing size attributes without a recursive scan.
Multiple selections show a count in the header and only Type, Size and Location
in Information. Duplicate Types and Total Size rows were removed.

Modified files: src/dialogs/properties.vala, tests/properties.vala,
docs/properties.md and this verification report.

The mapped Properties regression was extended with ordered Information rows,
header structure and stability, a long Unicode filename, enlarged text, unknown
size, symlink type, mixed-parent selection, read-only files, empty and 1,500-file
folders, unreadable partial totals and cancellation. Existing functional tests
for navigation, applications, organisation, permissions, sharing and Details remain.
The chooser footer geometry assertion now waits for layout settling and permits
one pixel of rounding difference.

The real Majoris Theme run passed /properties/redesign in 76.08 seconds. It wrote
30 PNGs and matching widget-tree JSON under build/identity-evidence. All six
required General scenarios were inspected in both light and dark: document,
image, folder, multiple selection, long filename, and narrow enlarged text.
The header wrapped without clipping, values remained separate and the Copy
Location button stayed visible. Screenshots include the native focus selection
on the selectable filename. Non-fatal Pixman diagnostics still occurred during
theme transitions; the environment-dependent limits above continue to apply.

Commands and logs for this update:

- meson setup build --reconfigure: build/identity-configure.log
- meson compile -C build: build/identity-full-build.log
- meson test -C build --num-processes 1 --print-errorlogs: build/identity-suite.log
- Majoris bridge mapped UI run: build/identity-visual.log
Reconfigure and full compilation succeeded. The complete serial suite passed
18/18 targets with zero failures, skips or timeouts, including inline-rename
(145.33 seconds), details-corrections and Properties (58.57 seconds). Existing
compiler warnings remain. git diff --check reported no whitespace errors.
