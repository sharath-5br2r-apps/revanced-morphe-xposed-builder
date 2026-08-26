import os
import glob
import math

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
        try:
            os.remove(old_f)
        except OSError:
            pass
    os.makedirs(merged_dir, exist_ok=True)

    toml_files = sorted(glob.glob(os.path.join(base, "*.toml")))

    # Collect all (header, table_content) blocks across all patchsets
    all_tables = []
    for fpath in toml_files:
        fname = os.path.basename(fpath)
        patchset_name = fname.replace(".toml", "")
        tables = get_tables_with_headers(fpath)
        for header, content in tables:
            all_tables.append((patchset_name, header, content))

    total_apps = len(all_tables)
    NUM_OUTPUT_FILES = 15
    apps_per_file = math.ceil(total_apps / NUM_OUTPUT_FILES)

    matrix_jobs = []
    job_names = []

    for idx in range(NUM_OUTPUT_FILES):
        start_idx = idx * apps_per_file
        end_idx = min(start_idx + apps_per_file, total_apps)
        chunk_items = all_tables[start_idx:end_idx]
        
        if not chunk_items:
            continue

        chunk_name = f"batch-part{idx + 1}.toml"
        job_id = f"build_batch_part{idx + 1}"
        job_names.append(job_id)
        out_file = os.path.join(merged_dir, chunk_name)

        content = [f"# --- Batch TOML Part {idx + 1}/{NUM_OUTPUT_FILES} ({len(chunk_items)} apps) ---\n"]
        for patchset_name, header, tbl_content in chunk_items:
            if header:
                content.append(header)
            content.append(tbl_content)

        with open(out_file, "w", encoding="utf-8") as out_fp:
            out_fp.write("\n\n".join(content) + "\n")

        matrix_jobs.append((job_id, f"configs/patches/merged/{chunk_name}"))
        print(f"[+] Created '{chunk_name}' with {len(chunk_items)} apps")

    generate_workflow_yaml(matrix_jobs)

def generate_workflow_yaml(jobs):
    job_names = [j[0] for j in jobs]
    job_blocks = []
    job_ids = []
    for job_id, config_file in jobs:
        job_ids.append(job_id)
        block = f"""  {job_id}:
    needs: update_versions
    if: ${{{{ !cancelled() && needs.update_versions.result == 'success' }}}}
    uses: ./.github/workflows/build.yml
    with:
      config_file: "{config_file}"
      patches_version: ${{{{ inputs.patches_version }}}}
      release_version_code: ${{{{ needs.update_versions.outputs.NEXT_VER_CODE }}}}
      upload_release_metadata: false
    secrets: inherit"""
        job_blocks.append(block)

    yaml_content = f"""name: "Batch Build All Configs"
permissions: write-all

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

concurrency:
  group: ci
  cancel-in-progress: false

jobs:
  update_versions:
    permissions:
      contents: write
    runs-on: ubuntu-latest
    timeout-minutes: 20
    outputs:
      NEXT_VER_CODE: ${{{{ steps.version.outputs.NEXT_VER_CODE }}}}
    env:
      TRAWL_URL: "http://localhost:8191"
      CFB_URL: "http://localhost:8000"
      KEYSTORE_BASE64: ${{{{ secrets.KEYSTORE_BASE64 }}}}
      KEYSTORE_PASSWORD: ${{{{ secrets.KEYSTORE_PASSWORD }}}}
      KEYSTORE_KEY_PASSWORD: ${{{{ secrets.KEYSTORE_KEY_PASSWORD }}}}
      KEYSTORE_ALIAS: ${{{{ vars.KEYSTORE_ALIAS }}}}
    services:
      redis:
        image: redis:alpine
        ports:
          - 6379:6379
      trawl:
        image: ghcr.io/germondai/trawl:latest
        ports:
          - 8191:8191
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

      - name: Determine next release version tag
        id: version
        env:
          GH_TOKEN: ${{{{ secrets.PERSONAL_ACCESS_TOKEN || secrets.GITHUB_TOKEN }}}}
        run: bash .github/scripts/build_resolve_version.sh

      - name: Commit updated patch_sources.json and configs
        uses: stefanzweifel/git-auto-commit-action@v7
        with:
          branch: main
          file_pattern: configs/*.json
          commit_message: "Update patch sources, app versions and generated configs [skip ci]"

{"\n\n".join(job_blocks)}

  trigger_cleanup:
    needs: [{", ".join(job_names)}]
    if: ${{{{ !cancelled() }}}}
    uses: ./.github/workflows/cleanup.yml
    secrets: inherit

  trigger_website_update:
    needs: [{", ".join(job_names)}, trigger_cleanup]
    if: ${{{{ !cancelled() }}}}
    uses: ./.github/workflows/update-website.yml
    secrets: inherit
"""
    with open(".github/workflows/batch-build.yml", "w", encoding="utf-8") as wf:
        wf.write(yaml_content)
    print(f"[+] Updated .github/workflows/batch-build.yml with {len(jobs)} normalized build jobs")

if __name__ == "__main__":
    main()
