"""Guard the boundary between Files layout and the GNOME-owned theme."""
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
theme = root / "data/theme"
assert not list(theme.rglob("*.css"))
manifest = ET.parse(root / "data/files.gresource.xml")
assert all(node.text.startswith("ui/") for node in manifest.iter("file"))
assert not (root / "src/window/theme.vala").exists()
css = ""
ui = "\n".join(p.read_text() for p in (root / "data/ui").glob("*.ui"))
browser = (root / "src/views/browser.vala").read_text()
assert "toolbar.margin_" not in browser
assert browser.count("new Majoris.Ui.Toolbar()") == 2
assert "toolbar.append_widget(address_fields)" in browser
assert "address_fields.attach(location_bar, 0, 0, 3, 1)" in browser
assert "majoris-toolbar-segmented" in ui
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
    assert family in browser + ui, family
assert "files-section" not in browser + css
assert "if (chooser_mode) adaptive.add_breakpoint" not in browser
assert '<property name="position">224</property>' in ui
assert "icon.pixel_size = grid ? icon_size : 16" in browser
assert "box.margin_" not in browser
assert '<property name="show-column-separators">false</property>' in ui

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
assert 'controls.get_object("up")' in browser
assert "toolbar.append_control(up_control)" in browser
assert "commands.append_spacer()" in browser
assert '<property name="column-spacing">8</property>' in ui
window = (root / "src/window/window.vala").read_text()
window_ui = ET.parse(root / "data/ui/window.ui")
assert window_ui.find('.//object[@class="AdwToolbarView"]') is not None
assert len(window_ui.findall('.//child[@type="top"]')) == 1
assert window_ui.find('.//object[@class="AdwHeaderBar"]') is not None
assert window_ui.find('.//object[@class="AdwTabOverview"]/property[@name="view"]').text == "tabs"
bar = window_ui.find('.//object[@class="AdwTabBar"]')
assert bar.find('property[@name="view"]').text == "tabs"
assert bar.find('style/class[@name="majoris-document-tabs"]') is not None
content = window_ui.find('.//object[@class="AdwToolbarView"]/property[@name="content"]/object')
assert [c.find("object").get("class") for c in content.findall("child")] == ["AdwTabBar", "AdwBanner", "AdwTabView"]
assert 'new Adw.TabView' not in window
assert 'new Adw.TabBar' not in window
assert 'new Adw.TabOverview' not in window

print("Files layout and GNOME theme ownership checks passed")
