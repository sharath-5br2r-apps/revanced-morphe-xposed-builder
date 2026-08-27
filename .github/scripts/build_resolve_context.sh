#!/bin/bash
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-github_output.env}"
set -euo pipefail
CONFIG="$1"

if [ ! -f "$CONFIG" ]; then
  echo "::error::Config file not found: $CONFIG"
  exit 1
fi

echo "CONFIG_FILE=$CONFIG" >> "$GITHUB_OUTPUT"

# Count enabled apps in config file (JSON or TOML)
HAS_ENABLED=true
if [[ "$CONFIG" == *.json ]]; then
  ENABLED_COUNT=$(jq '[to_entries[] | select(.value | type == "object" and (.value.enabled // true) != false)] | length' "$CONFIG" 2>/dev/null || echo "0")
  if [ "$ENABLED_COUNT" -eq 0 ]; then
    HAS_ENABLED=false
  fi
elif [[ "$CONFIG" == *.toml ]]; then
  if ! grep -iqE '^[[:space:]]*enabled[[:space:]]*=[[:space:]]*true' "$CONFIG" && ! grep -qE '^\[.+\]' "$CONFIG"; then
    HAS_ENABLED=false
  fi
fi

echo "HAS_ENABLED_APPS=$HAS_ENABLED" >> "$GITHUB_OUTPUT"
if [ "$HAS_ENABLED" = false ]; then
  echo "::notice::No enabled apps found in config file '$CONFIG'. Skipping build steps."
fi

IS_DEV=false
P_OVERRIDE="${OVERRIDE_PATCHES_VERSION:-}"
if [ "$P_OVERRIDE" = "dev" ] || [ "$P_OVERRIDE" = "absolutelatest" ]; then
  IS_DEV=true
elif [[ "$CONFIG" == *"dev"* ]]; then
  IS_DEV=true
elif [[ "$CONFIG" == *.json ]]; then
  PVER=$(jq -r '."patches-version" // empty' "$CONFIG")
  if [ "$PVER" = "dev" ] || [ "$PVER" = "absolutelatest" ]; then
    IS_DEV=true
  fi
elif [[ "$CONFIG" == *.toml ]]; then
  if awk '/^\[/ {exit} {print}' "$CONFIG" | grep -qE '^[[:space:]]*patches-version[[:space:]]*=[[:space:]]*"?(dev|absolutelatest)"?'; then
    IS_DEV=true
  fi
fi

CONFIG_BASE=$(basename "$CONFIG")
CONFIG_TAG="${CONFIG_BASE%.*}"
CONFIG_TAG="${CONFIG_TAG//./-}"
echo "CONFIG_TAG=$CONFIG_TAG" >> "$GITHUB_OUTPUT"

if [ "$IS_DEV" = true ]; then
  echo "IS_PRERELEASE=true" >> "$GITHUB_OUTPUT"
  echo "TG_THREAD_ID=350" >> "$GITHUB_OUTPUT"
  echo "TITLE_SUFFIX= (Pre-release)" >> "$GITHUB_OUTPUT"
  echo "ARCHIVE_TAG=beta" >> "$GITHUB_OUTPUT"
else
  echo "IS_PRERELEASE=false" >> "$GITHUB_OUTPUT"
  echo "TG_THREAD_ID=262" >> "$GITHUB_OUTPUT"
  echo "TITLE_SUFFIX=" >> "$GITHUB_OUTPUT"
  echo "ARCHIVE_TAG=stable" >> "$GITHUB_OUTPUT"
fi
