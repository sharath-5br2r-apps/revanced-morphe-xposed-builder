#!/usr/bin/env python3
"""Convert the builder's raw build.json into the unified filename-keyed manifest.

The numbered release gets this file uploaded as build.json, and the archive
releases (stable/beta) get a cumulative merge of it (see merge_archive_manifest.sh).
Schema matches .github/scripts/backfill_manifests.py output (schema version 1).

Env:
    NEXT_VER_CODE   release tag / build number (required)
    IS_PRERELEASE   true -> beta channel, else stable
Writes:
    temp/manifest/build.json
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from naming import extract_arch, normalize_arch, normalize_key, parse_patch_info  # noqa: E402


def main():
    next_ver_code = os.environ.get("NEXT_VER_CODE", "").strip()
    if not next_ver_code:
        print("Error: NEXT_VER_CODE not set.", file=sys.stderr)
        sys.exit(1)
    is_prerelease = os.environ.get("IS_PRERELEASE", "false").lower() == "true"
    channel = "beta" if is_prerelease else "stable"
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    build_json_file = Path("build.json")
    if not build_json_file.exists():
        print("[manifest] ERROR: build.json is missing; writing an empty manifest.", file=sys.stderr)
        build_info = {}
    else:
        with open(build_json_file, encoding="utf-8") as f:
            build_info = json.load(f)

    build_dir = Path("build")
    built_files = [f for f in build_dir.iterdir() if f.is_file()] if build_dir.exists() else []
    manifest_only = os.environ.get("MANIFEST_ONLY", "false").lower() == "true"

    files = {}
    skipped_targets = 0
    for target_key, info in build_info.items():
        if not isinstance(info, dict):
            print(f"[manifest] WARNING: skipping {target_key}: entry is not an object.", file=sys.stderr)
            continue
        file_prefix = info.get("name") or target_key
        assets = info.get("assets") or []
        assets_by_name = {
            asset.get("name"): asset
            for asset in assets
            if isinstance(asset, dict) and asset.get("name")
        }
        if assets_by_name:
            if manifest_only:
                # Aggregate jobs do not download the APKs. Use the exact asset
                # names recorded by the regular build.json from each build job.
                matching_files = [Path(name) for name in assets_by_name]
            else:
                matching_files = [f for f in built_files if f.name in assets_by_name]
        else:
            # Compatibility with older raw build.json files that had no assets.
            prefix_lower = file_prefix.lower()
            matching_files = [
                f for f in built_files
                if f.name.lower().startswith(prefix_lower + "-v")
                or f.name.lower().startswith(prefix_lower + "-module-")
            ]
        if not matching_files:
            skipped_targets += 1
            print(
                f"[manifest] WARNING: no built file matched {target_key}; "
                f"expected assets: {', '.join(assets_by_name) or '(prefix fallback)'}",
                file=sys.stderr,
            )
            continue

        app_name = (info.get("display_name") or target_key).strip()
        app_key = normalize_key(app_name) or normalize_key(target_key)

        brand_cfg = (info.get("patch_brand") or "").strip()
        if brand_cfg:
            brand_key, brand_name = normalize_key(brand_cfg), brand_cfg
        else:
            brand_key, brand_name = parse_patch_info(info.get("patches_source"), info.get("patches"))

        variant_cfg = (info.get("variant") or "").strip()
        variant_val = variant_cfg if (variant_cfg and variant_cfg.lower() != "default") else None
        sub_variant_cfg = (info.get("sub_variant") or "").strip()
        sub_variant_val = sub_variant_cfg if sub_variant_cfg else None
        version = info.get("version", "")
        patches_ref = (info.get("patches") or "").strip()
        changelog_url = (info.get("changelog") or "").strip()
        changelog_urls = info.get("changelog_urls") or (changelog_url.split() if changelog_url else [])
        raw_changelogs = info.get("changelogs") or []

        for f in matching_files:
            fname = f.name
            asset = assets_by_name.get(fname, {})
            lower = fname.lower()
            if not any(lower.endswith(ext) for ext in (".apk", ".apkm", ".xapk", ".apks", ".zip")):
                print(f"[manifest] WARNING: skipping unsupported output {fname}", file=sys.stderr)
                continue
            if not asset:
                print(f"[manifest] WARNING: {fname} matched by prefix fallback; asset metadata is unavailable.", file=sys.stderr)
            files[fname] = {
                "name": file_prefix,
                "version": version,
                "appKey": app_key,
                "appName": app_name,
                "arch": normalize_arch(asset.get("arch") or extract_arch(fname, version)),
                "fileType": "APK" if any(lower.endswith(ext) for ext in (".apk", ".apkm", ".xapk", ".apks")) else "Module",
                "brandKey": brand_key,
                "brandName": brand_name,
                "variant": variant_val,
                "subVariant": sub_variant_val,
                "packageName": (info.get("package_name") or info.get("pkgname") or "").strip() or None,
                "cli": info.get("cli") or None,
                "patches": patches_ref or None,
                "patchesSource": info.get("patches_source") or None,
                "engineBrand": info.get("engine_brand") or None,
                "patchBrand": info.get("patch_brand") or None,
                "densities": asset.get("densities") or [],
                "nativeLibraries": asset.get("native_libraries") or [],
                "minSdk": asset.get("min_sdk") or None,
                "versionCode": asset.get("version_code") or None,
                "patchSources": patches_ref.split() if patches_ref else [],
                "changelogUrls": changelog_urls,
                "changelogs": raw_changelogs,
                # Patch/build inspection data belongs to the matching asset;
                # never inherit it from the app-level build object.
                "appliedPatches": asset.get("appliedPatches") or [],
                "skippedPatches": asset.get("skippedPatches") or [],
                "failedPatches": asset.get("failedPatches") or [],
                "originBuild": next_ver_code,
                "publishedAt": now_iso,
            }

    manifest = {
        "schema": 1,
        "kind": "build",
        "meta": {"build": next_ver_code, "channel": channel, "publishedAt": now_iso},
        "files": files,
    }

    out_dir = Path("temp/manifest")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "build.json"
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, separators=(",", ":"))
    print(
        f"Wrote {out_path} with {len(files)} file entries "
        f"(build {next_ver_code}, channel {channel}, skipped targets {skipped_targets})."
    )


if __name__ == "__main__":
    main()
