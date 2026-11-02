"""Validate border-box allocations from the actual Files widget trees."""
import json
from pathlib import Path

def verify_toolbars(directory):
    def walk(node):
        yield node
        for child in node.get('children', []):
            yield from walk(child)
    reports = {}
    for variant in sorted(directory.iterdir()):
        if not variant.is_dir(): continue
        rows = {}
        for path in sorted(variant.glob('*.json')):
            if not (path.stem.startswith(('files-', 'open-chooser-', 'save-chooser-')) or path.stem == 'recovery-revealed'): continue
            assert path.with_suffix('.png').is_file(), path
            tree = json.loads(path.read_text())
            nodes = list(walk(tree))
            bars = [n for n in nodes if 'majoris-toolbar' in n['classes']]
            assert len(bars) == 2, path
            large = variant.name.endswith('large-text')
            assert all(b['allocated_height'] >= 40 if large else b['allocated_height'] == 40 for b in bars), path
            controls = [n for n in nodes if any(c in n['classes'] for c in ('majoris-toolbar-control', 'majoris-toolbar-field', 'majoris-toolbar-select'))]
            assert controls and all(c['allocated_height'] >= 32 if large else c['allocated_height'] == 32 for c in controls), path
            gaps = []
            for bar in bars:
                children = bar['children']
                assert round(children[0]['absolute_x'] - bar['absolute_x']) == 8, path
                last = children[-1]
                assert round(bar['absolute_x'] + bar['bounds_width'] - last['absolute_x'] - last['bounds_width']) == 8, path
                previous = None
                for child in bar['children']:
                    assert child['widget_type'] != 'MajorisUiToolbarGroup', path
                    assert child['node'] != 'separator', path
                    assert child['margin_start'] == child['margin_end'] == 0, path
                    if 'majoris-toolbar-spacer' in child['classes']:
                        previous = None
                        continue
                    if previous:
                        gap = round(child['absolute_x'] - previous['absolute_x'] - previous['bounds_width'])
                        assert gap == 4, (path, gap)
                        gaps.append(gap)
                    previous = child
                    if 'majoris-toolbar-segmented' in child['classes']:
                        for a, b in zip(child['children'], child['children'][1:]):
                            assert round(b['absolute_x'] - a['absolute_x'] - a['bounds_width']) == 2, path
            def vertical(a, b):
                gap = round(b['absolute_y'] - a['absolute_y'] - a['bounds_height'])
                assert gap == 0, (path, 'vertical gap', gap)
                return gap
            vertical(bars[0], bars[1])
            browser = next(n for n in nodes if n['widget_type'] == 'MajorisFilesBrowser')
            surfaces = [n for n in browser['children'] if n['bounds_height'] > 0]
            for a, b in zip(surfaces, surfaces[1:]): vertical(a, b)
            tabs = next((n for n in nodes if 'majoris-document-tabs' in n['classes']), None)
            if tabs:
                assert tabs['allocated_height'] == 40, path
                if path.stem == 'recovery-revealed':
                    banner = next(n for n in nodes if n['widget_type'] == 'AdwBanner')
                    vertical(tabs, banner); vertical(banner, bars[0])
                else: vertical(tabs, bars[0])
            rows[path.stem] = {'adjacent_control_gaps': gaps, 'toolbar_heights': [b['allocated_height'] for b in bars],
                               'tab_height': tabs['allocated_height'] if tabs else None, 'vertical_gap': 0}
        expected = {f'{mode}-{width}' for mode in ('files', 'open-chooser', 'save-chooser') for width in (480, 650, 800, 1100)} | {'recovery-revealed'}
        assert set(rows) == expected, (variant, expected - set(rows))
        assert 'Native toolbar actions, composites, responsive routing, chooser, preview and mutation checks passed' in (variant / 'native.log').read_text(), variant
        reports[variant.name] = rows
    assert set(reports) == {'light', 'dark', 'light-2x', 'dark-2x', 'light-large-text', 'dark-large-text'}, set(reports)
    (directory / 'allocations.json').write_text(json.dumps(reports, indent=2) + '\n')
    print('Native toolbar control and document composition geometry passed:', ', '.join(reports))

import sys
if len(sys.argv) > 1 and sys.argv[1] == '--toolbars':
    verify_toolbars(Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parents[1] / 'artifacts/toolbar-composition')
    raise SystemExit(0)

