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
        raw = info.get("name") or target_key
        raw = re.sub(r"\.(apk|zip)$", "", raw, flags=re.IGNORECASE)
        raw = re.sub(r"-v?[0-9].*$", "", raw)
        raw = re.sub(r"-module.*$", "", raw)
        tokens = raw.split("-")
        base_name = " ".join(t.capitalize() for t in tokens if t) if tokens else raw

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

def extract_arch_from_filename(fname, version=""):
    match = re.search(
        r"-(arm64-v8a|armeabi-v7a|armeabi-v7a|aarch64|arm64|arm32|arm|x86_64|x64|x86|universal|all)(?:-(?:apk|module))?\.(?:apk|zip)$",
        fname, re.IGNORECASE
    )
    if match:
        return match.group(1)
    if version:
        clean_ver = re.escape(version.lstrip("v"))
        m = re.search(rf"-v?{clean_ver}-([a-zA-Z0-9_-]+?)(?:-(?:apk|module))?\.(?:apk|zip)$", fname, re.IGNORECASE)
        if m:
            return m.group(1)
    name_no_ext = re.sub(r"\.(?:apk|zip)$", "", fname, flags=re.IGNORECASE)
    name_no_mode = re.sub(r"-(?:apk|module)$", "", name_no_ext, flags=re.IGNORECASE)
    parts = name_no_mode.split("-")
    return parts[-1] if len(parts) > 1 else "all"

