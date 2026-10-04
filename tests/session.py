"""Exercise the actual executable's crash recovery in an isolated desktop session."""
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import tempfile
import time


def wait_state(database, predicate, process):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise AssertionError(f"Files exited unexpectedly: {process.returncode}")
        try:
            with sqlite3.connect(database, timeout=0.2) as db:
                state = dict(db.execute("SELECT key,value FROM state"))
            if predicate(state):
                return state
        except sqlite3.Error:
            pass
        time.sleep(0.05)
    raise AssertionError("Session state did not reach the expected value")


with tempfile.TemporaryDirectory(prefix="majoris-session-") as temporary:
    root = Path(temporary)
    environment = os.environ.copy()
    environment.update(HOME=temporary, XDG_CONFIG_HOME=str(root / "config"),
                       XDG_DATA_HOME=str(root / "data"), XDG_CACHE_HOME=str(root / "cache"),
                       GSK_RENDERER="cairo", GSETTINGS_BACKEND="memory")
    database = root / "data/majoris-files/metadata.db"
    first = root / "First"
    second = root / "Second"
    first.mkdir()
    second.mkdir()
    process = None
    try:
        process = subprocess.Popen([sys.argv[1]], env=environment,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        wait_state(database, lambda state: "majoris:///home" in state.get("session-last", ""), process)
        process.send_signal(signal.SIGKILL)
        process.wait(timeout=5)
        snapshot = f"[  ([('{first.as_uri()}', 'List'), ('{second.as_uri()}', 'Grid')], uint32 1)  ]"
        with sqlite3.connect(database) as db:
            db.execute("UPDATE state SET value=? WHERE key='session-last'", (snapshot,))
        process = subprocess.Popen([sys.argv[1]], env=environment,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        state = wait_state(database, lambda state: first.as_uri() in state.get("session-last", "")
                           and second.as_uri() in state.get("session-last", "")
                           and state.get("session-last") != snapshot, process)
        assert "List" in state["session-last"]
        assert "uint32 1" in state["session-last"]
        process.send_signal(signal.SIGKILL)
        process.wait(timeout=5)
        with sqlite3.connect(database) as db:
            db.execute("INSERT OR REPLACE INTO state VALUES('restore-session','false')")
        process = subprocess.Popen([sys.argv[1]], env=environment,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        state = wait_state(database, lambda state: "majoris:///home" in state.get("session-last", ""), process)
        assert first.as_uri() not in state["session-last"]
        print("Crash recovery restored tab locations, views, and selection; opt-out respected.")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait(timeout=5)
