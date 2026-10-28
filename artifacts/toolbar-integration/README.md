# Native universal Toolbar evidence

Generated from the final Files implementation with the supplied Majoris-Theme.
See [migration and validation report](../../docs/toolbar-integration.md) and
[measured geometry](geometry.md).

The six directories cover light/dark at scale 1, scale 2 and font-only enlarged
text stress. Each contains nine PNG screenshots with matching realised GTK JSON
allocation trees: standard, keyboard-focus, maximised, narrow, open-chooser,
save-chooser, image-preview, animation-preview and pdf-preview. `native.log`
records the action checks; `font-resolution.txt` records the actual font used.

Reproduce with `python3 tools/capture-toolbars.py /path/to/Majoris-Theme`, then
`python3 tools/report-toolbars.py`, in the configured Linux build environment.
The large-text fixture deliberately uses descenders in “New Folder gjpqy” and
enlarges search/metadata text to verify natural sizing and clipping behavior.
