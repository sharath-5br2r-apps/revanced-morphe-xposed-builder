#!/bin/bash
export GITHUB_OUTPUT="${GITHUB_OUTPUT:-github_output.env}"
set -euo pipefail
MODE="${MODE:-Default}"

if [ "${CREATED:-false}" = "true" ] || [ "${SKIP_BUILD:-false}" = "true" ] || [ "$MODE" = "Update Versions Only" ] || [ "$MODE" = "Generate Configs Only (No Build)" ]; then
  echo "TRIGGER_STABLE=0" >> "$GITHUB_OUTPUT"
  echo "TRIGGER_PRERELEASE=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

if [ "$MODE" = "Build Only" ]; then
  RAW_TRIGGER_STABLE=1
  RAW_TRIGGER_PRERELEASE=1
  RAW_TRIGGER_APP_UPDATE=1
else
  RAW_TRIGGER_STABLE=${RAW_TRIGGER_STABLE:-0}
  RAW_TRIGGER_PRERELEASE=${RAW_TRIGGER_PRERELEASE:-0}
  RAW_TRIGGER_APP_UPDATE=${RAW_TRIGGER_APP_UPDATE:-0}
fi

TRIGGER_STABLE=0
TRIGGER_PRERELEASE=0

if [ "$RAW_TRIGGER_STABLE" = "1" ] || [ "$RAW_TRIGGER_APP_UPDATE" = "1" ]; then
  CFG="configs/config.stable.updated.json"
  ENABLED_COUNT=$(jq '[.[] | objects | select(.enabled != false)] | length' "$CFG" || echo 0)
  if [ "${ENABLED_COUNT:-0}" -gt 0 ]; then
    TRIGGER_STABLE=1
  else
    echo "::notice::Stable config has 0 enabled apps. Skipping stable build."
  fi
fi

if [ "$RAW_TRIGGER_PRERELEASE" = "1" ] || [ "$RAW_TRIGGER_APP_UPDATE" = "1" ]; then
  CFG="configs/config.dev.updated.json"
  ENABLED_COUNT=$(jq '[.[] | objects | select(.enabled != false)] | length' "$CFG" || echo 0)
  if [ "${ENABLED_COUNT:-0}" -gt 0 ]; then
    TRIGGER_PRERELEASE=1
  else
    echo "::notice::Skipping dev build trigger: no enabled apps in $CFG"
  fi
fi

for i in {1..5}; do
  dev_file="configs/config.dev.part${i}.json"
  if [ -s "$dev_file" ] && [ "$(jq '[to_entries[] | select(.value | type == "object" and (.value.enabled // true) != false)] | length' "$dev_file" 2>/dev/null || echo 0)" -gt 0 ]; then
    echo "HAS_DEV_${i}=1" >> "$GITHUB_OUTPUT"
  else
    echo "HAS_DEV_${i}=0" >> "$GITHUB_OUTPUT"
  fi

  stable_file="configs/config.stable.part${i}.json"
  if [ -s "$stable_file" ] && [ "$(jq '[to_entries[] | select(.value | type == "object" and (.value.enabled // true) != false)] | length' "$stable_file" 2>/dev/null || echo 0)" -gt 0 ]; then
    echo "HAS_STABLE_${i}=1" >> "$GITHUB_OUTPUT"
  else
    echo "HAS_STABLE_${i}=0" >> "$GITHUB_OUTPUT"
  fi
done

echo "TRIGGER_STABLE=$TRIGGER_STABLE" >> "$GITHUB_OUTPUT"
echo "TRIGGER_PRERELEASE=$TRIGGER_PRERELEASE" >> "$GITHUB_OUTPUT"
