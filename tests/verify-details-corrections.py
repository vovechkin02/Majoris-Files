"""Verify native section positions, Pango ink bounds, and GTK input modality."""
import json
from pathlib import Path
import re
import hashlib

root=Path(__file__).resolve().parents[1]
art=root/'artifacts/details-corrections'
variants=('light','dark','light-2x','dark-2x','light-large-text','dark-large-text')

def walk(node,parents=()):
    yield node,parents
    for child in node['children']:
        yield from walk(child,parents+(node,))

def load(variant,name):
    return json.loads((art/variant/(name+'.json')).read_text())

def family(tree,name):
    return next(n for n,_ in walk(tree) if name in n['classes'])

def column_metrics(tree):
    column=family(tree,'majoris-data-column')
    assert not any('majoris-data-list' in n['classes'] for n,_ in walk(column))
    header=next(c for c in column['children'] if any(x['node']=='button' for x in c['children']))
    rows=[n for n,_ in walk(column) if n['node']=='row' and any(c['node']=='cell' for c in n['children'])]
    assert rows
    top=min(n['absolute_y'] for n in rows)
    headings=[n for n,_ in walk(column) if 'heading' in n['classes']]
    return {'header_top':header['absolute_y'],'header_height':header['bounds_height'],
            'header_bottom':header['absolute_y']+header['bounds_height'],
            'first_row_top':top,'gap':top-header['absolute_y']-header['bounds_height'],
            'row_heights':sorted({n['allocated_height'] for n in rows}),
            'section_heading_labels':[n.get('text') for n in headings]}

gaps={};metrics={};focus={}
for variant in variants:
    gaps[variant]={}
    for name,density in [('details-ungrouped','standard'),('details-compact','compact'),
                         ('details-regrouped-none','standard'),('details-restored-none','standard')]:
        data=column_metrics(load(variant,name))
        assert data['gap']==0,(variant,name,data)
        assert data['header_height']==32
        assert data['row_heights']==[32 if density=='compact' else 40]
        assert not data['section_heading_labels']
        gaps[variant][name]=data
    for name in ('details-grouped','details-restored-grouped'):
        data=column_metrics(load(variant,name));assert data['section_heading_labels'] and all(data['section_heading_labels'])
        gaps[variant][name]=data
    for name in ('gallery-ungrouped','gallery-grouped'):
        view=family(load(variant,name),'majoris-data-list')
        headings=[n.get('text') for n,_ in walk(view) if 'heading' in n['classes']]
        assert bool(headings)==(name=='gallery-grouped')
        rows=[n for n,_ in walk(view) if n['node']=='row']
        gap=min(n['absolute_y'] for n in rows)-view['absolute_y']
        if name=='gallery-ungrouped':assert gap==0,(variant,name,gap)
        gaps[variant][name]={'section_heading_labels':headings,'first_row_offset':gap}
    for name in ('grid-ungrouped','grid-grouped'):
        tree=load(variant,name)
        headings=[n.get('text') for n,_ in walk(tree) if 'heading' in n['classes']]
        assert bool(headings)==(name=='grid-grouped')
        gaps[variant][name]={'section_heading_labels':headings}
    metrics[variant]={}
    for name,density in [('details-metadata','standard'),('details-metadata-compact','compact')]:
        tree=load(variant,name);column=family(tree,'majoris-data-column');labels=[]
        for n,parents in walk(column):
            if 'majoris-data-metadata' not in n['classes']:continue
            assert 'Plus Jakarta Sans' in n['resolved_font'],(variant,n['resolved_font'])
            assert '12px' in n['font'] and not any(weight in n['font'] for weight in ('Bold','Medium'))
            top=n['layout_y']+n['ink_y'];bottom=top+n['ink_height']
            assert 0<=top<=bottom<=n['height'],(variant,n['text'],top,bottom,n['height'])
            cell=next(p for p in reversed(parents) if p['node']=='cell')
            assert cell['absolute_y']<=n['absolute_y']+top
            assert n['absolute_y']+bottom<=cell['absolute_y']+cell['bounds_height']
            assert n['height_request']==-1 and n['margin_top']==n['margin_bottom']==0
            labels.append({k:n[k] for k in ('text','font','resolved_font','font_resolution','height','baseline',
                                           'pango_baseline','rendered_baseline','layout_y','ink_y','ink_height',
                                           'logical_y','logical_height','overflow')})
            labels[-1]['parent_cell_height']=cell['bounds_height']
            labels[-1]['vertical_ink_with_layout_offset']=[top,bottom]
            labels[-1]['clipping_ancestors']=[{'node':p['node'],'overflow':p['overflow']} for p in parents if p['overflow'].endswith('HIDDEN')]
        expected={'18 bytes','24 bytes','Folder','Plain text document','Modified','Favorites','Files','Format',
                  'ABCDEFGHIJKLMNOPQRSTUVWXYZ','gjpqy','10/27/2026 02:41:48 AM','10/27/26'}
        assert expected.issubset({n['text'] for n in labels}),(variant,expected-{n['text'] for n in labels})
        assert len({n['rendered_baseline'] for n in labels})==1,(variant,'unstable metadata baseline')
        assert column_metrics(tree)['row_heights']==[32 if density=='compact' else 40]
        metrics[variant][density]=labels
    focus[variant]={}
    for mode in ('details','grid','columns','gallery'):
        focus[variant][mode]={}
        for state in ('mouse-selected','keyboard-focused','unfocused-selected'):
            tree=load(variant,mode+'-'+state)
            view=family(tree, 'majoris-data-column' if mode=='details' else 'majoris-data-grid' if mode=='grid' else 'majoris-data-list')
            nodes=[n for n,_ in walk(view)]
            selected=[n for n in nodes if n['node']=='row' and n['selected']]
            focused=[n for n in nodes if n['has_focus']]
            assert selected,(variant,mode,state,'selection missing')
            keyboard=any(n['has_focus'] and n['focus_visible'] for n in nodes)
            assert keyboard==(state=='keyboard-focused'),(variant,mode,state,'incorrect GTK modality')
            focus[variant][mode][state]={'selected_rows':len(selected),'keyboard_focus_visible':keyboard,
                                       'focused_widgets':[{'node':n['node'],'state_flags':n['state_flags']} for n in focused]}

for variant in ('light','dark'):
    data=column_metrics(load('before/'+variant,'details-ungrouped'))
    assert data['gap']==24,(variant,'baseline did not reproduce the defect',data)
    gaps['before-'+variant]=data

out=art/'geometry';out.mkdir(exist_ok=True)
for name,data in [('header-gap',gaps),('metadata-metrics',metrics),('focus-selection',focus)]:
    (out/(name+'.json')).write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n')
# Audit the actual installed CSS copies; Files supplies no competing state CSS.
audit={}
for variant in ('light','dark'):
    css=(root/'build/theme-integration-runtime'/variant/'config/gtk-4.0/gtk.css').read_text()
    rules=[rule.strip() for rule in css.split('}') if 'majoris-data-column' in rule and ':focus-within' in rule]
    audit[variant]={'css_sha256':hashlib.sha256(css.encode()).hexdigest(),
                    'unconditional_details_focus_within_rules':[rule+'}' for rule in rules]}
(out/'theme-focus-audit.json').write_text(json.dumps(audit,indent=2)+'\n')
print('All six variants: header gap 24 -> 0px; native metadata ink and input modality pass')
