#!/usr/bin/env bash
set -euo pipefail

# Set local fallback for GITHUB_OUTPUT if not set
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-/tmp/github_output.env}"
> "$GITHUB_OUTPUT"

echo "=== Running 1: ci_ensure_patch_sources.sh ==="
bash .github/scripts/ci_ensure_patch_sources.sh
cat "$GITHUB_OUTPUT"

echo "=== Running 2: ci_fetch_tags.sh ==="
bash .github/scripts/ci_fetch_tags.sh

echo "=== Running 3: ci_compare_tags.sh ==="
bash .github/scripts/ci_compare_tags.sh
cat "$GITHUB_OUTPUT"

echo "=== Running 4: ci_fetch_app_versions.sh ==="
bash .github/scripts/ci_fetch_app_versions.sh

echo "=== Running 5: ci_compare_app_versions.sh ==="
bash .github/scripts/ci_compare_app_versions.sh
cat "$GITHUB_OUTPUT"

echo "=== Running 6: ci_generate_configs.sh ==="
TRIGGER_STABLE=$(grep "^TRIGGER_STABLE=" "$GITHUB_OUTPUT" | tail -n1 | cut -d= -f2 || echo 0)
TRIGGER_PRERELEASE=$(grep "^TRIGGER_PRERELEASE=" "$GITHUB_OUTPUT" | tail -n1 | cut -d= -f2 || echo 0)
TRIGGER_APP_UPDATE=$(grep "^TRIGGER_APP_UPDATE=" "$GITHUB_OUTPUT" | tail -n1 | cut -d= -f2 || echo 0)

export TRIGGER_STABLE TRIGGER_PRERELEASE TRIGGER_APP_UPDATE
bash .github/scripts/ci_generate_configs.sh

echo "=== Running 7: ci_resolve_triggers.sh ==="
RAW_TRIGGER_STABLE="$TRIGGER_STABLE"
RAW_TRIGGER_PRERELEASE="$TRIGGER_PRERELEASE"
RAW_TRIGGER_APP_UPDATE="$TRIGGER_APP_UPDATE"
CREATED=$(grep "^created=" "$GITHUB_OUTPUT" | tail -n1 | cut -d= -f2 || echo false)

export RAW_TRIGGER_STABLE RAW_TRIGGER_PRERELEASE RAW_TRIGGER_APP_UPDATE CREATED
bash .github/scripts/ci_resolve_triggers.sh

echo ""
echo "=========================================="
echo "      FINAL GITHUB_OUTPUT FILE CONTENT    "
echo "=========================================="
cat "$GITHUB_OUTPUT"
