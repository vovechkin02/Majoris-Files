"""Verify the packaged executable uses the system Majoris UI library and opens a window.
Run after tools/build-debian.py. Does not install Files or register desktop services.
"""
from pathlib import Path
import os
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time

root=Path(__file__).resolve().parents[1]
if len(sys.argv)>1 and sys.argv[1]=='--worker':
    binary=Path(sys.argv[2]);isolated=Path(sys.argv[3]);folder=isolated/'Selected';folder.mkdir(parents=True)
    environment=dict(os.environ,HOME=str(isolated),XDG_CONFIG_HOME=str(isolated/'config'),
        XDG_DATA_HOME=str(isolated/'data'),XDG_CACHE_HOME=str(isolated/'cache'),GDK_BACKEND='x11',
        GSK_RENDERER='cairo',GSETTINGS_BACKEND='memory')
    for key in ('LD_LIBRARY_PATH','PKG_CONFIG_PATH','LD_PRELOAD','MAJORIS_THEME_ROOT'):
        environment.pop(key,None)
    process=subprocess.Popen([str(binary),str(folder)],env=environment,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        deadline=time.monotonic()+10
        database=isolated/'data/majoris-files/metadata.db'
        while time.monotonic()<deadline:
            assert process.poll() is None,process.communicate()
            try:
                with sqlite3.connect(database,timeout=.1) as db:
                    state=dict(db.execute('SELECT key,value FROM state'))
                if folder.as_uri() in state.get('session-last',''):break
            except sqlite3.Error:pass
            time.sleep(.05)
        else:raise AssertionError('Packaged application did not create and record its window')
        print('Packaged Files opened its requested folder with normal system library resolution.')
    finally:
        if process.poll() is None:
            process.send_signal(signal.SIGTERM);process.communicate(timeout=5)
    raise SystemExit(0)

package=root/'build/majoris-files_0.1.0-1_amd64.deb'
depends=subprocess.check_output(['dpkg-deb','-f',str(package),'Depends'],text=True)
assert 'majoris-ui-gtk4 (>= 0.1.0)' in depends,depends
print('Package Depends:',depends.strip(),flush=True)
with tempfile.TemporaryDirectory(prefix='majoris-toolbar-runtime-') as temporary:
    stage=Path(temporary);subprocess.run(['dpkg-deb','-x',str(package),str(stage)],check=True)
    binary=stage/'usr/bin/majoris-files'
    dynamic=subprocess.check_output(['readelf','-d',str(binary)],text=True)
    assert 'libmajoris-ui-gtk4.so.0' in dynamic
    environment=dict(os.environ);environment.pop('LD_LIBRARY_PATH',None)
    linked=subprocess.check_output(['ldd',str(binary)],env=environment,text=True)
    assert 'not found' not in linked,linked
    print(next(line.strip() for line in linked.splitlines() if 'libmajoris-ui-gtk4' in line),flush=True)
    subprocess.run(['dbus-run-session','--','xvfb-run','-a',sys.executable,__file__,'--worker',str(binary),str(stage/'home')],check=True)
