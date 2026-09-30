#!/usr/bin/env python3
"""Generate a clean Markdown report from error.json and/or build_log.json."""

from __future__ import annotations

import json
import os
import sys
from typing import Any, Dict, List

def load_json(path: str) -> List[Dict[str, Any]]:
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                return data
            elif isinstance(data, dict):
                return [data]
    except Exception as e:
        sys.stderr.write(f"Warning: Failed to load {path}: {e}\n")
    return []

def format_report(log_entries: List[Dict[str, Any]]) -> str:
    errors: List[Dict[str, Any]] = []
    warnings: List[Dict[str, Any]] = []
    successes: List[Dict[str, Any]] = []

    for entry in log_entries:
        level = (entry.get("level") or "").lower()
        if level == "error":
            errors.append(entry)
        elif level == "warning":
            warnings.append(entry)
        elif level == "success":
            successes.append(entry)

    lines: List[str] = []
    lines.append("# Build Status Report\n")
    lines.append("| Metric | Count |")
    lines.append("| :--- | :---: |")
    lines.append(f"| **Successful Builds / Events** | {len(successes)} |")
    lines.append(f"| **Errors** | {len(errors)} |")
    lines.append(f"| **Warnings** | {len(warnings)} |\n")

    if errors:
        lines.append("## ❌ Errors\n")
        lines.append("| App / Target | Part / Step | Error Message | Timestamp |")
        lines.append("| :--- | :--- | :--- | :--- |")
        for err in errors:
            app = err.get("app") or "N/A"
            part = err.get("part") or "N/A"
            msg = (err.get("message") or "").replace("|", "\\|").replace("\n", "<br>")
            ts = err.get("timestamp") or "N/A"
            lines.append(f"| `{app}` | `{part}` | {msg} | {ts} |")
        lines.append("")

    if warnings:
        lines.append("## ⚠️ Warnings\n")
        lines.append("| App / Target | Part / Step | Warning Message | Timestamp |")
        lines.append("| :--- | :--- | :--- | :--- |")
        for warn in warnings:
            app = warn.get("app") or "N/A"
            part = warn.get("part") or "N/A"
            msg = (warn.get("message") or "").replace("|", "\\|").replace("\n", "<br>")
            ts = warn.get("timestamp") or "N/A"
            lines.append(f"| `{app}` | `{part}` | {msg} | {ts} |")
        lines.append("")

    if successes:
        lines.append("## ✅ Successful Builds\n")
        lines.append("| App / Target | Part | Details | Timestamp |")
        lines.append("| :--- | :--- | :--- | :--- |")
        for sc in successes:
            app = sc.get("app") or "N/A"
            part = sc.get("part") or "N/A"
            msg = (sc.get("message") or "").replace("|", "\\|").replace("\n", "<br>")
            ts = sc.get("timestamp") or "N/A"
            lines.append(f"| `{app}` | `{part}` | {msg} | {ts} |")
        lines.append("")

    if not errors and not warnings and not successes:
        lines.append("No errors or build log events were recorded.\n")

    return "\n".join(lines)

def main() -> int:
    # Arguments: [input_json_or_dir] [output_md]
    input_path = sys.argv[1] if len(sys.argv) > 1 else ""
    output_file = sys.argv[2] if len(sys.argv) > 2 else "error.md"

    entries: List[Dict[str, Any]] = []

    if input_path and os.path.isfile(input_path):
        entries.extend(load_json(input_path))
    else:
        # Check standard file locations
        candidates = ["error.json", "build_log.json"]
        if input_path and os.path.isdir(input_path):
            candidates = [
                os.path.join(input_path, "error.json"),
                os.path.join(input_path, "build_log.json"),
            ]
        for cand in candidates:
            if os.path.exists(cand):
                entries.extend(load_json(cand))

    # Deduplicate entries by timestamp + message + app + part
    deduped: List[Dict[str, Any]] = []
    seen = set()
    for e in entries:
        key = (e.get("timestamp"), e.get("level"), e.get("app"), e.get("part"), e.get("message"))
        if key not in seen:
            seen.add(key)
            deduped.append(e)

    content = format_report(deduped)
    with open(output_file, "w", encoding="utf-8") as f:
        f.write(content)
        f.write("\n")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
