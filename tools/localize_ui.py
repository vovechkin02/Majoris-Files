"""One-time migration of literal widget labels to the project gettext domain."""
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
literal = r'("(?:[^"\\]|\\.)*")'
patterns = [
    r'(\.(?:title|subtitle|tooltip_text|description|placeholder_text|label)\s*=\s*)' + literal,
    r'(\bnew\s+(?:Gtk\.Label|Gtk\.Button\.with_label|Gtk\.CheckButton\.with_label|Adw\.AlertDialog)\s*\(\s*)' + literal,
    r'(\btitle:\s*)' + literal,
    r'(\b(?:Browser\.)?button\(\s*"[^"\n]+",\s*)' + literal,
    r'(\bDialogs\.error\([^,\n]+,\s*)' + literal,
    r'(\.add_response\(\s*"[^"\n]+",\s*)' + literal,
]
for source in sorted((root / 'src').rglob('*.vala')):
    text = source.read_text(encoding='utf-8')
    updated = text
    for pattern in patterns:
        updated = re.sub(pattern, lambda match: match[1] + (match[2] if match[2] == '""' else '_(' + match[2] + ')'), updated)
    updated = updated.replace('_("")', '""')
    if updated != text:
        source.write_text(updated, encoding='utf-8')
(root / 'po' / 'POTFILES').write_text(''.join(str(path.relative_to(root)).replace('\\', '/') + '\n' for path in sorted((root / 'src').rglob('*.vala'))), encoding='utf-8')
