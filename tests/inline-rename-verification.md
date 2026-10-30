# Inline rename verification — 30 October 2026

## Environment and commands

Verified using elevated access to the Debian WSL2 distribution on the Windows host.
Meson 1.7.0, Vala 0.56.18, GTK 4.18.6, libadwaita 1.7.6 and majoris-ui-gtk4 0.1.0.
Mapped GTK tests ran on X11 under Xvfb; native interaction tests used xdotool.

```sh
meson setup build --reconfigure
meson compile -C build
GTK_A11Y=none meson test -C build --num-processes 1 --print-errorlogs
```

The final full suite passed **17/17 targets**, with zero failures, skips or timeouts.
The additional `/inline-rename/permission-denied` case was added afterward,
compiled and executed separately; it passed. Product sources were unchanged
between the full passing suite and this additional test.

`GTK_A11Y=none` disables the accessibility bridge only for verification.
Earlier parallel runs encountered shared accessibility/D-Bus session failures.
The final serial run completed successfully. Compiler warnings remain; the build
completed without errors.

## Automated coverage executed

- Filename stems, multi-dot names, dotfiles, extensionless names, spaces, Unicode,
  and full-name selection for folders.
- Real F2 and repeat-F2 selection toggling in all four file views.
- Enter commit, Escape cancellation, unchanged names, empty-name validation,
  existing destination conflicts, proposed-text retention, and successful retry.
- Tab commit and native outside clicks in all four views.
- Ctrl+A/C/X/V and End acting on filename text without changing file selection.
- Extension-warning decline retains the proposed text; acceptance renames once.
- Real Ctrl+Z/Ctrl+Shift+Z restore/reapply filenames and preserve selection.
- 1,500-file fixture: positions 0, 750 and 1499 in Grid, grouped Grid, List,
  Columns and Gallery. Each editor is checked against the correct GFile;
  detaching its presentation preserves the Browser transaction without submitting.
- Real permission denial after editing begins: original file remains, proposed
  text and error remain available, and retry succeeds after permissions return.
- Existing core, cloud, filesystem, batch-rename undo, crash-recovery, UI, session,
  portal, redesign, sidebar, theme, toolbar and details-correction targets.
- `git diff --check` and `python tests/theme-layout.py` passed.

The stress fixture keeps its metadata database outside the watched directory.
An earlier fixture stored the database among its files, causing self-triggered
refreshes and a timeout; the corrected stress case passed in about 16 seconds.

## Visual evidence

Eight mapped-window PNGs and corresponding widget-tree JSON files are in
`build/inline-evidence/`: Grid, List, Columns and Gallery, each in light and dark.
All eight PNGs were visually inspected. The icon remains visible, the editor is
in the filename area, selection and focus are visible, and no confirmation
buttons are added. Grid text scrolls horizontally within the normal label width.

The PDF fixtures contain placeholder text, so their large preview correctly shows
“Preview unavailable”; these captures do not verify successful PDF rendering.

## Fixes found during verification

- Composed Gtk.Stack inside Gtk.Box because Gtk.Stack is a final type.
- Corrected window event-controller installation and batch-action dispatch.
- Tracked filename cells independently of list-item children during teardown.
- Realized offscreen selections and applied stem selection after focus settles.
- Retained normal filename width while editing.
- Forwarded native text keys to the actual focused widget and retained focus
  while a rename is pending, avoiding a GtkText focus warning.
- Preserved root-column selection and existing column scrollers during monitor
  refreshes; reconciled descendant folder references.
- Added rename-history notifications so Undo/Redo can reconcile selected GFiles.
- Updated the toolbar regression test to use the inline editor.

## Remaining acceptance limits

This run does not establish every manual acceptance scenario. In particular,
there was no live remote-disconnection or mounted read-only filesystem fixture,
no exhaustive external replacement/deletion race test, and no dedicated native
pointer test for renaming an opened ancestor folder in a multi-column hierarchy.
The shared error path, permission denial and identity checks are covered to the
extent described above. The optional delayed second-click gesture remains absent.
