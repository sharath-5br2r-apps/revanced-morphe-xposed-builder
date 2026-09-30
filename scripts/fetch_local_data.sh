#!/bin/bash
set -euo pipefail

# Materialize configs/ and state/ from a local Git branch (default: data)
# into the working tree for local patching and inspection.
#
# Usage:
#   bash scripts/fetch_local_data.sh [BRANCH]
#
# Defaults to branch "data".

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$ROOT_DIR"

BRANCH="${1:-data}"

if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
	echo "FATAL: local branch '$BRANCH' not found." >&2
	exit 1
fi

mkdir -p configs state

CONFIGS_LIST=$(git ls-tree --name-only -r "$BRANCH" configs/ 2>/dev/null || true)
STATE_LIST=$(git ls-tree --name-only -r "$BRANCH" state/ 2>/dev/null || true)

if [ -z "$CONFIGS_LIST" ] && [ -z "$STATE_LIST" ]; then
	echo "WARNING: neither configs/ nor state/ found on local branch '$BRANCH'."
	exit 0
fi

if [ -n "$CONFIGS_LIST" ]; then
	git checkout -q "$BRANCH" -- configs/ 2>/dev/null || true
	git reset -q -- $CONFIGS_LIST 2>/dev/null || true
fi

if [ -n "$STATE_LIST" ]; then
	git checkout -q "$BRANCH" -- state/ 2>/dev/null || true
	git reset -q -- $STATE_LIST 2>/dev/null || true
fi

echo "Materialized configs and state from local branch '$BRANCH'@$(git rev-parse --short "$BRANCH"):"
[ -n "$CONFIGS_LIST" ] && git ls-tree --name-only -r "$BRANCH" configs/ | sed 's/^/  /'
[ -n "$STATE_LIST" ] && git ls-tree --name-only -r "$BRANCH" state/ | sed 's/^/  /'
