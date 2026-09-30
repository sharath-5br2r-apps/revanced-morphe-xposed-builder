#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT_DIR"

# Check out state/app_versions.json from origin/data if available
if git rev-parse --verify origin/data >/dev/null 2>&1 || git fetch -q origin data 2>/dev/null; then
    mkdir -p state
    git checkout -q origin/data -- state/app_versions.json 2>/dev/null || true
    git reset -q -- state/app_versions.json 2>/dev/null || true
    if [ -f "state/app_versions.json" ]; then
        echo "Checked out state/app_versions.json from data branch."
    fi
fi

exec bash "$ROOT_DIR/.github/scripts/ci_fetch_app_versions.sh" "$@"
