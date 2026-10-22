#!/usr/bin/python3
"""Exercise visibility policy with private Samba databases; never host smb.conf.

Pass the extracted Samba package root and the visibility-check binary. --server
requires an isolated network namespace and root; it tests real SMB on loopback.
"""
from pathlib import Path
import os
import pwd
import signal
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

tools_root, driver = map(lambda value: Path(value).resolve(), sys.argv[1:3])
server_test = '--server' in sys.argv
libexec_setup = None
if server_test:
    if os.geteuid() != 0 or os.readlink('/proc/self/ns/net') == os.readlink('/proc/1/ns/net') or os.readlink('/proc/self/ns/mnt') == os.readlink('/proc/1/ns/mnt'):
        raise RuntimeError('Server tests require root in private network and mount namespaces')
    subprocess.run(['ip', 'link', 'set', 'lo', 'up'], check=True)
    # Extracted packages retain compiled libexec paths. Supply those helpers only
    # inside this private mount namespace, never installing them on the host.
    libexec_setup=tempfile.TemporaryDirectory(prefix='majoris-samba-libexec-')
    overlay=Path(libexec_setup.name)
    (overlay/'upper').mkdir();(overlay/'work').mkdir()
    subprocess.run(['mount','-t','overlay','-o',f'lowerdir=/usr/libexec,upperdir={overlay/"upper"},workdir={overlay/"work"}','majoris-samba-libexec','/usr/libexec'],check=True)
    Path('/usr/libexec/samba').mkdir(exist_ok=True)
    subprocess.run(['mount', '--bind', str(tools_root/'usr/libexec/samba'), '/usr/libexec/samba'], check=True)
    subprocess.run(['mount', '-o', 'remount,bind,ro', '/usr/libexec/samba'], check=True)
