#!/bin/bash
set -euo pipefail

# Materialize configs and state into the working tree.
# Default target branch is `data`, but can be overridden (e.g. `main` or custom)
# via first positional parameter or CONFIG_BRANCH env var.
#
# When fetching from `data`, configs/stable/, configs/beta/, and configs/batch/
# are placed into temp_configs/ as a scratch directory while keeping human configs
# and main configs intact.

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

# Fetch configs/ if present
CONFIGS_LIST=$(git ls-tree --name-only -r FETCH_HEAD configs/ 2>/dev/null || true)
if [ -n "$CONFIGS_LIST" ]; then
	git checkout -q FETCH_HEAD -- configs/ 2>/dev/null || true
	git reset -q -- $CONFIGS_LIST 2>/dev/null || true
fi

# Set up temp_configs as a scratch directory for generated pool configs from data branch
mkdir -p temp_configs
for d in stable beta batch; do
	if [ -d "configs/$d" ]; then
		rm -rf "temp_configs/$d"
		cp -r "configs/$d" "temp_configs/$d"
	fi
done

# Also support single-file configs if present on data branch
for f in configs/stable_build.json configs/beta_build.json; do
	if [ -f "$f" ]; then
		cp -f "$f" "temp_configs/"
	fi
done

echo "Materialized $TARGET_BRANCH@$(git rev-parse --short FETCH_HEAD) (temp_configs ready)"
