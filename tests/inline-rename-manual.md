# Inline rename verification

Run on Debian 13 with GTK >= 4.18 and majoris-ui-gtk4 installed:

```sh
meson setup build --reconfigure
meson compile -C build
meson test -C build --print-errorlogs
```

The inline-rename executable maps real GTK widgets under Xvfb. It covers UTF-8
stem selection, directories/dotfiles, error text retention, cell detachment,
and a 1,500-file directory in Grid, List, Columns and Gallery.
It was executed successfully through Debian WSL. See `inline-rename-verification.md` for results and remaining limits.

Remaining graphical acceptance checks (both light and dark):

- F2, toolbar and context Rename; repeat F2 toggles stem/full selection.
- Enter and outside clicks commit once; Tab advances focus; Escape never commits.
- Ctrl+A/C/X/V, arrows and Home/End act on text.
- Empty names, separators and collisions retain input; permission/read-only and
  disconnected remote errors remain correctable.
- Extension warning accepts once; declining restores the proposed text.
- Unchanged names create no journal entry; undo/redo restore filenames.
- Grid/grouped Grid at all densities: icon and neighbouring cells remain stable.
- List: other columns and widths remain stable.
- Columns: rename in parent/middle/last columns; check opened descendants after
  directory monitors refresh, including folder location references and scroll.
- Gallery: preview, metadata and previous/next navigation survive rename.
- Scroll at beginning/middle/end of 1,500 files; sort, group, filter and refresh
  during editing; no recycled cell may submit a different file.
- Delete/move/externally rename the original during editing and confirmation.
- Switch views/tabs, navigate and close: no destruction-triggered rename.
- Open/Save/folder chooser flows and batch rename retain existing behavior.
- Capture screenshots in every view, in light and dark themes.

Mapped GTK tests, native keyboard/pointer checks and all eight screenshots have
now been verified in Debian WSL. Live remote/read-only backends and exhaustive
ancestor-column reconciliation remain manual acceptance limits.
The optional delayed second-click rename gesture is not implemented.
