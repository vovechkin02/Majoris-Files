"""Capture native Files evidence with an isolated, installed GTK4 user override.
Run under Linux: python3 tools/capture-theme-integration.py /path/to/Majoris-Theme
The supplied theme is read only. No source-tree CSS is loaded by Files.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
theme = Path(sys.argv[1]).resolve()
out = Path(os.environ.get('MAJORIS_CAPTURE_OUTPUT', root / 'artifacts/theme-integration'))
binary = Path(os.environ.get('MAJORIS_CAPTURE_BINARY', root / 'build/theme-integration'))
runtime = root / 'build/theme-integration-runtime'
for variant in ('light', 'dark'):
    config = runtime / variant / 'config'
    gtk = config / 'gtk-4.0'
    shutil.copytree(theme / 'theme/Majoris/gtk-4.0', gtk, dirs_exist_ok=True)
    if variant == 'dark':
        shutil.copyfile(gtk / 'gtk-dark.css', gtk / 'gtk.css')
    fonts = runtime / variant / 'data/fonts'
    fonts.mkdir(parents=True, exist_ok=True)
    if (theme / 'fonts/PlusJakartaSans').is_dir():
        shutil.copytree(theme / 'fonts/PlusJakartaSans', fonts / 'PlusJakartaSans', dirs_exist_ok=True)
    else:
        # XDG_DATA_HOME isolation hides the user's fonts. Copy the already
        # installed licensed font files when the theme does not bundle them.
        installed = subprocess.check_output(['fc-list', '-f', '%{file}\t%{family}\n'], text=True)
        for line in installed.splitlines():
            filename, family = line.split('\t', 1)
            if 'Plus Jakarta Sans' in family:
                shutil.copyfile(filename, fonts / Path(filename).name)
    aliases = config / 'fontconfig/conf.d'
    aliases.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(theme / 'fonts/fontconfig/65-majoris-fonts.conf', aliases / '65-majoris-fonts.conf')
    env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(fonts.parent),
               GDK_BACKEND='x11', GSK_RENDERER='cairo', GSETTINGS_BACKEND='memory',
               MAJORIS_VISUAL_DARK='1' if variant == 'dark' else '0')
    subprocess.run(['fc-cache', '-f', str(fonts)], env=env, check=True)
    matrix = [('', '1', None)] if os.environ.get('MAJORIS_CAPTURE_QUICK') else [('', '1', None), ('-2x', '2', None), ('-large-text', '1', 'Plus Jakarta Sans 14')]
    for suffix, scale, font in matrix:
        runenv = dict(env, GDK_SCALE=scale)
        settings = gtk / 'settings.ini'
        settings.write_text('[Settings]\n' + (f'gtk-font-name={font}\n' if font else ''))
        target = out / (variant + suffix)
        target.mkdir(parents=True, exist_ok=True)
        (target / 'font-resolution.txt').write_text(subprocess.check_output(['fc-match', '-f', '%{family}\n%{file}\n', 'Plus Jakarta Sans'], env=runenv, text=True))
        with (target / 'native.log').open('w') as log:
            subprocess.run(['dbus-run-session', '--', 'xvfb-run', '-a', '-s', '-screen 0 2560x2048x24',
                            str(binary), str(target)],
                           cwd=root, env=runenv, stdout=log, stderr=subprocess.STDOUT, check=True)
