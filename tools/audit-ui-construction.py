"""Enumerate toolkit construction, with explicit runtime responsibilities.

Run from any directory; --check also rejects permanent container construction.
The Markdown output is intended for review, not as a blanket migration exemption.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
pattern = re.compile(r"new\s+((?:Gtk|Adw|Majoris\.Ui)\.\w+)(?:\.\w+)?\s*\(")

def reason(path, typ, line):
    name = typ.rsplit(".", 1)[-1]
    if typ == "Gtk.Builder":
        return "Resource-backed native/final-type component or toolbar control set; loaded at construction/setup, never from a source-tree path."
    if typ == "Majoris.Ui.Toolbar":
        return "Shared Toolbar creation function initializes its theme/lifecycle contract; XML controls enter through append_control/append_widget/append_group."
    if any(word in name for word in ("Selection", "Sorter", "Filter", "ListModel", "StringList", "Bitset", "ListItemFactory")):
        return "Runtime model, selection, sort/filter predicate, or factory lifecycle; not a widget hierarchy."
    if any(word in name for word in ("EventController", "Gesture", "DragSource", "DropTarget", "Breakpoint")):
        return "Runtime input/drag controller or adaptive transition with application callbacks."
    if name in {"FileDialog", "FileLauncher", "UriLauncher", "MountOperation", "ColorDialog"}:
        return "Native asynchronous service dialog/launcher using the current file, parent, cancellation or user data."
    if name == "AlertDialog":
        return "Temporary native alert with operation-specific text/responses; permanent prompt/password/ACL/nearby layouts use XML."
    if name == "Toast":
        return "Transient native notification containing an asynchronous operation result or metadata error."
    if name == "PopoverMenu":
        return "Runtime location/selection/device/provider menu model and action ancestry; pointer arrows remain disabled."
    if name in {"GridView", "ListView"}:
        return "Virtualized view for a runtime directory column or grouped Grid slice; file-item structure comes from shared XML templates."
    if name == "ColumnViewColumn":
        return "Runtime configurable/extension column, sorter and factory; the permanent ColumnView and cell widgets are XML-defined."
    if name == "PreferencesGroup":
        return "Metadata/device/provider-dependent section: its existence and contents depend on reported backend fields. Information/identity row structures are reusable XML components."
    if name == "ExpanderRow":
        return "Runtime external-provider metadata group with arbitrary provider fields."
    if name == "SwitchRow":
        return "One native setting row per installed external extension; text, availability and state are provider data. SwitchRow is final."
    if name == "CheckButton":
        return "Single native boolean choice supplied by the portal caller; request-defined label and value, with no procedural child hierarchy."
    if name == "ActionRow" and "device-properties" in path:
        return "Tape-only refresh capability row emitted from the current device category; no permanent layout or nested widget construction."
    if name == "Button":
        if "get_parse_name" in line:
            return "Runtime filesystem completion result."
        if "crumb" in line:
            return "Runtime breadcrumb for the current path/collection; its permanent stack, scroller and container are XML-defined."
        return "Single native icon/action leaf with runtime icon, accessible name and callback; no hierarchy is assembled by this helper."
    if name == "Label":
        if '"›"' in line:
            return "Runtime breadcrumb separator, whose count follows the current location depth."
        if "row.label" in line:
            return "Virtualized runtime group heading, whose label and first-section geometry follow the grouped model."
        if "recovery?" in line:
            return "Model-driven operations/recovery section heading."
        return "Single metadata key/value label generated from decoded/provider data."
    if name == "TextView":
        return "Specialized Markdown document renderer: runtime text buffer and document-content tags. Its surrounding stack/switcher/failure presentation is XML-defined."
    if name == "Picture":
        return "Runtime decoded artwork/font paintable, not a permanent application layout."
    return "REVIEW REQUIRED"

rows = []
for source in sorted((root / "src").rglob("*.vala")):
    path = source.relative_to(root).as_posix()
    for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
        for match in pattern.finditer(line):
            typ = match[1]
            rows.append((path, number, typ, reason(path, typ, line)))

unreviewed = [row for row in rows if row[3] == "REVIEW REQUIRED"]
if "--check" in sys.argv:
    assert not unreviewed, unreviewed
    assert not any(typ in {"Gtk.Box", "Gtk.Grid", "Adw.HeaderBar", "Adw.ToolbarView", "Adw.NavigationPage"} for _, _, typ, _ in rows)
    print(f"Audited {len(rows)} toolkit construction sites; no permanent container construction remains")
else:
    print("# Runtime UI construction audit\n")
    print("Generated by `python tools/audit-ui-construction.py`. Each entry identifies the runtime responsibility at that site. Composite application widgets instantiated from XML templates are not procedural construction.\n")
    print("| Source | Toolkit type | Runtime responsibility |")
    print("| --- | --- | --- |")
    for path, number, typ, explanation in rows:
        print(f"| `{path}:{number}` | `{typ}` | {explanation} |")
