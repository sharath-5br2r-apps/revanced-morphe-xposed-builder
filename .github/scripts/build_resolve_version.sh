#!/bin/bash
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-github_output.env}"
set -euo pipefail

YEAR=$(date -u +"%y")
TAG=$( { gh api "repos/${GITHUB_REPOSITORY:-$1}/git/matching-refs/tags/" 2>/dev/null || true; } | jq -r '.[].ref // empty' | sed 's#refs/tags/##' | awk -v year="$YEAR" '$1 ~ "^" year "[0-9][0-9][0-9][0-9]$" {print $1}' | sort -nr | head -n1 )

if [ -n "$TAG" ]; then
    BUILD_COUNT=${TAG:2:4}
    BUILD_COUNT=$((10#$BUILD_COUNT + 1))
else
    BUILD_COUNT=1
fi

NEXT_VER_CODE=$(printf "%s%04d" "$YEAR" "$BUILD_COUNT")
echo "NEXT_VER_CODE=$NEXT_VER_CODE" >> "$GITHUB_OUTPUT"
