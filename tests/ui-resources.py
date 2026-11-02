"""Build-time resource, translation and composite-template binding checks."""
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
manifest = ET.parse(root / "data/files.gresource.xml")
resources = {node.text for node in manifest.iter("file")}
interfaces = {p.relative_to(root / "data").as_posix() for p in (root / "data/ui").glob("*.ui")}
assert resources == interfaces, (resources - interfaces, interfaces - resources)
templates = {}
for name in sorted(interfaces):
    tree = ET.parse(root / "data" / name)
    assert tree.getroot().get("domain") == "majoris-files", name
    ids = [n.get("id") for n in tree.iter() if n.get("id")]
    assert len(ids) == len(set(ids)), name
    for template in tree.iter("template"):
        templates[name] = template
    for obj in tree.iter("object"):
        props = [n.get("name") for n in obj.findall("property")]
        assert len(props) == len(set(props)), (name, obj.get("id"), props)
for source in (root / "src").rglob("*.vala"):
    text = source.read_text(encoding="utf-8")
    matches = list(re.finditer(r'\[GtkTemplate\s*\(ui\s*=\s*"/com/majoris/files/(ui/[^"]+)"\)\]\s+(?:public\s+)?class\s+(\w+)\s*:\s*([\w.]+)', text))
    for i, match in enumerate(matches):
        name, cls, parent = match.groups()
        assert "typeof(" + cls + ")" in (root / "tests/ui-resources.vala").read_text(), ("Template missing from runtime registry", cls)
        template = templates[name]
        assert template.get("class") == "MajorisFiles" + cls, name
        assert template.get("parent") == (parent.replace(".", "") if "." in parent else "MajorisFiles" + parent), name
        # Stop at the next class, including classes that do not use templates.
        end = re.search(r'\n    (?:public )?class ', text[match.end():])
        body = text[match.end():match.end() + end.start()] if end else text[match.end():]
        assert "dispose_template(typeof(" + cls + "))" in body, ("Missing template disposal", cls)
        for slot in ("child", "content", "extra_child"):
            if template.find('property[@name="' + slot.replace("_", "-") + '"]') is not None:
                assert slot + " = null;" in body, ("Clear native single-child slot before disposal", cls, slot)
        ids = {obj.get("id") for obj in template.iter("object")}
        for child in re.finditer(r'\[GtkChild(?:\s*\([^]]+\))?\]\s+(?:(?:public|private|protected)\s+)?(?:unowned\s+)?[\w.]+\s+(\w+)', body):
            assert child[1] in ids, (source, name, child[1])
        for signal in template.iter("signal"):
            assert re.search(r'\[GtkCallback\]\s+(?:\w+\s+)*' + signal.get("handler") + r'\s*\(', body), (name, signal.get("handler"))
potfiles = (root / "po/POTFILES").read_text().splitlines()
assert all("data/" + name in potfiles for name in interfaces), "UI resources missing from translation extraction"
assert not list((root / "data").rglob("*.css"))
for source in (root / "src").rglob("*.vala"):
    assert "CssProvider" not in source.read_text(), source
print(f"Validated {len(interfaces)} interfaces and {len(templates)} composite templates")
if len(sys.argv) > 1:
    Path(sys.argv[1]).write_text("validated\n")
