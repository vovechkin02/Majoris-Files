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
    ".files-navigation, .files-commands { padding: 6px 12px; }",
    ".files-status { padding: 6px 12px; }",
    ".files-section { padding: 12px 10px 4px; }",
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
