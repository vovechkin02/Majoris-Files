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
    ".files-status { padding: 4px 16px; }",
]
loader = (root / "src/window/theme.vala").read_text()
assert "StyleManager" not in loader
assert loader.count("load_from_resource(") == 1
assert '"/com/majoris/files/theme/files.css"' in loader
browser = (root / "src/views/browser.vala").read_text()
assert "toolbar.margin_" not in browser
assert browser.count("new Majoris.Ui.Toolbar()") == 2
assert "toolbar.append_widget(address_fields)" in browser
assert "address_fields.attach(location_bar, 0, 0, 3, 1)" in browser
assert "majoris-toolbar-segmented" in browser
assert "commands.append_widget(switcher)" in browser
assert "majoris-toolbar-view-switcher" not in browser
assert "files-navigation" not in browser + css
assert "files-commands" not in browser + css
assert "majoris-toolbar" not in css
build = (root / "meson.build").read_text()
assert "dependency('majoris-ui-gtk4'" in build
assert "dependency('gtk4', version: '>=4.18')" in build
assert "ui/toolbar.vala" not in build
for name in ("pdf", "sandbox", "animation"):
    preview = (root / "src/preview" / (name + ".vala")).read_text()
    assert "new Majoris.Ui.Toolbar()" in preview
    assert "controls.compact = true" in preview
assert not list((root / "src").rglob("toolbar.vala"))
assert "files-location" not in browser

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

# Ungrouped native views must not create even an invisible section header.
assert 'list.header_factory = group_headers()' not in browser
assert 'strip.header_factory = group_headers()' not in browser
assert 'label.visible = group_key != "None"' not in browser
assert browser.count('update_group_headers();') == 2
assert 'var headers = group_key == "None" ? null : section_headers;' in browser

assert 'set_state_flags' not in browser
assert 'add_css_class("selected")' not in browser
assert 'add_css_class("focused")' not in browser

# Files specifies toolbar membership; the public Theme API specifies geometry.
assert "append_group(" not in browser
assert "append_separator(" not in browser
assert "var up_control = button(" in browser
assert "toolbar.append_control(up_control)" in browser
assert "commands.append_spacer()" in browser
assert "address_fields.column_spacing = 8" in browser
window = (root / "src/window/window.vala").read_text()
assert window.count("toolbar.add_top_bar(") == 1
assert "toolbar.add_top_bar(header)" in window
assert "new Gtk.Box(Gtk.Orientation.VERTICAL, 0)" in window
assert "toolbar.content = document_content" in window
assert window.index("document_content.append(tabbar)") < window.index("document_content.append(recovery_banner)") < window.index("document_content.append(tabs)")
assert 'tabbar.view = tabs' in window
assert 'tabbar.add_css_class("majoris-document-tabs")' in window

print("Files layout and GNOME theme ownership checks passed")
