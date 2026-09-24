#!/bin/bash
set -euo pipefail

# Check if any module zip was actually built
shopt -s nullglob
MODULES=(build/*module*.zip)
shopt -u nullglob

if [ ${#MODULES[@]} -eq 0 ]; then
  echo "No modules produced in this build. Skipping module update file generation."
  [ -n "${GITHUB_OUTPUT-}" ] && echo "has_modules=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

[ -n "${GITHUB_OUTPUT-}" ] && echo "has_modules=true" >> "$GITHUB_OUTPUT"

get_update_json() {
  echo "{
  \"version\": \"$1\",
  \"versionCode\": $NEXT_VER_CODE,
  \"zipUrl\": \"$2\",
  \"changelog\": \"https://raw.githubusercontent.com/$GITHUB_REPOSITORY/update/changelogs/$NEXT_VER_CODE.md\"
}"
}

# Stage *-update.json files in temp/update-files/ rather than committing them
# directly from each parallel build job.  The aggregation jobs (aggregate_dev_logs,
# aggregate_stable_logs, etc.) collect every part's files and do one atomic commit
# to the update branch, preventing push-race failures.
UPDATE_OUT="temp/update-files"
mkdir -p "$UPDATE_OUT"

cd build || { echo "build folder not found"; exit 1; }
for OUTPUT in *module*.zip; do
  [ "$OUTPUT" = "*module*.zip" ] && continue
  ZIP_S=$(unzip -p "$OUTPUT" module.prop)
  UPDATE_JSON=$(echo "$ZIP_S" | grep updateJson || true)
  [ -z "$UPDATE_JSON" ] && continue
  UPDATE_JSON="${UPDATE_JSON##*/}"
  VER=$(echo "$ZIP_S" | grep 'version=' | head -1)
  VER="${VER##*=}"
  DLURL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/download/$ARCHIVE_TAG/${OUTPUT}"
  get_update_json "$VER" "$DLURL" > "../${UPDATE_OUT}/${UPDATE_JSON}"
  echo "Generated ${UPDATE_OUT}/${UPDATE_JSON}"
done
