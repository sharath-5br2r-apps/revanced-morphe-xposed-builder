#!/usr/bin/env python3
"""Generate a GitHub Actions Step Summary for the Version Discovery & Config Generation step."""

from __future__ import annotations

import json
import os
import sys

def main() -> int:
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    lines = []
    lines.append("# 🚀 CI / Version Discovery & Configuration Summary\n")

    mode = os.environ.get("CI_MODE", "Default")
    lines.append(f"**Execution Mode:** `{mode}`\n")

    # App versions fetched
    fetched_file = "fetched_app_versions.json"
    if os.path.exists(fetched_file):
        try:
            with open(fetched_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    lines.append(f"### 📦 Discovered App Versions ({len(data)} apps)\n")
                    lines.append("| App | Version |")
                    lines.append("| :--- | :--- |")
                    for k in sorted(data.keys()):
                        v = data[k]
                        ver = v.get("version", v) if isinstance(v, dict) else v
                        lines.append(f"| `{k}` | `{ver}` |")
                    lines.append("")
        except Exception as e:
            lines.append(f"*(Could not read {fetched_file}: {e})*\n")

    # Patch sources info
    patch_sources_file = "configs/patch_sources.json"
    if os.path.exists(patch_sources_file):
        try:
            with open(patch_sources_file, "r", encoding="utf-8") as f:
                ps = json.load(f)
                if isinstance(ps, dict):
                    lines.append(f"### 🔧 Patch Sources & Tags\n")
                    lines.append("| Source | Tag / Ref |")
                    lines.append("| :--- | :--- |")
                    for src, meta in sorted(ps.items()):
                        tag = meta.get("tag", "N/A") if isinstance(meta, dict) else str(meta)
                        lines.append(f"| `{src}` | `{tag}` |")
                    lines.append("")
        except Exception:
            pass

    # Build triggers
    t_stable = os.environ.get("TRIGGER_STABLE", "0")
    t_prerelease = os.environ.get("TRIGGER_PRERELEASE", "0")
    t_app = os.environ.get("TRIGGER_APP_UPDATE", "0")
    lines.append("### ⚡ Effective Build Triggers\n")
    lines.append(f"- **Trigger Stable:** `{'Yes' if t_stable == '1' else 'No'}`")
    lines.append(f"- **Trigger Prerelease / Beta:** `{'Yes' if t_prerelease == '1' else 'No'}`")
    lines.append(f"- **Trigger App Update:** `{'Yes' if t_app == '1' else 'No'}`\n")

    summary_content = "\n".join(lines) + "\n"

    out_file = sys.argv[1] if len(sys.argv) > 1 else summary_path
    if out_file:
        with open(out_file, "a", encoding="utf-8") as f:
            f.write(summary_content)
    else:
        sys.stdout.write(summary_content)

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
