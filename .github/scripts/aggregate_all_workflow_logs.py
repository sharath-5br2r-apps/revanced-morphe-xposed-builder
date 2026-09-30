#!/usr/bin/env python3
"""Aggregate all build part logs, markdowns, and JSON logs into a unified summary."""

from __future__ import annotations

import glob
import json
import os
import sys
from typing import Any, Dict, List

def load_json(path: str) -> Any:
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def main() -> int:
    # 1. Locate all downloaded logs or artifacts
    search_dirs = ["logs_artifacts", "part_logs", "artifacts", "."]
    
    # We want to find error.json, build_log.json, error.md, build.md grouped by artifact / folder
    found_error_jsons = glob.glob("**/error.json", recursive=True)
    found_build_log_jsons = glob.glob("**/build_log.json", recursive=True)
    found_error_mds = glob.glob("**/error.md", recursive=True)

    all_entries: List[Dict[str, Any]] = []
    
    for ej in found_error_jsons:
        if "aggregated_out" in ej:
            continue
        data = load_json(ej)
        if isinstance(data, list):
            all_entries.extend(data)

    for bl in found_build_log_jsons:
        if "aggregated_out" in bl:
            continue
        data = load_json(bl)
        if isinstance(data, list):
            all_entries.extend(data)

    # Deduplicate entries
    deduped = []
    seen = set()
    for e in all_entries:
        key = (e.get("timestamp"), e.get("level"), e.get("app"), e.get("part"), e.get("message"))
        if key not in seen:
            seen.add(key)
            deduped.append(e)

    # Import formatter from generate_error_markdown
    sys.path.insert(0, os.path.dirname(__file__))
    import generate_error_markdown

    global_summary = generate_error_markdown.format_report(deduped)

    # Build per-artifact error log sections
    per_artifact_sections: List[str] = []
    
    # Find all error.log or error.md files grouped by directory / artifact
    # Group by artifact directory name
    artifact_dirs = set()
    for f in glob.glob("**/*", recursive=True):
        if os.path.isfile(f) and (os.path.basename(f) in ["error.log", "error.md", "error.json", "build_log.json"]):
            d = os.path.dirname(f)
            if d and d != "." and not d.startswith("aggregated_out"):
                artifact_dirs.add(d)

    for ad in sorted(artifact_dirs):
        artifact_name = os.path.basename(ad)
        section_lines = [f"### 📁 Artifact / Job: `{artifact_name}`\n"]
        
        # Check if error.md exists
        emd = os.path.join(ad, "error.md")
        ej = os.path.join(ad, "error.json")
        blj = os.path.join(ad, "build_log.json")
        el = os.path.join(ad, "error.log")
        
        has_content = False
        entries_in_part = []
        if os.path.exists(ej):
            d = load_json(ej)
            if isinstance(d, list): entries_in_part.extend(d)
        if os.path.exists(blj):
            d = load_json(blj)
            if isinstance(d, list): entries_in_part.extend(d)
            
        if entries_in_part:
            part_deduped = []
            pseen = set()
            for e in entries_in_part:
                k = (e.get("timestamp"), e.get("level"), e.get("app"), e.get("part"), e.get("message"))
                if k not in pseen:
                    pseen.add(k)
                    part_deduped.append(e)
            part_md = generate_error_markdown.format_report(part_deduped)
            section_lines.append(part_md)
            has_content = True
        elif os.path.exists(emd) and os.path.getsize(emd) > 0:
            with open(emd, "r", encoding="utf-8") as f:
                section_lines.append(f.read())
            has_content = True
        elif os.path.exists(el) and os.path.getsize(el) > 0:
            with open(el, "r", encoding="utf-8") as f:
                raw_log = f.read().strip()
                if raw_log:
                    section_lines.append(f"```text\n{raw_log}\n```\n")
                    has_content = True

        if has_content:
            per_artifact_sections.append("\n".join(section_lines))

    # Combine into full summary
    out_lines = []
    out_lines.append("# 🏁 Final Build Workflow Summary\n")
    out_lines.append(global_summary)
    out_lines.append("\n---\n")

    if per_artifact_sections:
        out_lines.append("## 📑 Per-Artifact Build Logs\n")
        out_lines.extend(per_artifact_sections)

    final_content = "\n".join(out_lines) + "\n"

    out_file = sys.argv[1] if len(sys.argv) > 1 else "workflow_summary.md"
    with open(out_file, "w", encoding="utf-8") as f:
        f.write(final_content)

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as f:
            f.write(final_content)

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
