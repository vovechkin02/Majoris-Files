#!/usr/bin/env python3
"""Capture Files menu fixtures using the generated Majoris Theme, without installation."""
from pathlib import Path
import os
import subprocess
import sys
import shutil

root = Path(__file__).resolve().parents[1]
if len(sys.argv) > 1 and sys.argv[1] == '--worker':
    wm = subprocess.Popen(['openbox'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) if shutil.which('openbox') else None
    try:
        subprocess.run([str(root / 'build/menu-tests')], check=True)
    finally:
        if wm is not None:
            wm.terminate()
            wm.wait(timeout=5)
    raise SystemExit(0)
theme = Path(sys.argv[1]).resolve()
out = root / 'artifacts/menu-integration'
subprocess.run(['dbus-run-session', '--', 'xvfb-run', '-a', sys.executable,
                str(root / 'tests/menu-keyboard.py'), str(theme)],
               env=dict(os.environ, GDK_BACKEND='x11', GTK_A11Y='none'), check=True)
for name, scale, dpi in [('normal', '1', '1'), ('2x', '2', '1'), ('large-text', '1', '1.25')]:
    target = out / name
    target.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, MAJORIS_MENU_THEME=str(theme / 'theme/Majoris'),
               MAJORIS_MENU_EVIDENCE=str(target), GDK_BACKEND='x11',
               GSK_RENDERER='cairo', GTK_A11Y='none', ADW_DISABLE_PORTAL='1',
               GSETTINGS_BACKEND='memory', GDK_SCALE=scale, GDK_DPI_SCALE=dpi)
    with (target / 'native.log').open('w') as log:
        subprocess.run(['dbus-run-session', '--', 'xvfb-run', '-a', '-s',
                        '-screen 0 3200x2400x24', sys.executable, __file__, '--worker'],
                       cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
print(out)
