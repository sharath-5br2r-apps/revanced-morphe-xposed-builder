#!/usr/bin/env python3
"""Append structured JSON log entries safely without leaking secrets."""

from __future__ import annotations

import datetime
import json
import os
import re
import sys

def lock_file(handle) -> None:
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

def sanitize_message(msg: str) -> str:
    sensitive_patterns = [
        os.environ.get("GITHUB_TOKEN", ""),
        os.environ.get("GH_TOKEN", ""),
        os.environ.get("PERSONAL_ACCESS_TOKEN", ""),
        os.environ.get("KEYSTORE_BASE64", ""),
        os.environ.get("KEYSTORE_PASSWORD", ""),
        os.environ.get("KEYSTORE_KEY_PASSWORD", ""),
        os.environ.get("RVB_KEYSTORE_PASS", ""),
    ]
    for secret in sensitive_patterns:
        if secret and len(secret) > 2 and secret in msg:
            msg = msg.replace(secret, "***REDACTED***")
    # Redact common keypass/storepass arguments if caught in command line strings
    msg = re.sub(r'(-passin\s+pass:)(\S+)', r'\1***REDACTED***', msg, flags=re.IGNORECASE)
    msg = re.sub(r'(-storepass\s+)(\S+)', r'\1***REDACTED***', msg, flags=re.IGNORECASE)
    msg = re.sub(r'(-keypass\s+)(\S+)', r'\1***REDACTED***', msg, flags=re.IGNORECASE)
    msg = re.sub(r'(--ks-pass\s+pass:)(\S+)', r'\1***REDACTED***', msg, flags=re.IGNORECASE)
    msg = re.sub(r'(--key-pass\s+pass:)(\S+)', r'\1***REDACTED***', msg, flags=re.IGNORECASE)
    return msg

def main() -> int:
    if len(sys.argv) < 3:
        sys.stderr.write("Usage: append_build_log.py <json_file> <level> [message] [app] [part]\n")
        return 1

    json_file = sys.argv[1]
    level = sys.argv[2]
    raw_message = sys.argv[3] if len(sys.argv) > 3 else ""
    app = sys.argv[4] if len(sys.argv) > 4 else os.environ.get("CURRENT_APP_NAME", "")
    part = sys.argv[5] if len(sys.argv) > 5 else os.environ.get("CURRENT_BUILD_PART", "")

    message = sanitize_message(raw_message.strip())
    now_iso = datetime.datetime.now(datetime.timezone.utc).isoformat()

    entry = {
        "timestamp": now_iso,
        "level": level,
        "app": app,
        "part": part,
        "message": message,
    }

    lock_path = f"{json_file}.lock"
    os.makedirs(os.path.dirname(os.path.abspath(json_file)) or ".", exist_ok=True)
    with open(lock_path, "a+") as lock:
        lock_file(lock)
        data = []
        if os.path.exists(json_file) and os.path.getsize(json_file) > 0:
            try:
                with open(json_file, "r", encoding="utf-8") as f:
                    content = json.load(f)
                    if isinstance(content, list):
                        data = content
            except Exception:
                data = []

        data.append(entry)

        tmp_file = f"{json_file}.tmp.{os.getpid()}"
        with open(tmp_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp_file, json_file)

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
