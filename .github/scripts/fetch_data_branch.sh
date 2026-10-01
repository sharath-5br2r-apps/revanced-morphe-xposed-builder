#!/bin/bash
set -euo pipefail

# Materialize configs and state into the working tree.
# Default target branch is `data`, but can be overridden (e.g. `main` or custom)
# via first positional parameter or CONFIG_BRANCH env var.


TARGET_BRANCH="${1:-${CONFIG_BRANCH:-data}}"

if [ "$TARGET_BRANCH" = "main" ] || [ "$TARGET_BRANCH" = "HEAD" ]; then
	echo "Using configs from local checkout ($TARGET_BRANCH) — skipping fetch_data_branch."
	exit 0
fi

if ! git fetch -q origin "$TARGET_BRANCH"; then
	echo "FATAL: '$TARGET_BRANCH' branch not found on origin." >&2
	exit 1
fi

# Fetch state/ if present
STATE_LIST=$(git ls-tree --name-only -r FETCH_HEAD state/ 2>/dev/null || true)
if [ -n "$STATE_LIST" ]; then
	git checkout -q FETCH_HEAD -- state/ 2>/dev/null || true
	git reset -q -- $STATE_LIST 2>/dev/null || true
fi

# Fetch configs/ from the branch
CONFIGS_LIST=$(git ls-tree --name-only -r FETCH_HEAD configs/ 2>/dev/null || true)
if [ -n "$CONFIGS_LIST" ]; then
	git checkout -q FETCH_HEAD -- configs/ 2>/dev/null || true
	git reset -q -- $CONFIGS_LIST 2>/dev/null || true

	# Restore on-tree configs/patches from HEAD so configs/patches stays clean
	if git ls-tree -d HEAD configs/patches >/dev/null 2>&1; then
		git checkout -q HEAD -- configs/patches/ 2>/dev/null || true
	fi
fi

echo "Materialized $TARGET_BRANCH@$(git rev-parse --short FETCH_HEAD) (configs/ and state/ populated)"