uid = int(os.environ.get('MAJORIS_TEST_UID', os.getuid()))
account = pwd.getpwuid(uid).pw_name
environment = dict(os.environ, LD_LIBRARY_PATH=str(tools_root/'usr/lib/x86_64-linux-gnu/samba')+':'+str(tools_root/'usr/lib/x86_64-linux-gnu'))
server = None
with tempfile.TemporaryDirectory(prefix='majoris-samba-visibility-') as folder:
    root = Path(folder); root.chmod(0o755)
    for name in ['private', 'state', 'cache', 'lock', 'pid', 'usershares', 'shared']:
        (root/name).mkdir()
    (root/'shared').chmod(0o755)
    (root/'usershares').chmod(0o1770)
    if server_test:
        os.chown(root/'shared', uid, uid)
        os.chown(root/'usershares', 0, uid)
    (root/'shared/allowed.txt').write_text('SMB visibility fixture\n')
    config = root/'smb.conf'
    config.write_text(f'''[global]
workgroup = MAJORISFIXTURE
server role = standalone server
security = user
map to guest = Bad User
guest account = {account}
registry shares = yes
usershare path = {root/'usershares'}
usershare max shares = 20
usershare owner only = yes
usershare allow guests = yes
private dir = {root/'private'}
state directory = {root/'state'}
cache directory = {root/'cache'}
lock directory = {root/'lock'}
pid directory = {root/'pid'}
ncalrpc dir = {root/'ncalrpc'}
winbindd socket directory = {root/'winbindd'}
log file = {root/'smb.log'}
interfaces = 127.0.0.1
bind interfaces only = yes
smb ports = 445
load printers = no
printing = bsd
disable spoolss = yes
''')
    share = root/'usershares/fixture'
    share.write_text(f'#VERSION 2\npath={root/"shared"}\ncomment=Fixture\nusershare_acl=S-1-1-0:R\nguest_ok=y\nsharename=fixture\n')
    if server_test:
        os.chown(share, uid, uid)

    def command(program, *args, success=True):
        if program == 'smbclient':
            args = ('-U', 'fixture-guest', *args)
        result = subprocess.run([str(tools_root/'usr/bin'/program), '--configfile='+str(config), *map(str,args)], env=environment, capture_output=True, text=True, timeout=15)
        if success and result.returncode:
            raise RuntimeError(program+': '+result.stdout+result.stderr)
        return result

    def policy(action, success=True):
        result = subprocess.run([str(driver), str(root/'visibility'), str(root/'usershares'), str(config), str(tools_root/'usr/bin'), str(uid), action], env=environment, capture_output=True, text=True, timeout=20)
        if success and result.returncode:
            raise RuntimeError('Visibility '+action+': '+result.stdout+result.stderr)
        return result

    if '--check-databases' in sys.argv:
        for parameter, directory in [('private dir', 'private'), ('state directory', 'state'), ('lock directory', 'lock'), ('cache directory', 'cache')]:
            result = subprocess.run([str(tools_root/'usr/bin/testparm'), '-s', '--parameter-name='+parameter, str(config)], env=environment, capture_output=True, text=True, check=True)
            assert result.stdout.strip() == str(root/directory), result.stdout
            print(parameter+': '+result.stdout.strip())
        print('All Samba databases resolve inside the disposable fixture; no include or host config is used.')
        sys.exit(0)

    try:
        if server_test:
            console = (root/'server-console.log').open('w')
            server = subprocess.Popen([str(tools_root/'usr/sbin/smbd'), '--foreground', '--no-process-group', '--debug-stdout', '--debuglevel=2', '--configfile='+str(config)], env=environment, stdin=subprocess.PIPE, stdout=console, stderr=subprocess.STDOUT, start_new_session=True)
            for attempt in range(100):
                result = command('smbclient', '-N', '-g', '-L', '127.0.0.1', success=False)
                if result.returncode == 0:
                    break
                if server.poll() is not None:
                    raise RuntimeError('Disposable smbd exited '+str(server.returncode)+': '+result.stdout+result.stderr+'\n'+(root/'server-console.log').read_text())
                time.sleep(0.05)
            downloaded = root/'downloaded.txt'
            read = command('smbclient', '-N', '//127.0.0.1/fixture', '-c', 'get allowed.txt '+str(downloaded))
            assert downloaded.read_text() == 'SMB visibility fixture\n'
            result = command('smbclient', '-N', '-g', '-L', '127.0.0.1')
            assert 'Disk|fixture|' in result.stdout, result.stdout+result.stderr+'\n'+(root/'server-console.log').read_text()
            upload = command('smbclient', '-N', '//127.0.0.1/fixture', '-c', f'put {root/"shared/allowed.txt"} denied.txt', success=False)
            assert 'NT_STATUS_ACCESS_DENIED' in upload.stdout+upload.stderr
        policy('hide')
        hidden = command('net', 'conf', 'showshare', 'fixture').stdout
        assert 'browseable = no' in hidden
        assert 'READ' in command('sharesec', 'fixture', '--view').stdout
        if server_test:
            command('smbcontrol', str(server.pid), 'reload-config')
            listing = command('smbclient', '-N', '-g', '-L', '127.0.0.1').stdout
            assert 'Disk|fixture|' not in listing, listing
            downloaded.unlink()
            command('smbclient', '-N', '//127.0.0.1/fixture', '-c', 'get allowed.txt '+str(downloaded))
            assert downloaded.read_text() == 'SMB visibility fixture\n'
            upload = command('smbclient', '-N', '//127.0.0.1/fixture', '-c', f'put {root/"shared/allowed.txt"} denied.txt', success=False)
            assert 'NT_STATUS_ACCESS_DENIED' in upload.stdout+upload.stderr
        policy('show')
        assert 'fixture' not in command('net', 'conf', 'listshares').stdout.splitlines()
        if server_test:
            password = secrets.token_hex(20)
            identities = {}
            for user in [account, 'nobody']:
                result = subprocess.run([str(tools_root/'usr/bin/pdbedit'), '--configfile='+str(config), '-a', '-u', user, '-t'], input=password+'\n'+password+'\n', env=environment, capture_output=True, text=True, timeout=10)
                assert result.returncode == 0, result.stderr
                identity = command('pdbedit', '-u', user, '-v').stdout
                identities[user] = re.search(r'User SID:\s*(S-[0-9-]+)', identity)[1]
            updated = root/'usershares/.fixture-update'
            updated.write_text(f'#VERSION 2\npath={root/"shared"}\ncomment=Fixture\nusershare_acl={identities[account]}:F,{identities["nobody"]}:R\nguest_ok=n\nsharename=fixture\n')
            os.chown(updated, uid, uid)
            os.replace(updated, share)
            policy('hide')
            command('smbcontrol', str(server.pid), 'reload-config')

            def authenticated(user, request):
                read_fd, write_fd = os.pipe()
                os.write(write_fd, (password+'\n').encode()); os.close(write_fd)
                try:
                    return subprocess.run([str(tools_root/'usr/bin/smbclient'), '--configfile='+str(config), '-U', user, '//127.0.0.1/fixture', '-c', request], env=dict(environment, PASSWD_FD=str(read_fd)), pass_fds=(read_fd,), capture_output=True, text=True, timeout=15)
                finally:
                    os.close(read_fd)

            write = authenticated(account, f'put {root/"shared/allowed.txt"} writable.txt')
            assert (root/'shared/writable.txt').read_text() == 'SMB visibility fixture\n', write.stdout+write.stderr
            read_only = root/'read-only.txt'
            result = authenticated('nobody', f'get allowed.txt {read_only}')
            assert read_only.read_text() == 'SMB visibility fixture\n', result.stdout+result.stderr
            (root/'shared').chmod(0o777)  # Prove the share ACL, not POSIX mode alone, denies writes.
            denied = authenticated('nobody', f'put {root/"shared/allowed.txt"} forbidden.txt')
            assert 'NT_STATUS_ACCESS_DENIED' in denied.stdout+denied.stderr and not (root/'shared/forbidden.txt').exists()
            (root/'shared').chmod(0o555)
            denied = authenticated(account, f'put {root/"shared/allowed.txt"} posix-denied.txt')
            assert 'NT_STATUS_ACCESS_DENIED' in denied.stdout+denied.stderr and not (root/'shared/posix-denied.txt').exists()
            (root/'shared').chmod(0o777)
            # Edit a currently hidden eligible share, retaining registry ownership.
            updated=root/'usershares/.fixture-update'
            updated.write_text(f'#VERSION 2\npath={root/"shared"}\ncomment=Fixture\nusershare_acl={identities[account]}:F,{identities["nobody"]}:F\nguest_ok=n\nsharename=fixture\n')
            os.chown(updated,uid,uid);os.replace(updated,share);policy('hide');command('smbcontrol',str(server.pid),'reload-config')
            permitted=authenticated('nobody',f'put {root/"shared/allowed.txt"} newly-permitted.txt')
            assert (root/'shared/newly-permitted.txt').read_text()=='SMB visibility fixture\n',permitted.stdout+permitted.stderr
            print('Authenticated owner-write and separate-account read-only checks passed')
            print('Share ACL / POSIX intersection and editing an existing hidden share passed')
            remote_check=os.environ.get('MAJORIS_REMOTE_CHECK')
            if remote_check:
                (root/'shared/payload.txt').write_text('remote fixture\n')
                (root/'shared/large.bin').write_bytes(b'x'*(12*1024*1024))
                with tempfile.TemporaryDirectory(prefix='ms-') as home:
                    os.chown(home,uid,uid)
                    runtime=Path(home)/'r';runtime.mkdir(mode=0o700);os.chown(runtime,uid,uid)
                    client_env=dict(os.environ,HOME=home,USER=account,LOGNAME=account,XDG_DATA_HOME=home+'/data',XDG_CONFIG_HOME=home+'/config',XDG_CACHE_HOME=home+'/cache',XDG_DATA_DIRS='/usr/local/share:/usr/share',XDG_RUNTIME_DIR=str(runtime),MAJORIS_FIXTURE_USER=account,MAJORIS_FIXTURE_PASSWORD=password,GSK_RENDERER='cairo',GSETTINGS_BACKEND='memory')
                    client_env.pop('LD_LIBRARY_PATH',None)
                    client_env['GDK_BACKEND']='x11'
                    def drop(): os.setgroups([]);os.setgid(uid);os.setuid(uid)
                    try:
                        subprocess.run(['dbus-run-session','--','xvfb-run','-a',str(Path(remote_check).resolve()),f'smb://{account}@127.0.0.1/fixture/'],env=client_env,preexec_fn=drop,check=True,timeout=100)
                    finally:
                        # Never recursively clean a mounted remote filesystem.
                        mountpoint=str(runtime/'gvfs')
                        if any(line.split()[4]==mountpoint for line in Path('/proc/self/mountinfo').read_text().splitlines()):
                            subprocess.run(['umount','--lazy',mountpoint],check=True)
                print('PASS: real SMB chooser and remote archive acceptance')
            if os.environ.get('MAJORIS_FLATPAK_HOST') and os.environ.get('MAJORIS_FLATPAK_CLIENT'):
                portal=root/'shared/portal';portal.mkdir();os.chown(portal,uid,uid)
                (portal/'allowed.txt').write_text('allowed fixture');(portal/'another.txt').write_text('another fixture')
                portal_env=dict(os.environ,MAJORIS_REMOTE_URI=f'smb://{account}@127.0.0.1/fixture/portal/',MAJORIS_FIXTURE_USER=account,MAJORIS_FIXTURE_PASSWORD=password)
                subprocess.run(['python3','tests/flatpak-session.py',os.environ['MAJORIS_FLATPAK_CLIENT'],os.environ['MAJORIS_FLATPAK_HOST'],'--privileged-namespace'],env=portal_env,check=True,timeout=180)
                print('PASS: actual remote SMB Flatpak/document-portal acceptance')
            policy('show')
        policy('hide')
        command('net', 'conf', 'setparm', 'fixture', 'valid users', 'administrator')
        policy('refuse')
        assert 'valid users' in command('net', 'conf', 'showshare', 'fixture').stdout
        print('Samba visibility ownership, ACL preservation, visibility reset and administrator-change refusal passed'+ ('; real SMB listing/direct read/write denial passed' if server_test else ''))
    finally:
        if server:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill(); server.wait()
            # On-demand RPC workers can outlive smbd. Only signal helpers whose
            # exact configuration and network namespace belong to this fixture.
            for process in Path('/proc').glob('[0-9]*'):
                try:
                    descriptor = os.pidfd_open(int(process.name))
                    try:
                        args = (process/'cmdline').read_bytes().split(b'\0')
                        if (('--configfile='+str(config)).encode() not in args or
                            os.readlink(process/'ns/net') != os.readlink('/proc/self/ns/net') or
                            Path(os.fsdecode(args[0])).name not in {'samba-dcerpcd', 'rpcd_classic', 'rpcd_epmapper', 'rpcd_lsad', 'rpcd_winreg'}):
                            continue
                        if 'Pid:\t'+process.name+'\n' in Path('/proc/self/fdinfo/'+str(descriptor)).read_text():
                            signal.pidfd_send_signal(descriptor, signal.SIGTERM)
                    finally:
                        os.close(descriptor)
                except (OSError, ProcessLookupError):
                    pass
            console.close()
        if libexec_setup:
            subprocess.run(['umount','--lazy','/usr/libexec/samba'],check=True)
            subprocess.run(['umount','--lazy','/usr/libexec'],check=True)
            libexec_setup.cleanup()
