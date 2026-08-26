#!/bin/bash
set -euo pipefail

USAGE="Usage: $0 [update-versions|manual] [latest|auto|absolutelatest]"

MODE="${1:-}"
PATCHES_VER="${2:-latest}"

if [ -z "$MODE" ]; then
    echo "$USAGE"
    echo ""
    echo "Modes:"
    echo "  update-versions  Trigger 'CI / Update Versions' once with skip_build=true and wait for completion"
    echo "  manual           Trigger 'Manual CI' for each TOML file found and wait for each run to complete"
    exit 1
fi

wait_for_workflow_run() {
    local workflow_file=$1
    local run_id=""
    
    echo "[+] Waiting for workflow run to start..."
    for i in {1..15}; do
        sleep 3
        run_id=$(gh run list --workflow="$workflow_file" --limit 1 --json databaseId,status --jq '.[0].databaseId' || true)
        if [ -n "$run_id" ]; then
            break
        fi
    done

    if [ -n "$run_id" ]; then
        echo "[+] Watching workflow run ID: $run_id..."
        gh run watch "$run_id" --exit-status || echo "[-] Run $run_id finished with non-zero status"
    else
        echo "[-] Could not detect active run ID for $workflow_file"
    fi
}

mapfile -t TOML_FILES < <(find configs/patches -type f -name "*.toml" | sort)

if [ ${#TOML_FILES[@]} -eq 0 ]; then
    echo "[-] No TOML files found matching configs/patches/*.toml"
    exit 1
fi

echo "[+] Found ${#TOML_FILES[@]} patch config files under configs/patches/"

if [ "$MODE" = "update-versions" ]; then
    echo "[+] Dispatching CI / Update Versions (skip_build=true)..."
    gh workflow run ci.yml -f skip_build=true
    wait_for_workflow_run "ci.yml"
elif [ "$MODE" = "manual" ]; then
    for file in "${TOML_FILES[@]}"; do
        filename=$(basename "$file")
        config_name="${filename%.toml}"
        echo "[+] Dispatching Manual CI for '$config_name' (patches_version: $PATCHES_VER)..."
        gh workflow run manual-ci.yml -f manual_config_file="$config_name" -f patches_version="$PATCHES_VER"
        wait_for_workflow_run "manual-ci.yml"
    done
else
    echo "[-] Invalid mode: $MODE"
    echo "$USAGE"
    exit 1
fi

echo "[+] Dispatch and execution completed!"
