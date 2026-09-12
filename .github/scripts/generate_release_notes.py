#!/usr/bin/env python3
import os
import re
import sys
import json
import glob
import urllib.request
from pathlib import Path

def load_json(path, default=None):
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: Could not read {path}: {e}")
    return default if default is not None else {}

def resolve_display_name(target_key, info):
    explicit_name = info.get("display_name")
    if explicit_name:
        base_name = explicit_name
    else:
        # If target_key is a filename (e.g. amazon-shopping-morphe-rushiranpise-exp-v32.17.0.100-all.apk)
        raw = info.get("app_key") or target_key
        raw = re.sub(r"\.(apk|zip)$", "", raw, flags=re.IGNORECASE)
        raw = re.sub(r"-v?[0-9].*$", "", raw)
        raw = re.sub(r"-module.*$", "", raw)
        tokens = raw.split("-")
        clean_tokens = []
        stop_words = {"morphe", "revanced", "rvx", "npatch", "xposed", "lspatch", "apksigner", "signed", "exp", "shared"}
        for t in tokens:
            if t.lower() in stop_words:
                break
            clean_tokens.append(t.capitalize())
        base_name = " ".join(clean_tokens) if clean_tokens else raw

    variant = (info.get("variant") or "").strip()
    sub_variant = (info.get("sub_variant") or "").strip()
    extras = []
    if variant and variant.lower() != "default":
        extras.append(variant)
    if sub_variant:
        extras.append(sub_variant)
    if extras:
        return f"{base_name} ({' - '.join(extras)})"
    return base_name


def normalize_arch(arch_raw):
    a = (arch_raw or "").lower().strip()
    if "arm64" in a or "aarch64" in a:
        return "arm64"
    if "arm" in a or "armeabi" in a:
        return "arm"
    if a in ["all", "universal"] or a.endswith("-all") or a.endswith("-universal"):
        return "all"
    if "x86_64" in a or "x64" in a:
        return "x86_64"
    if "x86" in a:
        return "x86"
    return a or "all"

def extract_arch(fname, version=""):
    # First match against known architecture tokens at the end of the filename
    match = re.search(
        r"-(arm64-v8a|armeabi-v7a|arm-v7a|aarch64|arm64|arm32|arm|x86_64|x64|x86|universal|all)(?:-(?:apk|module))?\.(?:apk|zip)$",
        fname,
        re.IGNORECASE
    )
    if match:
        return match.group(1)

    # If version is provided, match what follows -v<version>-
    if version:
        clean_ver = re.escape(version.lstrip("v"))
        m = re.search(rf"-v?{clean_ver}-([a-zA-Z0-9_-]+?)(?:-(?:apk|module))?\.(?:apk|zip)$", fname, re.IGNORECASE)
        if m:
            return m.group(1)

    # Fallback to the last hyphen-delimited segment before extension
    name_no_ext = re.sub(r"\.(?:apk|zip)$", "", fname, flags=re.IGNORECASE)
    name_no_mode = re.sub(r"-(?:apk|module)$", "", name_no_ext, flags=re.IGNORECASE)
    parts = name_no_mode.split("-")
    if len(parts) > 1:
        return parts[-1]

    return "all"

def fetch_online_changelog(url):
    """Attempt to fetch release notes from GitHub or GitLab API if not already embedded in build.json."""
    if not url or "http" not in url:
        return ""
    try:
        headers = {"User-Agent": "ReleaseNotesGenerator"}
        gh_token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or os.environ.get("PERSONAL_ACCESS_TOKEN")
        if "github.com" in url and "/releases/tag/" in url:
            parts = url.split("github.com/")[-1].split("/releases/tag/")
            repo = parts[0].strip("/")
            tag = parts[1].strip("/")
            api_url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
            if gh_token:
                headers["Authorization"] = f"Bearer {gh_token}"
            req = urllib.request.Request(api_url, headers=headers)
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                return (data.get("body") or "").strip()
    except Exception:
        pass
    return ""

