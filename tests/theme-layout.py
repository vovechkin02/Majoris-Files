"""Guard the boundary between Files layout and the GNOME-owned theme."""
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
theme = root / "data/theme"
assert {p.relative_to(theme).as_posix() for p in theme.rglob("*") if p.is_file()} == {"files.css"}
manifest = ET.parse(root / "data/files.gresource.xml")
assert [node.text for node in manifest.iter("file")] == ["theme/files.css"]
css = (theme / "files.css").read_text()
assert css.strip().splitlines() == [
    ".files-navigation, .files-commands { padding: 4px 16px; }",
    ".files-status { padding: 4px 16px; }",
]
loader = (root / "src/window/theme.vala").read_text()
assert "StyleManager" not in loader
assert loader.count("load_from_resource(") == 1
assert '"/com/majoris/files/theme/files.css"' in loader
browser = (root / "src/views/browser.vala").read_text()
assert "toolbar.margin_" not in browser
assert "new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4)" in browser
assert "files-location" not in browser
print("Files layout and GNOME theme ownership checks passed")

for family in ("majoris-data-grid", "majoris-data-list", "majoris-data-column",
               "majoris-data-tile", "majoris-data-artwork", "majoris-data-thumbnail",
               "majoris-data-cell", "majoris-data-metadata", "majoris-density-compact",
               "majoris-sidebar-heading", "majoris-sidebar-heading-first"):
    assert family in browser, family
assert "files-section" not in browser + css
assert "if (chooser_mode) adaptive.add_breakpoint" not in browser
assert "body.position = 224" in browser
assert "icon.pixel_size = grid ? icon_size : 16" in browser
assert "box.margin_" not in browser
assert "list.show_column_separators = false" in browser
