#!/bin/bash
set -euo pipefail

FLAVOR="${1:-stable}" # dev or stable

echo "[+] Aggregating build logs for flavor: $FLAVOR"

aggregated_json="aggregated_out/build.${FLAVOR}.json"
aggregated_md="aggregated_out/build.${FLAVOR}.md"

mkdir -p aggregated_out
echo "{}" > "$aggregated_json"
> "$aggregated_md"

# Collect all downloaded part-logs
for json_file in $(find . -name "build.json" 2>/dev/null); do
  if [ -s "$json_file" ]; then
    echo "[+] Merging $json_file into $aggregated_json"
    tmp_merged=$(mktemp)
    jq -s '.[0] * .[1]' "$aggregated_json" "$json_file" > "$tmp_merged"
    mv "$tmp_merged" "$aggregated_json"
  fi
done

for md_file in $(find . -name "build.md" -o -name "build.tmp" 2>/dev/null); do
  if [ -s "$md_file" ]; then
    echo "[+] Appending $md_file into $aggregated_md"
    cat "$md_file" >> "$aggregated_md"
    echo "" >> "$aggregated_md"
  fi
done

if [ -s "$aggregated_md" ]; then
  echo "[+] Aggregated changelog size: $(wc -c < "$aggregated_md") bytes"
fi

if [ -s "$aggregated_json" ]; then
  echo "[+] Aggregated build.json entries count: $(jq 'keys | length' "$aggregated_json")"
fi
