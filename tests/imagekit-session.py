"""Set private test directories before GLib caches any user paths."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory(prefix="majoris-files-imagekit-session-") as directory:
    root = Path(directory)
    env = os.environ.copy()
    for name in ("HOME", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "TMPDIR"):
        path = root / name.lower()
        path.mkdir(mode=0o700)
        env[name] = str(path)
    env["GTK_A11Y"] = "none"
    raise SystemExit(subprocess.run(sys.argv[1:], env=env).returncode)
