"""Measure the untouched native sidebar selection stripe (requires Pillow)."""
from pathlib import Path
import json
from PIL import Image
root=Path(__file__).resolve().parents[1]/'artifacts/theme-integration'
report={}
for variant in ('light','dark'):
    image=Image.open(root/variant/'sidebar.png').convert('RGB')
    colors=((99,102,241),(129,140,248))
    pixels=[(x,y) for y in range(180,240) for x in range(0,20) if image.getpixel((x,y)) in colors]
    assert pixels,variant
    width=max(x for x,y in pixels)-min(x for x,y in pixels)+1
    height=max(y for x,y in pixels)-min(y for x,y in pixels)+1
    # WidgetPaintable rasterizes the fractional CSS edge with partial pixels.
    assert width in (1,2) and height in (15,16),(variant,width,height)
    report[variant]={'css_target_width':2,'css_target_height':16,
                     'fully_opaque_pixel_width':width,'fully_opaque_pixel_height':height,
                     'note':'Partial edge pixels are excluded from this exact-colour count.'}
(root/'geometry/selection-stripe.json').write_text(json.dumps(report,indent=2)+'\n')
print('Native sidebar stripe is visible in both themes; raster edge coverage recorded')
