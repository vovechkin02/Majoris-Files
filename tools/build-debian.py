#!/usr/bin/python3
"""Build unsigned binary packages on a Linux filesystem, including from WSL.

Only a temporary source copy is built; no packages are installed. Build/test
diagnostics and resulting artifacts are retained in the checkout's build/ folder.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


source = Path(__file__).resolve().parents[1]
output = source / 'build'
output.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(prefix='majoris-debian-') as directory:
    work = Path(directory) / 'majoris-files'
    shutil.copytree(source, work, ignore=shutil.ignore_patterns(
        '.git', '.reference', 'build', 'obj-*', '__pycache__', '*.swp'))
    # DrvFs without metadata exposes 0777 even after chmod. Normalize the private
    # Linux copy so dpkg can enforce control-directory and installed-file modes.
    for parent, directories, files in os.walk(work):
        Path(parent).chmod(0o755)
        for name in files:
            path = Path(parent) / name
            if not path.is_symlink():
                path.chmod(0o755 if path == work / 'debian/rules' else 0o644)
    environment = dict(os.environ)
    environment.setdefault('DEB_BUILD_OPTIONS', 'parallel=4')
    with (output / 'debian-build.log').open('w') as log:
        subprocess.run(['dpkg-buildpackage', '-us', '-uc', '-b'], cwd=work,
                       env=environment, stdout=log, stderr=subprocess.STDOUT,
                       check=True)
    artifacts = [path for path in Path(directory).iterdir()
                 if path.is_file() and path.suffix in {'.deb', '.changes', '.buildinfo'}]
    if not artifacts:
        raise RuntimeError('The package builder did not produce any artifacts')
    for artifact in artifacts:
        shutil.copy2(artifact, output / artifact.name)
        print(output / artifact.name)
