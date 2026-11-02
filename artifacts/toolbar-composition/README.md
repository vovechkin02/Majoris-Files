# Native toolbar composition evidence

See [implementation and measurements](../../docs/toolbar-composition.md).

Each appearance directory contains unedited native GTK PNG screenshots and
matching widget allocation JSON. `native.log` records the regression result;
`font-resolution.txt` identifies the actual resolved font.

- `files-480/650/800/1100`: recovery hidden and all requested responsive widths.
- `recovery-revealed`: tabs, revealed banner, navigation and commands.
- `open-chooser-*`, `save-chooser-*`: both chooser modes at all four widths.
- `standard`, `keyboard-focus`, `maximised`, `narrow`: existing interaction views.
- `image-preview`, `animation-preview`, `pdf-preview`: compact toolbar regressions.

`allocations.json` summarises measured gaps and heights. Recheck with:

```sh
python3 tests/verify-theme-geometry.py --toolbars artifacts/toolbar-composition
```
