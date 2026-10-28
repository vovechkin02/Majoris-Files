"""Summarise realised, theme-owned toolbar geometry from native captures."""
from pathlib import Path
import json

root=Path(__file__).resolve().parents[1]
output=root/'artifacts/toolbar-integration'
def nodes(value):
    yield value
    for child in value.get('children',[]): yield from nodes(child)
rows=[]
for directory in sorted(output.iterdir()):
    if not directory.is_dir(): continue
    for name in ('standard','open-chooser','save-chooser','image-preview','animation-preview','pdf-preview'):
        path=directory/(name+'.json')
        if not path.exists(): continue
        tree=list(nodes(json.loads(path.read_text())))
        bars=[n for n in tree if 'majoris-toolbar' in n.get('classes',[])]
        controls=[n for n in tree if 'majoris-toolbar-control' in n.get('classes',[]) or 'majoris-toolbar-field' in n.get('classes',[]) or 'majoris-toolbar-select' in n.get('classes',[])]
        heights=sorted({n['allocated_height'] for n in bars})
        control_heights=sorted({n['allocated_height'] for n in controls})
        large=directory.name.endswith('large-text')
        expected=28 if name.endswith('preview') else 32
        assert bars and controls,(directory,name)
        assert all(h>=40 if large else h==40 for h in heights),(directory,name,heights)
        assert all(h>=expected if large else h==expected for h in control_heights),(directory,name,control_heights)
        for node in tree:
            if 'majoris-location-bar' in node.get('classes',[]):
                assert node['allocated_height']==32,(directory,name,'location shell',node['allocated_height'])
            if 'majoris-location-crumb' in node.get('classes',[]):
                assert node['allocated_height']==26,(directory,name,'breadcrumb',node['allocated_height'])
            if 'majoris-toolbar-group'  in node.get('classes',[]):
                children=node.get('children',[])
                for before,after in zip(children,children[1:]):
                    gap=round(after['absolute_x']-(before['absolute_x']+before['bounds_width']))
                    assert gap==4,(directory,name,'group gap',gap)
            if node.get('node')=='image' and any('majoris-toolbar-control' in control.get('classes',[]) and node in list(nodes(control)) for control in controls):
                assert node['icon_size']==16 or (node['allocated_width']==16 and node['allocated_height']==16),(directory,name,'artwork',node)
        if large and name in ('standard','pdf-preview'):
            assert max(heights)>40,(directory,name,'large text must grow naturally',heights)
        for node in tree:
            if node.get('node') == 'label' and (node.get('text','').startswith('New Folder') or 'majoris-toolbar-metadata' in node.get('classes',[])):
                assert node['logical_height'] <= node['allocated_height'],(directory,name,node)
                assert node['ink_height'] <= node['allocated_height'],(directory,name,node)
        rows.append((directory.name,name,heights,control_heights))
report='# Native Toolbar geometry\n\nLogical GTK allocations; scale 2 uses twice the physical pixels.\n\n| Appearance | Strip | Toolbar height | Controls |\n|---|---|---|---|\n'
for palette,name,heights,controls in rows:
    report+=f'| {palette} | {name} | {heights} | {controls} |\n'
(output/'geometry.md').write_text(report)
print(report)
