#!/bin/bash
set -euo pipefail

FLAVOR="${1:-manual}" # stable, dev, or manual

echo "[+] Aggregating build logs for flavor: $FLAVOR"

aggregated_json="aggregated_out/build.json"
aggregated_md="aggregated_out/build.md"
aggregated_errors="aggregated_out/error.log"

mkdir -p aggregated_out
echo "{}" > "$aggregated_json"
> "$aggregated_md"
> "$aggregated_errors"

# Collect all downloaded part-logs (support build.json directly or inside subdirectories)
for json_file in $(find . \( -name "build.json" -o -name "build*.json" \) 2>/dev/null); do
  # Avoid merging output target if running in same dir
  if [ -s "$json_file" ] && [ "${json_file#./}" != "$aggregated_json" ]; then
    echo "[+] Merging $json_file into $aggregated_json"
    if ! jq empty "$json_file" >/dev/null 2>&1; then
      echo "[-] ERROR: Invalid JSON fragment: $json_file" >&2
      jq empty "$json_file" >&2 || true
      exit 1
    fi
    tmp_merged=$(mktemp)
    jq -s '.[0] * .[1]' "$aggregated_json" "$json_file" > "$tmp_merged"
    mv "$tmp_merged" "$aggregated_json"
  fi
done

# Preserve warnings and errors emitted by each parallel build part.
while IFS= read -r error_file; do
  [ -s "$error_file" ] || continue
  {
    printf '\n===== %s =====\n' "$error_file"
    cat "$error_file"
  } >> "$aggregated_errors"
done < <(find . -type f -name error.log ! -path "./$aggregated_errors" 2>/dev/null | sort)

# Concatenate each part's Markdown using its config/artifact directory as a
# heading. This preserves the build output exactly and avoids reconstructing
# release notes from the legacy raw JSON shape.
while IFS= read -r md_file; do
  [ -s "$md_file" ] || continue
  artifact_root=$(dirname "$md_file")
  heading_file=$(find "$artifact_root" -type f -name 'config.part*.json' -print -quit 2>/dev/null || true)
  if [ -n "$heading_file" ]; then
    heading=$(basename "$heading_file")
  else
    heading=$(basename "$(dirname "$md_file")")
  fi
  {
    printf '# %s\n\n' "$heading"
    cat "$md_file"
    printf '\n\n'
  } >> "$aggregated_md"
done < <(find . -type f -name build.md ! -path "./$aggregated_md" | sort)

if [ -s "$aggregated_md" ]; then
  echo "[+] Aggregated changelog size: $(wc -c < "$aggregated_md") bytes"
fi

entries_count=$(jq 'keys | length' "$aggregated_json" 2>/dev/null || echo 0)
if [ "$entries_count" -eq 0 ]; then
  echo "[-] ERROR: No build logs or JSON entries found to aggregate! Failing step."
  exit 1
fi

echo "[+] Aggregated build.json entries count: $entries_count"
