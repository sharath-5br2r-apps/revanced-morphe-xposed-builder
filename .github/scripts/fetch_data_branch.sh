#!/bin/bash
set -euo pipefail

# Materialize configs and state into the working tree.
# Default target branch is `data`, but can be overridden (e.g. `main` or custom)
# via first positional parameter or CONFIG_BRANCH env var.
#
# When fetching from `data`, configs/stable/, configs/beta/, and configs/batch/
# are placed into temp_configs/ as a scratch directory, reserving configs/patches/
# and configs/*.toml for on-tree configuration.

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

# Fetch configs/ from the branch into temp_configs/
mkdir -p temp_configs
CONFIGS_LIST=$(git ls-tree --name-only -r FETCH_HEAD configs/ 2>/dev/null || true)
if [ -n "$CONFIGS_LIST" ]; then
	git checkout -q FETCH_HEAD -- configs/ 2>/dev/null || true
	git reset -q -- $CONFIGS_LIST 2>/dev/null || true

	# Route generated pool configs to temp_configs scratch directory
	for d in stable beta batch both; do
		if [ -d "configs/$d" ]; then
			rm -rf "temp_configs/$d"
			cp -r "configs/$d" "temp_configs/$d"
			rm -rf "configs/$d"
		fi
	done

	for f in configs/stable_build.json configs/beta_build.json; do
		if [ -f "$f" ]; then
			cp -f "$f" "temp_configs/"
			rm -f "$f"
		fi
	done

	# Restore on-tree configs/patches from HEAD so configs/patches stays clean
	if git ls-tree -d HEAD configs/patches >/dev/null 2>&1; then
		git checkout -q HEAD -- configs/patches/ 2>/dev/null || true
	fi
fi

echo "Materialized $TARGET_BRANCH@$(git rev-parse --short FETCH_HEAD) (temp_configs populated, configs/patches reserved for on-tree)"