root=Path(__file__).resolve().parents[1]/'artifacts/theme-integration'
def walk(node):
    yield node
    for child in node.get('children',[]):
        yield from walk(child)
def component(tree,name):
    return next(n for n in walk(tree) if name in n['classes'])
def load(variant,name):
    return json.loads((root/variant/(name+'.json')).read_text())
def size(node):
    return [node['allocated_width'],node['allocated_height']]
reports={}
for variant in ('light','dark','light-2x','dark-2x','light-large-text','dark-large-text'):
    data={}
    for density in ('standard','compact'):
        tree=load(variant,'grid-'+density)
        tile=component(tree,'majoris-data-tile')
        artwork=component(tile,'majoris-data-artwork')
        expected=[128,160] if density=='standard' else [96,128]
        assert size(tile)[0]==expected[0] and (size(tile)[1]>=expected[1] if 'large-text' in variant else size(tile)[1]==expected[1]),(variant,density,size(tile))
        assert size(artwork)==([96,96] if density=='standard' else [64,64])
        data['grid-'+density]={'tile':size(tile),'artwork':size(artwork)}
        column=component(load(variant,'details-'+density),'majoris-data-column')
        rows=[n for n in walk(column) if n['node']=='row' and any(c['node']=='cell' for c in n['children'])]
        assert rows and {n['allocated_height'] for n in rows}=={40 if density=='standard' else 32}
        # ColumnView headers have the CSS node name "header" on some GTK versions,
        # and a GtkListItemWidget title node on GTK 4.18; find Name's ancestor.
        def name_header(node):
            if node['node']=='button' and any(n.get('text')=='Name' for n in walk(node)):return node
            for child in node['children']:
                found=name_header(child)
                if found:return found
        header=name_header(column)
        assert header and header['allocated_height']==31,(variant,header)
        data['details-'+density]={'row':rows[0]['allocated_height'],'header_button':31,'header_with_bottom_border':32}
        for mode in ('columns','gallery'):
            view=component(load(variant,mode+('-compact' if density=='compact' else '')),'majoris-data-list')
            rows=[n for n in walk(view) if n['node']=='row']
            assert rows and {n['allocated_height'] for n in rows}=={40 if density=='standard' else 32}
            data[mode+'-'+density]={'row':rows[0]['allocated_height']}
    sidebar=component(load(variant,'sidebar'),'navigation-sidebar')
    rows=[n for n in walk(sidebar) if n['node']=='row']
    assert rows and {n['height'] for n in rows}=={32}
    assert {n['allocated_height'] for n in rows}=={36}
    assert {n['icon_size'] for n in walk(sidebar) if n['node']=='image'}=={16}
    for row in rows:
        box=row['children'][0]
        icon,label=box['children'][:2]
        assert label['x']-icon['x']-icon['allocated_width']==8
    headings=[n for n in walk(sidebar) if 'majoris-sidebar-heading' in n['classes']]
    assert headings and all('majoris-sidebar-heading-first' not in n['classes'] for n in headings)
    assert all(n['allocated_height']-n['height']==24 for n in headings)
    data['sidebar']={'painted_row':32,'row_with_gap':36,'icon':16,'icon_gap':8,
                     'heading_top':16,'heading_bottom':8}
    # Pango logical allocation includes ascenders/descenders. Test visible labels,
    # including sidebar headings, filenames, toolbar labels and document tabs.
    labels=[n for n in walk(load(variant,'details-standard')) if n['node']=='label' and n.get('text')]
    failures=[n['text'] for n in labels if n['logical_height']>n['height'] or n['ink_y']<0 or n['ink_y']+n['ink_height']>n['height']]
    assert not failures,(variant,'glyph clipping',failures)
    data['glyph_labels_checked']=len(labels)
    reports[variant]=data
out=root/'geometry';out.mkdir(exist_ok=True)
(out/'allocations.json').write_text(json.dumps(reports,indent=2)+'\n')
for family in ('sidebar','grid','details','list'):
    keys=('columns','gallery') if family=='list' else (family,)
    (out/(family+'.json')).write_text(json.dumps({v:{k:x for k,x in data.items() if any(k.startswith(s) for s in keys)} for v,data in reports.items()},indent=2)+'\n')
print('Native Files geometry and glyph allocation checks passed for all six variants')