def main():
    # CLI arguments support: python3 generate_release_notes.py [input_json] [output_md]
    json_path = "build.json"
    output_md_path = "build.md"

    if len(sys.argv) > 2:
        json_path = sys.argv[1]
        output_md_path = sys.argv[2]
    elif len(sys.argv) > 1:
        arg1 = sys.argv[1]
        if arg1.endswith(".json"):
            json_path = arg1
        elif arg1 in ["dev", "stable", "latest", "manual"]:
            json_path = f"aggregated_out/build.{arg1}.json"
            output_md_path = f"aggregated_out/build.{arg1}.md"
        else:
            output_md_path = arg1

    # Fall back to finding candidate json if default build.json not found
    if not os.path.exists(json_path):
        agg_candidates = glob.glob("aggregated_out/build.*.json") or glob.glob("*/aggregated_out/build.*.json")
        if agg_candidates:
            json_path = agg_candidates[0]

    next_ver_code = os.environ.get("NEXT_VER_CODE", "").strip()
    github_server = os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    github_repo = os.environ.get("GITHUB_REPOSITORY", "sharath-5br2r-apps/revanced-morphe-xposed-builder").strip()

    build_dir = Path("build")
    build_info = load_json(json_path, default={})

    # Discover actual files in build/ if present
    built_files = []
    if build_dir.exists():
        built_files = [f.name for f in build_dir.iterdir() if f.is_file() and f.suffix.lower() in [".apk", ".zip"]]

    # Map target keys to patch groups
    # Group: patch_source -> { "source": str, "tag": str, "changelog_url": str, "release_notes": str, "apps": { app_name: { "display_name": str, "version": str, "apks": [], "modules": [] } } }
    patch_groups = {}

    for target_key, info in build_info.items():
        if not isinstance(info, dict):
            continue

        patches_source = info.get("patches_source") or ""
        patches_ref = info.get("patches") or ""
        if isinstance(patches_ref, list):
            patches_ref = " ".join([str(p) for p in patches_ref])

        changelog_url = (info.get("changelog") or "")
        if isinstance(changelog_url, list):
            changelog_url = " ".join([str(c) for c in changelog_url])
        changelog_url = changelog_url.strip()

        rel_notes = (info.get("release_notes") or "").strip()

        # Extract primary patch source and version tag
        primary_source = patches_source.split()[0] if patches_source else (patches_ref.split()[0].split("/")[0] if "/" in patches_ref else "Patched")

        # Determine patch version tag
        patch_tag = ""
        first_url = changelog_url.split()[0] if changelog_url else ""
        if first_url:
            if "/tag/" in first_url:
                patch_tag = first_url.split("/tag/")[-1].strip("/")
            elif "/-/releases/" in first_url:
                patch_tag = first_url.split("/-/releases/")[-1].strip("/")
            elif "/releases/" in first_url:
                patch_tag = first_url.split("/releases/")[-1].strip("/")

        if not patch_tag and patches_ref:
            ref_part = re.sub(r"\.(mpp|jar|rvp|apk|zip)$", "", patches_ref.split()[0], flags=re.IGNORECASE)
            tag_match = re.search(r"v?\d+(\.\d+)+([.-][a-zA-Z0-9]+)*", ref_part)
            if tag_match:
                matched = tag_match.group(0)
                patch_tag = matched if matched.startswith("v") else f"v{matched}"

        group_key = primary_source
        if group_key not in patch_groups:
            patch_groups[group_key] = {
                "source": primary_source,
                "tag": patch_tag,
                "changelog_url": first_url,
                "release_notes": rel_notes,
                "apps": {}
            }
        elif rel_notes and not patch_groups[group_key]["release_notes"]:
            patch_groups[group_key]["release_notes"] = rel_notes

        # Resolve display name directly from structured build info
        display_name = resolve_display_name(target_key, info)
        version = str(info.get("version", "")).strip()
        file_prefix = str(info.get("name", "")).strip()
        arch = str(info.get("arch", "")).strip()
        ext = str(info.get("ext", "")).strip()

        if display_name not in patch_groups[group_key]["apps"]:
            patch_groups[group_key]["apps"][display_name] = {
                "display_name": display_name,
                "version": version,
                "apks": [],
                "modules": []
            }
        app_entry = patch_groups[group_key]["apps"][display_name]
        if version and not app_entry["version"]:
            app_entry["version"] = version

        # Find matching built files from disk
        matched_from_disk = False
        for fname in built_files:
            lower = fname.lower()
            prefix_lower = file_prefix.lower()
            if not (lower.startswith(prefix_lower + "-v") or lower.startswith(prefix_lower + "-module-")):
                continue

            matched_from_disk = True
            norm_arch = normalize_arch(extract_arch(fname, version))
            dl_url = f"{github_server}/{github_repo}/releases/download/{next_ver_code}/{fname}" if (github_repo and next_ver_code) else f"./build/{fname}"

            if lower.endswith(".apk") and "-module-" not in lower:
                if not any(url == dl_url for _, url in app_entry["apks"]):
                    app_entry["apks"].append((norm_arch, dl_url))
            elif lower.endswith(".zip") and "-module-" in lower:
                if not any(url == dl_url for _, url in app_entry["modules"]):
                    app_entry["modules"].append((norm_arch, dl_url))

        # Fallback for batch aggregation / remote builds where ./build/ directory is absent
        if not matched_from_disk and file_prefix:
            norm_arch = normalize_arch(arch)
            clean_ver = version.replace(" ", "")
            # Check if entry represents a completed build
            if target_key.endswith(".apk") or ext == ".apk":
                fname = target_key if target_key.endswith(".apk") else f"{file_prefix}-v{clean_ver}-{arch or 'all'}.apk"
                dl_url = f"{github_server}/{github_repo}/releases/download/{next_ver_code}/{fname}" if (github_repo and next_ver_code) else fname
                if not any(url == dl_url for _, url in app_entry["apks"]):
                    app_entry["apks"].append((norm_arch, dl_url))
            elif target_key.endswith(".zip") or ext == ".zip":
                fname = target_key if target_key.endswith(".zip") else f"{file_prefix}-module-v{clean_ver}-{arch or 'all'}.zip"
                dl_url = f"{github_server}/{github_repo}/releases/download/{next_ver_code}/{fname}" if (github_repo and next_ver_code) else fname
                if not any(url == dl_url for _, url in app_entry["modules"]):
                    app_entry["modules"].append((norm_arch, dl_url))

        # Sort architectures consistently: arm64, arm, all, etc.
        arch_priority = {"arm64": 0, "arm": 1, "all": 2, "universal": 3, "x86_64": 4, "x86": 5}
        app_entry["apks"].sort(key=lambda x: arch_priority.get(x[0], 99))
        app_entry["modules"].sort(key=lambda x: arch_priority.get(x[0], 99))

    # Build output markdown
    lines = []
    sorted_group_keys = sorted(patch_groups.keys())

    for gkey in sorted_group_keys:
        group = patch_groups[gkey]
        apps = group["apps"]
        # Remove empty apps
        valid_apps = {k: v for k, v in apps.items() if v["apks"] or v["modules"] or v["version"]}
        if not valid_apps:
            continue

        # Header format: ### 🧩 source ([tag](url))
        src = group["source"]
        tag = group["tag"]
        cl_url = group["changelog_url"]

        if tag and cl_url:
            tag_str = f" ([{tag}]({cl_url}))"
        elif tag:
            tag_str = f" ({tag})"
        elif cl_url:
            tag_str = f" ([changelog]({cl_url}))"
        else:
            tag_str = ""

        lines.append(f"### 🧩 {src}{tag_str}")
        lines.append("")

        # Patch changelog / release notes placed just above the apps in each patch
        changelog_text = group.get("release_notes")
        if not changelog_text and cl_url:
            changelog_text = fetch_online_changelog(cl_url)

        if changelog_text:
            lines.append("<details>")
            lines.append("<summary><b>Changelog</b></summary>")
            lines.append("")
            lines.append(changelog_text.strip())
            lines.append("")
            lines.append("</details>")
            lines.append("")

        # List apps in this patch group
        for app_name in sorted(valid_apps.keys()):
            app = valid_apps[app_name]
            ver_str = f" `v{app['version']}`" if app['version'] else ""
            lines.append(f"* **{app['display_name']}**{ver_str}")

            if app["apks"]:
                apk_links = " • ".join([f"[{arch}]({url})" for arch, url in app["apks"]])
                lines.append(f"  * APK: {apk_links}")

            if app["modules"]:
                mod_links = " • ".join([f"[{arch}]({url})" for arch, url in app["modules"]])
                lines.append(f"  * Module: {mod_links}")

            lines.append("")

    # Notes section with custom repository and website links preserved
    lines.append("---")
    lines.append("")
    lines.append("### ℹ️ Notes")
    lines.append("• Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases/latest) or [MicroG](https://github.com/ReVanced/GmsCore/releases/latest), required for Google APKs.  ")
    lines.append("• Use [Zygisk Detach](https://github.com/j-hc/zygisk-detach) to stop Play Store from updating Modules.  ")
    lines.append("")
    lines.append("🌐 [GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder) | 🔗 [Website](https://sharath-5br2r.github.io/catalog)")
    lines.append("")

    content = "\n".join(lines)
    os.makedirs(os.path.dirname(output_md_path) or ".", exist_ok=True)
    with open(output_md_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Successfully generated {output_md_path}")

if __name__ == "__main__":
    main()

