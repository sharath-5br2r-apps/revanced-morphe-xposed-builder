#!/usr/bin/env python3
"""Hold a cross-platform advisory lock until the parent terminates us."""
import os
import signal
import sys
import time


def lock(handle):
    try:
        import fcntl
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    except ImportError:
        import msvcrt
        handle.seek(0)
        handle.write("0")
        handle.flush()
        msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)


if len(sys.argv) != 3:
    raise SystemExit(2)

lock_path, ready_path = sys.argv[1:]
os.makedirs(os.path.dirname(os.path.abspath(lock_path)), exist_ok=True)
with open(lock_path, "a+") as handle:
    lock(handle)
    open(ready_path, "w").close()
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    signal.signal(signal.SIGINT, lambda *_: sys.exit(0))
    while True:
        time.sleep(60)
