"""Collect this integration's disposable Linux verification outputs.

Run under the Debian build environment after verification. No source is vendored;
the adjacent upstream working revision is identified by its base and file hashes.
"""
from pathlib import Path
import hashlib
import json
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
upstream = root.parent / "Majoris-Image"
base = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
assert base == "5428aa1da43c8d649cfbad79a54a83c7e18831ea", base
changed = subprocess.check_output(["git", "-C", str(upstream), "diff", "--name-only"], text=True).splitlines()
changed += subprocess.check_output(["git", "-C", str(upstream), "ls-files", "--others", "--exclude-standard"], text=True).splitlines()
files = {}
for name in sorted(set(changed)):
    path = upstream / name
    if path.is_file() and path.suffix != ".zip":
        files[name] = hashlib.sha256(path.read_bytes()).hexdigest()
revision = {
    "repository": "https://github.com/vovechkin02/Majoris-Image",
    "base_commit": base,
    "working_version": "2.0.1",
    "uncommitted_upstream_changes": True,
    "pkg_config": ["majoris-image-1", "majoris-image-gtk4-1"],
    "soname_major": 2,
    "working_file_sha256": files,
}
(root / "docs/imagekit-revision.json").write_text(json.dumps(revision, indent=2) + "\n")
output = root / "artifacts/imagekit-verification"
output.mkdir(parents=True, exist_ok=True)
for path in Path("/tmp").glob("majoris-files-imagekit-*.log"):
    shutil.copyfile(path, output / path.name)
packages = output / "packages"
packages.mkdir(exist_ok=True)
for name in ("libmajoris-image2", "libmajoris-image-gtk4-2", "libmajoris-image-dev", "majoris-image-worker", "majoris-image-thumbnailer"):
    path = Path("/tmp") / f"{name}_2.0.1_amd64.deb"
    if path.exists():
        shutil.copyfile(path, packages / path.name)
checksums = {}
for path in sorted(output.rglob("*")):
    if path.is_file() and path.name != "sha256.json":
        checksums[path.relative_to(output).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
(output / "sha256.json").write_text(json.dumps(checksums, indent=2) + "\n")
print(f"Recorded {len(files)} upstream files and {len(checksums)} verification artifacts")
