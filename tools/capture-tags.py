#!/usr/bin/env python3
"""Capture native Tags interfaces with generated Majoris-Theme CSS, without installation."""
from pathlib import Path
import os
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
if len(sys.argv) > 1 and sys.argv[1] == '--worker':
    wm = subprocess.Popen(['openbox'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) if shutil.which('openbox') else None
    compositor = subprocess.Popen(['xcompmgr', '-n'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) if shutil.which('xcompmgr') else None
    try:
        subprocess.run([str(root / 'build/tag-ui-tests')], check=True)
    finally:
        if compositor is not None:
            compositor.terminate()
            compositor.wait(timeout=5)
        if wm is not None:
            wm.terminate()
            wm.wait(timeout=5)
    raise SystemExit(0)
theme = Path(sys.argv[1]).resolve() / 'theme/Majoris'
output = root / 'artifacts/tags'
for name, scale, dpi in [('normal', '1', '1'), ('2x', '2', '1'), ('large-text', '1', '1.25')]:
    if name not in os.environ.get('MAJORIS_TAG_CAPTURE_VARIANTS', 'normal,2x,large-text').split(','):
        continue
    target = output / name
    target.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MAJORIS_TAG_THEME=str(theme), MAJORIS_TAG_EVIDENCE=str(target),
               GDK_BACKEND='x11', GSK_RENDERER='cairo', GSETTINGS_BACKEND='memory',
               GTK_A11Y='none', ADW_DISABLE_PORTAL='1', GDK_SCALE=scale, GDK_DPI_SCALE=dpi)
    with (target / 'native.log').open('w') as log:
        subprocess.run(['dbus-run-session', '--', 'xvfb-run', '-a', '-s', '-screen 0 3200x2400x24',
                        sys.executable, __file__, '--worker'], env=env, cwd=root,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
print(output)
