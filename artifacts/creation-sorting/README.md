# Creation and sorting verification evidence

Generated on Debian WSL/X11 using GTK 4.18.6, the installed Majoris Toolbar library and the supplied Majoris Theme in isolated GTK configuration. No Files CSS was added.

| Check | Light | Dark |
|---|---|---|
| Navigation and secondary toolbars | [PNG](light/toolbar/standard.png) | [PNG](dark/toolbar/standard.png) |
| Narrow layout | [PNG](light/toolbar/narrow.png) | [PNG](dark/toolbar/narrow.png) |
| Empty-space menu | [PNG](light/menus/empty-light.png) | [PNG](dark/menus/empty-dark.png) |
| New Folder in Grid | [PNG](light/grid-folder.png) | [PNG](dark/grid-folder.png) |
| New File in Grid | [PNG](light/grid-file.png) | [PNG](dark/grid-file.png) |
| New Folder in List | [PNG](light/list-folder.png) | [PNG](dark/list-folder.png) |
| New File in List | [PNG](light/list-file.png) | [PNG](dark/list-file.png) |
| Inline creation in Columns | [PNG](light/columns-folder.png) | [PNG](dark/columns-folder.png) |
| Nested-column destination | [PNG](light/columns-nested-file.png) | [PNG](dark/columns-nested-file.png) |
| Inline creation in Gallery | [PNG](light/gallery-folder.png) | [PNG](dark/gallery-folder.png) |
| Name sorting | [PNG](light/sort-name.png) | [PNG](dark/sort-name.png) |
| Size sorting | [PNG](light/sort-size.png) | [PNG](dark/sort-size.png) |
| Modified sorting | [PNG](light/sort-modified.png) | [PNG](dark/sort-modified.png) |

The empty-space menu captures use real X11 pointer input. GTK supplies all sort
indicators; exactly one native sort column remains active. Creation captures
preserve the current scroll position so the selected editor stays visible.
Grouped Grid is exercised with at least 1,500 files without a full-tree bitmap
capture. Additional provider/date/chooser captures are included in each palette.

Reproduce after building:

```sh
GTK_A11Y=none meson test -C build --print-errorlogs
python3 tools/capture-creation-sorting.py /path/to/Majoris-Theme
```

The capture runner also supports `--creation-only` and `--chrome-only` for
refreshing independent evidence sets. Images render on temporary Linux storage
before being copied here, avoiding ImageMagick overwrite errors on drvfs.

See [the completion report](../../docs/creation-sorting-report.md) for implementation,
coverage and platform limits. Build/test logs are included here after verification.
