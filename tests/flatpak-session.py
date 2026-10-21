#!/usr/bin/python3
"""Build an isolated local Flatpak fixture from the runner's Debian GIO libraries.
No host/user Flatpak remotes, applications, Samba or firewall settings are changed.
"""
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

privileged = '--privileged-namespace' in sys.argv
fixture_uid = int(os.environ.get('MAJORIS_TEST_UID', os.getuid()))
def drop_privileges():
    if privileged:
        os.setgroups([]); os.setgid(fixture_uid); os.setuid(fixture_uid)


def run(args, env, **kwargs):
    if privileged:
        kwargs['preexec_fn'] = drop_privileges
    return subprocess.run(args, env=env, check=True, text=True, **kwargs)


root = pathlib.Path(tempfile.mkdtemp(prefix='majoris-flatpak-'))
if privileged:
    if os.geteuid() != 0 or os.readlink('/proc/self/ns/mnt') == os.readlink('/proc/1/ns/mnt'):
        raise RuntimeError('Privileged fixtures require a separate private mount namespace')
    os.chown(root, fixture_uid, fixture_uid)
runtime, app, repo = root / 'runtime-build', root / 'app-build', root / 'repo'
env = dict(os.environ, XDG_DATA_HOME=str(root / 'data'), XDG_CONFIG_HOME=str(root / 'config'),
           XDG_CACHE_HOME=str(root / 'cache'), XDG_RUNTIME_DIR=str(root / 'run'),
           XDG_CURRENT_DESKTOP='Majoris', XDG_SESSION_TYPE='x11', GSK_RENDERER='cairo', GSETTINGS_BACKEND='memory')
env['HOME'] = str(root / 'home')
(root / 'home').mkdir(mode=0o700)
(root / 'run').mkdir(mode=0o700)
if privileged:
    os.chown(root / 'run', fixture_uid, fixture_uid)
    os.chown(root / 'home', fixture_uid, fixture_uid)
(runtime / 'usr').mkdir(parents=True)
(runtime / 'files').mkdir()
(runtime / 'export').mkdir()
(runtime / 'var').mkdir()
(app / 'files/bin').mkdir(parents=True)
(app / 'export').mkdir()
(app / 'var').mkdir()
arch = subprocess.check_output(['flatpak', '--default-arch'], text=True).strip()
try:
    client, host = map(lambda value: pathlib.Path(value).resolve(), sys.argv[1:3])
    shutil.copy2(client, app / 'files/bin/portal-client')
    gtk_client = client.with_name('gtk-portal-client')
    shutil.copy2(gtk_client, app / 'files/bin/gtk-portal-client')
    dependencies = subprocess.check_output(['ldd', str(client)], text=True) + subprocess.check_output(['ldd', str(gtk_client)], text=True)
    for library in set(re.findall(r'(/[^\s()]+)', dependencies)):
        source = pathlib.Path(library)
        target = runtime / 'usr' / str(source).removeprefix('/usr/').removeprefix('/')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source.resolve(), target)
    # Flatpak exposes /lib as /usr/lib, and the ELF interpreter via /lib64.
    loader = pathlib.Path('/lib64/ld-linux-x86-64.so.2')
    if loader.exists():
        target = runtime / 'usr/lib64/ld-linux-x86-64.so.2'
        target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(loader.resolve(), target)
    ldconfig = pathlib.Path('/sbin/ldconfig')
    if ldconfig.exists():
        target = runtime / 'usr/bin/ldconfig'; target.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(ldconfig.resolve(), target)
    for directory in ['share/glib-2.0/schemas', 'share/fonts/truetype/dejavu', 'share/fontconfig', 'etc/fonts']:
        source = pathlib.Path('/usr') / directory
        if directory == 'etc/fonts':
            source = pathlib.Path('/etc/fonts')
        if source.exists():
            shutil.copytree(source, runtime / 'usr' / directory, symlinks=False, dirs_exist_ok=True)
    (runtime / 'metadata').write_text(f'[Runtime]\nname=com.majoris.PortalRuntime\nruntime=com.majoris.PortalRuntime/{arch}/1\nsdk=com.majoris.PortalRuntime/{arch}/1\n')
    # Xvfb on WSL exposes an abstract Unix socket; sharing the network namespace
    # permits that socket without granting any additional filesystem access.
    (app / 'metadata').write_text(f'[Application]\nname=com.majoris.PortalTest\nruntime=com.majoris.PortalRuntime/{arch}/1\nsdk=com.majoris.PortalRuntime/{arch}/1\ncommand=portal-client\n[Context]\nsockets=x11;\nshared=ipc;network;\n[Session Bus Policy]\norg.freedesktop.portal.Desktop=talk\n')
    run(['flatpak', 'build-export', '--runtime', str(repo), str(runtime), '1'], env, stdout=subprocess.DEVNULL)
    run(['flatpak', 'build-export', str(repo), str(app), '1'], env, stdout=subprocess.DEVNULL)
    run(['flatpak', 'remote-add', '--user', '--no-gpg-verify', 'majoris-fixture', repo.as_uri()], env)
    for reference in ['com.majoris.PortalRuntime', 'com.majoris.PortalTest']:
        run(['flatpak', 'install', '--user', '-y', '--no-deps', '--no-related', 'majoris-fixture', reference + '//1'], env, stdout=subprocess.DEVNULL)
    portals = root / 'config/xdg-desktop-portal'; portals.mkdir(parents=True)
    (portals / 'portals.conf').write_text('[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.FileChooser=majoris\n')
    data = root / 'share/xdg-desktop-portal/portals'; data.mkdir(parents=True)
    source = pathlib.Path(__file__).resolve().parents[1] / 'data/majoris.portal'
    shutil.copy2(source, data / 'majoris.portal')
    env['XDG_DATA_DIRS'] = str(root / 'share') + ':/usr/local/share:/usr/share'
    # The document URI and Flatpak's mount target must agree on /run/user/UID.
    # Use a mount namespace instead of touching the developer's real runtime dir.
    runtime_path = '/run/user/' + str(fixture_uid)
    if privileged:
        # /run/user is replaced only in this private mount namespace, including
        # when the headless runner has no real login runtime directory.
        subprocess.run(['mount', '-t', 'tmpfs', '-o', 'mode=0755,size=64m', 'majoris-fixture-runtime', '/run/user'], check=True)
        pathlib.Path(runtime_path).mkdir(mode=0o700)
        os.chown(runtime_path, fixture_uid, fixture_uid)
        subprocess.run(['mount', '--bind', str(root / 'run'), runtime_path], check=True)
        try:
            env['XDG_RUNTIME_DIR'] = runtime_path
            run(['xvfb-run', '-a', 'dbus-run-session', '--', str(host), str(root)], env, timeout=180)
        finally:
            subprocess.run(['umount', '-l', runtime_path + '/doc'], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(['umount', runtime_path], check=True)
            subprocess.run(['umount', '-l', '/run/user'], check=True)
    else:
        run(['bwrap', '--bind', '/', '/', '--dev-bind', '/dev', '/dev', '--proc', '/proc', '--bind', str(root / 'run'), runtime_path,
             '--unshare-pid', '--die-with-parent', '--setenv', 'XDG_RUNTIME_DIR', runtime_path,
             '--', 'xvfb-run', '-a', 'dbus-run-session', '--', str(host), str(root)], env, timeout=180)
finally:
    # FUSE may need a moment to detach when the private D-Bus session exits.
    if not os.path.ismount(root / 'run/doc'):
        shutil.rmtree(root, ignore_errors=True)
