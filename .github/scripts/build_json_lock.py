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
    output_path = None
    command_start = 2
    if len(sys.argv) > 3 and sys.argv[2] == "--output":
        output_path = sys.argv[3]
        command_start = 4
    command = sys.argv[command_start:]
    if not command:
        return 2
    os.makedirs(os.path.dirname(os.path.abspath(lock_path)), exist_ok=True)
    with open(lock_path, "a+") as lock:
        lock_file(lock)
        if output_path is None:
            return subprocess.run(command).returncode
        result = subprocess.run(command, stdout=subprocess.PIPE)
        if result.returncode != 0:
            return result.returncode
        temporary = f"{output_path}.tmp.{os.getpid()}"
        with open(temporary, "wb") as output:
            output.write(result.stdout)
        os.replace(temporary, output_path)
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
