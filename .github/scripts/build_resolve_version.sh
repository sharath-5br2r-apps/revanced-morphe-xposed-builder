#!/bin/bash
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-github_output.env}"
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-$1}"
DATE_PREFIX=$(date -u +"%Y.%m.%d")

# Fetch all matching tags for today's date prefix
TAGS=$( { gh api "repos/${REPO}/git/matching-refs/tags/${DATE_PREFIX}-" 2>/dev/null || true; } | jq -r '.[].ref // empty' | sed 's#refs/tags/##' )

HIGHEST_REV=$(echo "$TAGS" | awk -F'-' -v prefix="$DATE_PREFIX" '
  $0 ~ "^" prefix "-[0-9]+$" {
    n = $NF + 0
    if (n > max) max = n
  }
  END { print (max ? max : 0) }
')

NEXT_REV=$((HIGHEST_REV + 1))
NEXT_VER_CODE="${DATE_PREFIX}-${NEXT_REV}"
RELEASE_TITLE_BASE="Build ${DATE_PREFIX} (revision ${NEXT_REV})"

echo "NEXT_VER_CODE=$NEXT_VER_CODE" >> "$GITHUB_OUTPUT"
echo "RELEASE_TITLE_BASE=$RELEASE_TITLE_BASE" >> "$GITHUB_OUTPUT"
echo "[+] Resolved version tag: $NEXT_VER_CODE"
echo "[+] Resolved title base: $RELEASE_TITLE_BASE"
