"""Render the operation UI state fixtures using the installed Majoris theme.
These are presentation fixtures; real transfer behaviour is tested separately.
Run under Linux/WSL: python3 tools/capture-operation-progress.py ../Majoris-Theme
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
theme = Path(sys.argv[1]).resolve() / 'theme/Majoris/gtk-4.0'
for palette in ('light', 'dark'):
    output = root / 'artifacts/operation-progress' / palette
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='majoris-progress-visual-') as temporary:
        config = Path(temporary) / 'config'
        gtk = config / 'gtk-4.0'
        shutil.copytree(theme, gtk)
        if palette == 'dark':
            shutil.copyfile(gtk / 'gtk-dark.css', gtk / 'gtk.css')
        captures = Path(temporary) / 'captures'
        captures.mkdir()
        env = dict(os.environ, XDG_CONFIG_HOME=str(config), GDK_BACKEND='x11',
                   GSK_RENDERER='cairo', GTK_A11Y='none', GSETTINGS_BACKEND='memory',
                   ADW_DISABLE_PORTAL='1', MAJORIS_VISUAL_DARK='1' if palette == 'dark' else '0')
        with (output / 'capture.log').open('w') as log:
            subprocess.run(['dbus-run-session', '--', 'xvfb-run', '-a', '-s',
                            '-screen 0 1280x1024x24', str(root / 'build/operation-progress-ui'),
                            str(captures)], cwd=root, env=env, stdout=log,
                           stderr=subprocess.STDOUT, check=True)
        shutil.copytree(captures, output, dirs_exist_ok=True)
        print(f'{palette}: {len(list(output.glob("*.png")))} captures')
