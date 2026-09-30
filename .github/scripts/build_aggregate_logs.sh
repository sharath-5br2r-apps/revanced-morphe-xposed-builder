#!/bin/bash
set -euo pipefail

FLAVOR="${1:-manual}" # stable, dev, or manual

echo "[+] Aggregating build logs for flavor: $FLAVOR"

aggregated_json="aggregated_out/build.json"
aggregated_md="aggregated_out/build.md"
aggregated_errors="aggregated_out/error.log"
aggregated_errors_json="aggregated_out/error.json"
aggregated_log_json="aggregated_out/build_log.json"
aggregated_errors_md="aggregated_out/error.md"
aggregated_files="aggregated_out/built_files.txt"

mkdir -p aggregated_out
echo "{}" > "$aggregated_json"
> "$aggregated_md"
> "$aggregated_errors"
echo "[]" > "$aggregated_errors_json"
echo "[]" > "$aggregated_log_json"
> "$aggregated_files"

# Collect all downloaded part-logs (support build.json directly or inside subdirectories)
for json_file in $(find . \( -name "build.json" -o -name "build*.json" \) ! -name "build_log.json" 2>/dev/null); do
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

# Aggregate error.json files
for ej in $(find . -type f -name "error.json" ! -path "./$aggregated_errors_json" 2>/dev/null); do
  if [ -s "$ej" ] && jq -e 'type == "array" and length > 0' "$ej" >/dev/null 2>&1; then
    tmp_merged=$(mktemp)
    jq -s '.[0] + .[1]' "$aggregated_errors_json" "$ej" > "$tmp_merged"
    mv "$tmp_merged" "$aggregated_errors_json"
  fi
done

# Aggregate build_log.json files
for bl in $(find . -type f -name "build_log.json" ! -path "./$aggregated_log_json" 2>/dev/null); do
  if [ -s "$bl" ] && jq -e 'type == "array" and length > 0' "$bl" >/dev/null 2>&1; then
    tmp_merged=$(mktemp)
    jq -s '.[0] + .[1]' "$aggregated_log_json" "$bl" > "$tmp_merged"
    mv "$tmp_merged" "$aggregated_log_json"
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

# Generate aggregated error.md from aggregated JSON logs
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
if [ -f "$ROOT_DIR/.github/scripts/generate_error_markdown.py" ]; then
  python3 "$ROOT_DIR/.github/scripts/generate_error_markdown.py" aggregated_out "$aggregated_errors_md" || true
fi

# Generate aggregated build.md directly from aggregated build.json
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
if [ -f "$ROOT_DIR/.github/scripts/generate_release_notes.py" ]; then
  echo "[+] Generating $aggregated_md from $aggregated_json"
  python3 "$ROOT_DIR/.github/scripts/generate_release_notes.py" "$aggregated_json" "$aggregated_md" || true
fi

# Fallback: if generate_release_notes did not produce build.md, concatenate part markdowns
if [ ! -s "$aggregated_md" ]; then
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
fi

if [ -s "$aggregated_md" ]; then
  echo "[+] Aggregated changelog size: $(wc -c < "$aggregated_md") bytes"
fi

# Collect all downloaded part-logs built_files.txt
while IFS= read -r f_file; do
  [ -s "$f_file" ] || continue
  cat "$f_file" >> "$aggregated_files"
done < <(find . -type f \( -name "built_files.txt" -o -name "build_files.txt" \) ! -path "./$aggregated_files" 2>/dev/null | sort -u)
sort -u "$aggregated_files" -o "$aggregated_files"

if [ -s "$aggregated_files" ]; then
  echo "[+] Aggregated built files count: $(wc -l < "$aggregated_files")"
fi

entries_count=$(jq 'keys | length' "$aggregated_json" 2>/dev/null || echo 0)
if [ "$entries_count" -eq 0 ]; then
  echo "[-] ERROR: No build logs or JSON entries found to aggregate! Failing step."
  exit 1
fi

echo "[+] Aggregated build.json entries count: $entries_count"