def fetch_online_changelog(url):
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

    if not os.path.exists(json_path):
        agg_candidates = glob.glob("aggregated_out/build.*.json") or glob.glob("*/aggregated_out/build.*.json")
        if agg_candidates:
            json_path = agg_candidates[0]

    next_ver_code = os.environ.get("NEXT_VER_CODE", "").strip()
    github_server = os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
    github_repo = os.environ.get("GITHUB_REPOSITORY", "sharath-5br2r-apps/revanced-morphe-xposed-builder").strip()

    build_dir = Path("build")
    build_info = load_json(json_path, default={})

    # Index files actually present in build/
    built_files = set()
    if build_dir.exists():
        built_files = {f.name for f in build_dir.iterdir() if f.is_file() and f.suffix.lower() in [".apk", ".zip"]}

    # patch_source → { source, tag, changelog_url, release_notes, apps: { display_name → { version, apks, modules } } }
    patch_groups = {}

    for target_key, info in build_info.items():
        if not isinstance(info, dict):
            continue

        # Skip legacy file-named keys
        if target_key.lower().endswith((".apk", ".zip")):
            continue

        patches_source = info.get("patches_source") or ""
        patches_ref = info.get("patches") or ""
        if isinstance(patches_ref, list):
            patches_ref = " ".join(str(p) for p in patches_ref)

        changelog_val = info.get("changelog") or ""
        if isinstance(changelog_val, list):
            changelog_val = " ".join(str(c) for c in changelog_val)
        changelog_url = changelog_val.strip()

        primary_source = patches_source.split()[0] if patches_source else (
            patches_ref.split()[0].split("/")[0] if "/" in patches_ref else "Patched"
        )

        patch_tag = ""
        first_url = changelog_url.split()[0] if changelog_url else ""
        if first_url:
            for sep in ["/tag/", "/-/releases/", "/releases/"]:
                if sep in first_url:
                    patch_tag = first_url.split(sep)[-1].strip("/")
                    break
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
                "release_notes": "",
                "apps": {}
            }

        display_name = resolve_display_name(target_key, info)
        version = str(info.get("version", "")).strip()

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

        # Build download links from assets[]
        assets = info.get("assets") or []
        for asset in assets:
            fname = asset.get("name", "")
            if not fname:
                continue

            # Only include if file is on disk, or build/ is absent (aggregated/remote run)
            if built_files and fname not in built_files:
                continue

            arch_raw = asset.get("arch") or extract_arch_from_filename(fname, version)
            norm_arch = normalize_arch(arch_raw)
            dl_url = (
                f"{github_server}/{github_repo}/releases/download/{next_ver_code}/{fname}"
                if github_repo and next_ver_code else f"./build/{fname}"
            )

            lower = fname.lower()
            if lower.endswith(".apk") and "-module-" not in lower:
                if not any(u == dl_url for _, u, *_ in app_entry["apks"]):
                    app_entry["apks"].append((norm_arch, dl_url))
            elif lower.endswith(".zip") and "-module-" in lower:
                display_label = f"{norm_arch} (Beta Channel)" if "-module-beta" in lower else norm_arch
                if not any(u == dl_url for _, u, *_ in app_entry["modules"]):
                    app_entry["modules"].append((display_label, dl_url, norm_arch, "-module-beta" in lower))

        # Fallback: no assets[], reconstruct filenames from top-level exts[]+name+arch
        if not assets:
            name = info.get("name", "")
            arch = str(info.get("arch", "")).strip()
            exts = info.get("exts") or []
            clean_ver = version.replace(" ", "")
            norm_arch = normalize_arch(arch)
            for ext in exts:
                ext = ext.lstrip(".")
                if ext == "apk":
                    fname = f"{name}-v{clean_ver}-{arch or 'all'}.apk"
                    dl_url = (
                        f"{github_server}/{github_repo}/releases/download/{next_ver_code}/{fname}"
                        if github_repo and next_ver_code else fname
                    )
                    if not any(u == dl_url for _, u, *_ in app_entry["apks"]):
                        app_entry["apks"].append((norm_arch, dl_url))
                elif ext == "zip":
                    fname = f"{name}-module-v{clean_ver}-{arch or 'all'}.zip"
                    dl_url = (
                        f"{github_server}/{github_repo}/releases/download/{next_ver_code}/{fname}"
                        if github_repo and next_ver_code else fname
                    )
                    if not any(u == dl_url for _, u, *_ in app_entry["modules"]):
                        app_entry["modules"].append((norm_arch, dl_url, norm_arch, False))

        arch_priority = {"arm64": 0, "arm": 1, "all": 2, "universal": 3, "x86_64": 4, "x86": 5}
        app_entry["apks"].sort(key=lambda x: arch_priority.get(x[0], 99))
        app_entry["modules"].sort(key=lambda x: (arch_priority.get(x[2], 99), 1 if x[3] else 0))

    # Build output markdown
    lines = []
    for gkey in sorted(patch_groups.keys()):
        group = patch_groups[gkey]
        valid_apps = {k: v for k, v in group["apps"].items() if v["apks"] or v["modules"] or v["version"]}
        if not valid_apps:
            continue

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

        changelog_text = group.get("release_notes") or ""
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

        for app_name in sorted(valid_apps.keys()):
            app = valid_apps[app_name]
            ver_str = f" `v{app['version']}`" if app["version"] else ""
            lines.append(f"* **{app['display_name']}**{ver_str}")

            if app["apks"]:
                apk_links = " • ".join(f"[{arch}]({url})" for arch, url in app["apks"])
                lines.append(f"  * APK: {apk_links}")

            if app["modules"]:
                mod_links = " • ".join(f"[{label}]({url})" for label, url, _, _ in app["modules"])
                lines.append(f"  * Module: {mod_links}")

            lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("### ℹ️ Notes")
    lines.append("• Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases/latest) or [MicroG](https://github.com/ReVanced/GmsCore/releases/latest), required for Google APKs.  ")
    lines.append("• Use [Zygisk Detach](https://github.com/j-hc/zygisk-detach) to stop Play Store from updating Modules.  ")
    lines.append("")
    gh_repo = os.environ.get("GITHUB_REPOSITORY") or "nullcpy/rvb"
    website_link = os.environ.get("RELEASE_NOTES_WEBSITE_LINK") or "https://sharath-5br2r.github.io/catalog"
    lines.append(f"🌐 [GitHub](https://github.com/{gh_repo}) | 🔗 [Website]({website_link})")
    lines.append("")

    content = "\n".join(lines)
    os.makedirs(os.path.dirname(output_md_path) or ".", exist_ok=True)
    with open(output_md_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"Successfully generated {output_md_path}")

if __name__ == "__main__":
    main()
