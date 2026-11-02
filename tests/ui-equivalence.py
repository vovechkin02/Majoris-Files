"""Compare native before/after capture geometry without comparing random paths.

Usage: python tests/ui-equivalence.py build/ui-migration-before build/ui-migration-after
The status-area change is recorded separately: it now uses Majoris-Theme's
shared statusbar instead of the removed application CSS.
"""
from pathlib import Path
import json
import sys

before, after = map(Path, sys.argv[1:3])

def walk(node):
    yield node
    for child in node.get("children", []):
        yield from walk(child)

def family(tree, name):
    return [n for n in walk(tree) if name in n.get("classes", [])]

def geometry(node):
    return tuple(round(node[k], 2) for k in ("absolute_x", "absolute_y", "bounds_width", "bounds_height"))

report = {}
for path in sorted(before.glob("*/*.json")):
    target = after / path.relative_to(before)
    assert target.exists(), target
    assert path.with_suffix(".png").exists() and target.with_suffix(".png").exists()
    old, new = json.loads(path.read_text()), json.loads(target.read_text())
    assert geometry(old) == geometry(new), (path, "window geometry")
    for name in ("majoris-document-tabs", "majoris-toolbar", "majoris-location-bar", "majoris-toolbar-segmented"):
        left, right = family(old, name), family(new, name)
        assert len(left) == len(right), (path, name, len(left), len(right))
        assert [geometry(n) for n in left] == [geometry(n) for n in right], (path, name)
    left = [n for n in walk(old) if n.get("node") == "headerbar"]
    right = [n for n in walk(new) if n.get("node") == "headerbar"]
    assert [geometry(n) for n in left] == [geometry(n) for n in right], (path, "headerbar")
    old_status, new_status = family(old, "files-status"), family(new, "majoris-statusbar")
    assert len(old_status) == len(new_status) == 1, path
    delta = new_status[0]["bounds_height"] - old_status[0]["bounds_height"]
    left, right = family(old, "navigation-sidebar"), family(new, "navigation-sidebar")
    assert len(left) == len(right), path
    for a, b in zip(left, right):
        assert geometry(a)[:3] == geometry(b)[:3], (path, "sidebar placement/width")
        assert abs(a["bounds_height"] - b["bounds_height"] - delta) <= 1, (path, "sidebar viewport")
    left, right = family(old, "majoris-data-tile"), family(new, "majoris-data-tile")
    old_tiles = {(n["absolute_x"], n["absolute_y"]): geometry(n) for n in left}
    new_tiles = {(n["absolute_x"], n["absolute_y"]): geometry(n) for n in right}
    if old_tiles:
        shared = old_tiles.keys() & new_tiles.keys()
        assert shared, (path, "no matching tiles")
        assert all(old_tiles[key] == new_tiles[key] for key in shared), (path, "tile geometry")
    report[path.relative_to(before).as_posix()] = {
        "status_before": geometry(old_status[0]), "status_after": geometry(new_status[0]),
        "shared_theme_status_height_change": delta,
        "header_tabs_toolbars_sidebar_and_tiles": "pass",
    }
assert report, "No capture pairs found"
(after / "equivalence.json").write_text(json.dumps(report, indent=2) + "\n")
print(f"Compared {len(report)} native capture pairs; shared statusbar differences recorded separately")
