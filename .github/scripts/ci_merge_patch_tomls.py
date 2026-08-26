import os
import glob
import re

def get_tables_with_headers(filepath):
    tables = []
    current_lines = []
    header_comment = []
    with open(filepath, "r", encoding="utf-8") as f:
        for line in f:
            if line.startswith('['):
                if current_lines:
                    tables.append((''.join(header_comment), ''.join(current_lines)))
                    current_lines = []
                    header_comment = []
                current_lines.append(line)
            else:
                if not current_lines and (line.startswith('#') or not line.strip()):
                    header_comment.append(line)
                else:
                    current_lines.append(line)
        if current_lines:
            tables.append((''.join(header_comment), ''.join(current_lines)))
    return tables

def main():
    base = "configs/patches"
    merged_dir = os.path.join(base, "merged")
    
    # Remove old merged files
    for old_f in glob.glob(os.path.join(merged_dir, "*.toml")):
        os.remove(old_f)
    os.makedirs(merged_dir, exist_ok=True)

    toml_files = sorted(glob.glob(os.path.join(base, "*.toml")))

    matrix_jobs = []

    for fpath in toml_files:
        fname = os.path.basename(fpath)
        patchset_name = fname.replace(".toml", "")
        tables = get_tables_with_headers(fpath)
        
        # Split tables of this patchset into chunks of max 6 apps
        for i in range(0, len(tables), 6):
            chunk_tables = tables[i:i+6]
            part_num = (i // 6) + 1
            total_parts = ((len(tables) - 1) // 6) + 1
            
            if total_parts > 1:
                chunk_name = f"{patchset_name}-part{part_num}.toml"
                job_id = f"build_{patchset_name.replace('-', '_')}_part{part_num}"
            else:
                chunk_name = f"{patchset_name}.toml"
                job_id = f"build_{patchset_name.replace('-', '_')}"
                
            out_file = os.path.join(merged_dir, chunk_name)
            
            content = [f"# --- Patchset: {patchset_name} (Part {part_num}/{total_parts}) ---\n"]
            for header, tbl in chunk_tables:
                if header:
                    content.append(header)
                content.append(tbl)
                
            with open(out_file, "w", encoding="utf-8") as out_fp:
                out_fp.write("\n\n".join(content) + "\n")
            
            matrix_jobs.append((job_id, f"configs/patches/merged/{chunk_name}"))
            print(f"[+] Created normalized chunk '{chunk_name}' with {len(chunk_tables)} apps")

    generate_workflow_yaml(matrix_jobs)

def generate_workflow_yaml(jobs):
    job_blocks = []
    job_ids = []
    for job_id, config_file in jobs:
        job_ids.append(job_id)
        block = f"""  {job_id}:
    needs: update_versions
    if: ${{{{ always() && needs.update_versions.result == 'success' }}}}
    uses: ./.github/workflows/build.yml
    with:
      config_file: "{config_file}"
      patches_version: ${{{{ inputs.patches_version }}}}
      artifact_mode: ${{{{ inputs.artifact_mode }}}}
    secrets: inherit"""
        job_blocks.append(block)

    needs_list = "\n".join([f"      - {jid}" for jid in job_ids])
    
    yaml_content = f"""name: "Batch Build All Configs"

on:
  workflow_dispatch:
    inputs:
      patches_version:
        description: "Select patches-version override (latest, auto, or absolutelatest)"
        required: true
        type: choice
        default: "latest"
        options:
          - "latest"
          - "auto"
          - "absolutelatest"
      artifact_mode:
        description: "Use artifact mode (build as artifacts first, then aggregate build.json & release at end)"
        required: false
        type: boolean
        default: true

concurrency:
  group: batch-build
  cancel-in-progress: false

jobs:
  update_versions:
    permissions:
      contents: write
    runs-on: ubuntu-latest
    timeout-minutes: 20
    env:
      TRAWL_URL: "http://localhost:8191"
      CFB_URL: "http://localhost:8000"
    services:
      redis:
        image: redis:alpine
        ports:
          - 6379:6379
      trawl:
        image: ghcr.io/germondai/trawl:latest
        ports:
          - 8191:8191
        env:
          REDIS_URL: redis://redis:6379
        options: --shm-size=1gb
      cfb:
        image: ghcr.io/sarperavci/cloudflarebypassforscraping:latest
        ports:
          - 8000:8000
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          ref: main
          fetch-depth: 1

      - name: Ensure patch_sources.json exists
        id: ensure_patch_sources
        run: bash .github/scripts/ci_ensure_patch_sources.sh

      - name: Commit dummy patch_sources.json if created
        if: steps.ensure_patch_sources.outputs.created == 'true'
        uses: stefanzweifel/git-auto-commit-action@v7
        with:
          branch: main
          skip_checkout: true
          file_pattern: configs/patch_sources.json
          commit_message: "Create dummy patch_sources.json"

      - name: Fetch latest tags
        if: steps.ensure_patch_sources.outputs.created == 'false'
        id: fetch_tags
        env:
          GH_TOKEN: ${{{{ secrets.PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}}}
        run: bash .github/scripts/ci_fetch_tags.sh

      - name: Compare latest vs stored tags
        if: steps.ensure_patch_sources.outputs.created == 'false'
        id: compare
        env:
          LATEST_TAGS: ${{{{ steps.fetch_tags.outputs.latest }}}}
        run: bash .github/scripts/ci_compare_tags.sh

      - name: Fetch App Versions
        if: steps.ensure_patch_sources.outputs.created == 'false'
        id: fetch_app_versions
        run: bash .github/scripts/ci_fetch_app_versions.sh

      - name: Compare App Versions
        if: steps.ensure_patch_sources.outputs.created == 'false'
        id: compare_apps
        env:
          FETCHED_APP_VERSIONS: ${{{{ steps.fetch_app_versions.outputs.fetched }}}}
        run: bash .github/scripts/ci_compare_app_versions.sh

      - name: Generate configs (JSON)
        if: ${{{{ steps.ensure_patch_sources.outputs.created == 'false' && (steps.compare.outputs.TRIGGER_STABLE == '1' || steps.compare.outputs.TRIGGER_PRERELEASE == '1' || steps.compare.outputs.TRIGGER_BLOCKED == '1' || steps.compare_apps.outputs.TRIGGER_APP_UPDATE == '1') }}}}
        id: generate_configs
        env:
          TAGS_OLD: ${{{{ steps.compare.outputs.tags_old }}}}
          TAGS_NEW: ${{{{ steps.compare.outputs.tags_new }}}}
          TRIGGER_STABLE: ${{{{ steps.compare.outputs.TRIGGER_STABLE }}}}
          TRIGGER_PRERELEASE: ${{{{ steps.compare.outputs.TRIGGER_PRERELEASE }}}}
          TRIGGER_APP_UPDATE: ${{{{ steps.compare_apps.outputs.TRIGGER_APP_UPDATE }}}}
          DISABLE_CONFIG_UPDATE: "false"
        run: bash .github/scripts/ci_generate_configs.sh

      - name: Generate normalized patch TOML configs
        run: python3 .github/scripts/ci_merge_patch_tomls.py

      - name: Commit updated patch sources, configs and normalized TOMLs
        if: ${{{{ steps.ensure_patch_sources.outputs.created == 'false' && (steps.compare.outputs.TRIGGER_STABLE == '1' || steps.compare.outputs.TRIGGER_PRERELEASE == '1' || steps.compare.outputs.TRIGGER_BLOCKED == '1' || steps.compare_apps.outputs.TRIGGER_APP_UPDATE == '1') }}}}
        uses: stefanzweifel/git-auto-commit-action@v7
        with:
          branch: main
          skip_checkout: true
          file_pattern: configs/*.json configs/patches/merged/*.toml
          commit_message: "Update patch sources, app versions, generated configs and normalized TOMLs [skip ci]"

{"\n\n".join(job_blocks)}

  aggregate_and_release:
    needs:
      - update_versions
{needs_list}
    if: ${{{{ always() && inputs.artifact_mode == true }}}}
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - name: Checkout
        uses: actions/checkout@v7
        with:
          ref: main

      - name: Download all build artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts/

      - name: Consolidate build files & Merge build.json
        run: |
          mkdir -p final_build/
          find artifacts/ -type f \( -name "*.apk" -o -name "*.zip" \) -exec cp -f {{}} final_build/ \;
          python3 .github/scripts/ci_aggregate_build_json.py

      - name: Determine next release version tag
        id: version
        env:
          GH_TOKEN: ${{{{ secrets.PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}}}
        run: |
          LATEST_RELEASE=$(gh release list --limit 1 --json tagName --jq '.[0].tagName' 2>/dev/null || echo "v1.0.0")
          if [[ "$LATEST_RELEASE" =~ ^v?([0-9]+)$ ]]; then
            VER_NUM="${{BASH_REMATCH[1]}}"
            NEXT_VER=$((VER_NUM + 1))
          else
            NEXT_VER="1"
          fi
          echo "NEXT_VER_CODE=$NEXT_VER" >> "$GITHUB_OUTPUT"

      - name: Upload to Release
        uses: softprops/action-gh-release@v3
        with:
          token: ${{{{ secrets.PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}}}
          files: final_build/*
          name: Build No. ${{{{ steps.version.outputs.NEXT_VER_CODE }}}}
          tag_name: ${{{{ steps.version.outputs.NEXT_VER_CODE }}}}
          overwrite_files: true

      - name: Upload aggregated build.json to release
        env:
          GH_TOKEN: ${{{{ secrets.PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}}}
        run: |
          gh release upload ${{{{ steps.version.outputs.NEXT_VER_CODE }}}} build.json \\
            --repo "$GITHUB_REPOSITORY" --clobber

      - name: Update changelog and module update files
        env:
          NEXT_VER_CODE: ${{{{ steps.version.outputs.NEXT_VER_CODE }}}}
          GITHUB_SERVER_URL: ${{{{ github.server_url }}}}
          GITHUB_REPOSITORY: ${{{{ github.repository }}}}
        run: bash .github/scripts/build_update_changelog.sh

      - name: Upload module update metadata to release (update)
        uses: softprops/action-gh-release@v3
        with:
          token: ${{{{ secrets.PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}}}
          files: |
            build.md
            *-update.json
          name: Update Metadata
          tag_name: update
          overwrite_files: true
"""
    with open(".github/workflows/batch-build.yml", "w", encoding="utf-8") as wf:
        wf.write(yaml_content)
    print(f"[+] Updated .github/workflows/batch-build.yml with {len(jobs)} normalized build jobs")

if __name__ == "__main__":
    main()
