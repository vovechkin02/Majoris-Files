#!/usr/bin/python3
"""Run only in a private mount namespace; mounts a bounded fixture tmpfs."""
import os, pathlib, subprocess, sys, tempfile
if os.geteuid()!=0 or os.readlink('/proc/self/ns/mnt')==os.readlink('/proc/1/ns/mnt'):
    raise SystemExit('Requires root in a private mount namespace')
uid=int(os.environ.get('MAJORIS_TEST_UID','1000'))
if uid<=0: raise SystemExit('Client must be unprivileged')
with tempfile.TemporaryDirectory(prefix='majoris-enospc-') as root:
    subprocess.run(['mount','-t','tmpfs','-o',f'size=8m,mode=0700,uid={uid},gid={uid}','tmpfs',root],check=True)
    try:
        def drop(): os.setgroups([]);os.setgid(uid);os.setuid(uid)
        subprocess.run([str(pathlib.Path(sys.argv[1]).resolve()),'--disk-full',root],preexec_fn=drop,check=True,timeout=30)
    finally: subprocess.run(['umount',root],check=True)
