#!/bin/bash
set -euo pipefail

echo "--- Fetching active releases ---"
ACTIVE_TAGS=$(gh release list -L 200 --json tagName -q '.[].tagName' 2>/dev/null || true)
if [ -z "$ACTIVE_TAGS" ]; then
  echo "No active releases found or gh CLI call failed. Skipping changelog release cleanup."
  exit 0
fi

echo "--- Checking update_changelog release assets for orphaned files ---"
REPO="${GITHUB_REPOSITORY:-}"
if [ -z "$REPO" ]; then
  echo "GITHUB_REPOSITORY is not set. Skipping."
  exit 0
fi

RELEASE_ID=$(gh api "repos/${REPO}/releases/tags/update_changelog" --jq .id 2>/dev/null || true)
if [ -z "$RELEASE_ID" ]; then
  echo "Release 'update_changelog' not found. Nothing to cleanup."
  exit 0
fi

# Fetch update.json assets from release 'update' to check active references
ACTIVE_UPDATE_JSON_CONTENT=""
UPDATE_RELEASE_ID=$(gh api "repos/${REPO}/releases/tags/update" --jq .id 2>/dev/null || true)
if [ -n "$UPDATE_RELEASE_ID" ]; then
  UPDATE_ASSETS=$(gh api --paginate "repos/${REPO}/releases/${UPDATE_RELEASE_ID}/assets" --jq '.[] | select(.name | endswith("-update.json")) | .id' 2>/dev/null || true)
  for aid in $UPDATE_ASSETS; do
    json_body=$(gh api -H "Accept: application/octet-stream" "repos/${REPO}/releases/assets/${aid}" 2>/dev/null || true)
    ACTIVE_UPDATE_JSON_CONTENT="${ACTIVE_UPDATE_JSON_CONTENT} ${json_body}"
  done
fi

CHANGELOG_ASSETS=$(gh api --paginate "repos/${REPO}/releases/${RELEASE_ID}/assets" --jq '.[] | {id: .id, name: .name}' 2>/dev/null || true)
if [ -z "$CHANGELOG_ASSETS" ]; then
  echo "No assets found in release 'update_changelog'."
  exit 0
fi

DELETED_COUNT=0
while read -r item; do
  [ -z "$item" ] && continue
  asset_id=$(jq -r '.id' <<<"$item")
  asset_name=$(jq -r '.name' <<<"$item")

  case "$asset_name" in
    *.md)
      tag="${asset_name%.md}"
      if ! echo "$ACTIVE_TAGS" | grep -Fxq "$tag"; then
        if echo "$ACTIVE_UPDATE_JSON_CONTENT" | grep -q "${tag}\.md"; then
          echo "Keeping changelog asset: $asset_name (release '$tag' pruned, but still referenced by an active update.json)"
          continue
        fi
        echo "Pruning orphaned changelog asset: $asset_name (id: $asset_id, release tag '$tag' no longer exists)"
        gh api -X DELETE "repos/${REPO}/releases/assets/${asset_id}" >/dev/null 2>&1 || true
        DELETED_COUNT=$((DELETED_COUNT + 1))
      fi
      ;;
  esac
done < <(gh api --paginate "repos/${REPO}/releases/${RELEASE_ID}/assets" --jq '.[] | @json' 2>/dev/null || true)

echo "Pruned $DELETED_COUNT orphaned changelog asset(s) from update_changelog release."
