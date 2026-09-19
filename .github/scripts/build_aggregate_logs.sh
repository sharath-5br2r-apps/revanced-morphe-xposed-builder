#!/bin/bash
set -euo pipefail

FLAVOR="${1:-manual}" # stable, dev, or manual

echo "[+] Aggregating build logs for flavor: $FLAVOR"

aggregated_json="aggregated_out/build.${FLAVOR}.json"
aggregated_md="aggregated_out/build.${FLAVOR}.md"
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

# Generate normalized aggregated build.md exclusively from aggregated build.json
python3 ../.github/scripts/generate_release_notes.py "$aggregated_json" "$aggregated_md" 2>/dev/null || python3 .github/scripts/generate_release_notes.py "$aggregated_json" "$aggregated_md" || true

if [ -s "$aggregated_md" ]; then
  echo "[+] Aggregated changelog size: $(wc -c < "$aggregated_md") bytes"
fi

entries_count=$(jq 'keys | length' "$aggregated_json" 2>/dev/null || echo 0)
if [ "$entries_count" -eq 0 ]; then
  echo "[-] ERROR: No build logs or JSON entries found to aggregate! Failing step."
  exit 1
fi

echo "[+] Aggregated build.json entries count: $entries_count"
