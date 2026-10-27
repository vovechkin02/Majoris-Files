"""Validate border-box allocations from the actual Files widget trees."""
import json
from pathlib import Path

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
