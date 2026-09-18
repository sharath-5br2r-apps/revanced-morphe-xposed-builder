#!/usr/bin/env python3
"""Run a command while holding an advisory lock for concurrent build.json writes."""

from __future__ import annotations

import os
import subprocess
import sys


def lock_file(handle) -> None:
    """Lock one shared byte using the platform's native advisory locking API."""
    try:
        import fcntl

        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        return
    except ImportError:
        import msvcrt

        handle.seek(0)
        handle.write("0")
        handle.flush()
        msvcrt.locking(handle.fileno(), msvcrt.LK_LOCK, 1)


def main() -> int:
    if len(sys.argv) < 3:
        return 2
    lock_path = sys.argv[1]
    command = sys.argv[2:]
    os.makedirs(os.path.dirname(os.path.abspath(lock_path)), exist_ok=True)
    with open(lock_path, "a+") as lock:
        lock_file(lock)
        return subprocess.run(command).returncode


if __name__ == "__main__":
    raise SystemExit(main())
