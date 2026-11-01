"""Capture creation/header/toolbar/menu evidence with the supplied Majoris Theme.
Usage: python3 tools/capture-creation-sorting.py /path/to/Majoris-Theme
No styling is copied into application sources; GTK overrides live in a temp dir.
"""
import concurrent.futures
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
if sys.argv[1] == "--worker":
    wm = subprocess.Popen(["openbox"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    compositor = subprocess.Popen(["xcompmgr", "-a"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        subprocess.run(sys.argv[2:], check=True)
    finally:
        compositor.terminate()
        compositor.wait(timeout=5)
        wm.terminate()
        wm.wait(timeout=5)
    raise SystemExit(0)

theme = Path(sys.argv[1]).resolve()
output = root / "artifacts/creation-sorting"

def palette(name):
    with tempfile.TemporaryDirectory(prefix="majoris-creation-visual-") as runtime:
        config = Path(runtime) / "config"
        gtk = config / "gtk-4.0"
        shutil.copytree(theme / "theme/Majoris/gtk-4.0", gtk)
        if name == "dark":
            shutil.copyfile(gtk / "gtk-dark.css", gtk / "gtk.css")
        destination = output / name
        target = Path(runtime) / "captures"
        target.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ, XDG_CONFIG_HOME=str(config), GDK_BACKEND="x11",
                   GSK_RENDERER="cairo", GSETTINGS_BACKEND="memory", GTK_A11Y="none",
                   ADW_DISABLE_PORTAL="1", MAJORIS_TOOLBAR_GEOMETRY="1",
                   MAJORIS_VISUAL_DARK="1" if name == "dark" else "0",
                   MAJORIS_CREATION_EVIDENCE=str(target), MAJORIS_MENU_EVIDENCE=str(target / "menus"),
                   MAJORIS_MENU_THEME=str(theme / "theme/Majoris"))
        commands = [("creation", [str(root / "build/creation-sorting-tests")]),
                    ("toolbar", [str(root / "build/toolbar-tests"), str(target / "toolbar")]),
                    ("menus", [str(root / "build/menu-tests")])]
        if "--creation-only" in sys.argv:
            commands = commands[:1]
        elif "--chrome-only" in sys.argv:
            commands = commands[1:]
        try:
            for label, command in commands:
                with (target / (label + ".log")).open("w") as log:
                    subprocess.run(["dbus-run-session", "--", "xvfb-run", "-a", "-s", "-screen 0 1920x1280x24",
                                    sys.executable, __file__, "--worker", *command], cwd=root, env=env,
                                   stdout=log, stderr=subprocess.STDOUT, check=True)
        finally:
            # Render on Linux storage; ImageMagick overwrites can fail on drvfs.
            shutil.copytree(target, destination, dirs_exist_ok=True)
        return name + ": " + ", ".join(label for label, _ in commands) + " passed"

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
    for result in pool.map(palette, ("light", "dark")):
        print(result)
