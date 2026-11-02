"""Give the real GTK action test a private home, Trash and session bus."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
with tempfile.TemporaryDirectory(prefix='majoris-sidebar-session-') as directory:
    home=Path(directory)
    env=dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home/'config'),
             XDG_DATA_HOME=str(home/'data'), XDG_CACHE_HOME=str(home/'cache'),
             GTK_A11Y='none', GSETTINGS_BACKEND='memory', GVFS_DISABLE_FUSE='1')
    for name in ('config','data','cache','data/Trash/files','data/Trash/info'):
        (home/name).mkdir(parents=True,exist_ok=True)
    (home/'data/Trash/files/sidebar-fixture').write_text('isolated test trash; never delete through the UI')
    (home/'data/Trash/info/sidebar-fixture.trashinfo').write_text('[Trash Info]\nPath=/tmp/majoris-sidebar-trash-fixture\nDeletionDate=2026-11-02T00:00:00\n')
    result=subprocess.run(['dbus-run-session','--','xvfb-run','-a',*sys.argv[1:]],env=env)
    raise SystemExit(result.returncode)
