"""Capture and measure Files against an installed GTK override from the supplied Theme.
Usage: python3 tools/capture-toolbars.py /path/to/Majoris-Theme
No application CSS, shared libraries or fonts are copied into Files sources.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
if len(sys.argv) > 1 and sys.argv[1] == '--worker':
    wm = subprocess.Popen(['openbox'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) if shutil.which('openbox') else None
    try:
        subprocess.run([str(root / 'build/toolbar-tests'), sys.argv[2]], check=True)
    finally:
        if wm is not None:
            wm.terminate(); wm.wait(timeout=5)
    raise SystemExit(0)
theme = Path(sys.argv[1]).resolve()
runtime = Path(tempfile.mkdtemp(prefix='majoris-toolbar-capture-'))
output = root / 'artifacts/toolbar-integration'
for palette in ('light', 'dark'):
    config = runtime / palette / 'config'
    gtk = config / 'gtk-4.0'
    shutil.copytree(theme / 'theme/Majoris/gtk-4.0', gtk, dirs_exist_ok=True)
    if palette == 'dark':
        shutil.copyfile(gtk / 'gtk-dark.css', gtk / 'gtk.css')
    fonts = runtime / palette / 'data/fonts'
    fonts.mkdir(parents=True, exist_ok=True)
    listing = subprocess.check_output(['fc-list', '-f', '%{file}\t%{family}\n'], text=True)
    for line in listing.splitlines():
        name, family = line.split('\t', 1)
        if 'Plus Jakarta Sans' in family:
            shutil.copyfile(name, fonts / Path(name).name)
    aliases = config / 'fontconfig/conf.d'
    aliases.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(theme / 'fonts/fontconfig/65-majoris-fonts.conf', aliases / '65-majoris-fonts.conf')
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(fonts.parent),
               GDK_BACKEND='x11', GSK_RENDERER='cairo', GSETTINGS_BACKEND='memory',
               ADW_DISABLE_PORTAL='1', MAJORIS_TOOLBAR_GEOMETRY='1',
               MAJORIS_VISUAL_DARK='1' if palette == 'dark' else '0')
    subprocess.run(['fc-cache', '-f', str(fonts)], env=env, check=True)
    for suffix, scale, dpi in (('', '1', '1'), ('-2x', '2', '1'), ('-large-text', '1', '2')):
        target = output / (palette + suffix)
        target.mkdir(parents=True, exist_ok=True)
        runenv = dict(env, GDK_SCALE=scale, GDK_DPI_SCALE=dpi,
                      MAJORIS_TOOLBAR_LARGE_TEXT='1' if dpi != '1' else '0')
        (target / 'font-resolution.txt').write_text(subprocess.check_output(
            ['fc-match', '-f', '%{family}\n%{file}\n', 'Plus Jakarta Sans'], env=runenv, text=True))
        with (target / 'native.log').open('w') as log:
            subprocess.run(['dbus-run-session', '--', 'xvfb-run', '-a', '-s', '-screen 0 3200x2400x24',
                            sys.executable, __file__, '--worker', str(target)],
                           cwd=root, env=runenv, stdout=log, stderr=subprocess.STDOUT, check=True)
