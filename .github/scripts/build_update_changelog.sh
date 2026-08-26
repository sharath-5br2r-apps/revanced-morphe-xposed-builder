#!/bin/bash
set -euo pipefail

cp -f build.tmp build.md 2>/dev/null || touch build.md

get_update_json() {
  echo "{
  \"version\": \"$1\",
  \"versionCode\": $NEXT_VER_CODE,
  \"zipUrl\": \"$2\",
  \"changelog\": \"$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/download/update/build.md\"
}"
}

# Check build/ directory first, or fallback to final_build/ or current directory
BUILD_DIR_TARGET="build"
if [ ! -d "$BUILD_DIR_TARGET" ]; then
  if [ -d "final_build" ]; then
    BUILD_DIR_TARGET="final_build"
  else
    BUILD_DIR_TARGET="."
  fi
fi

echo "[+] Generating module update JSONs from directory: '$BUILD_DIR_TARGET'..."
cd "$BUILD_DIR_TARGET"
for OUTPUT in *module*.zip; do
  [ "$OUTPUT" = "*module*.zip" ] && continue
  ZIP_S=$(unzip -p "$OUTPUT" module.prop 2>/dev/null || true)
  if [ -z "$ZIP_S" ]; then continue; fi
  if ! UPDATE_JSON=$(echo "$ZIP_S" | grep updateJson || true); then continue; fi
  if [ -z "$UPDATE_JSON" ]; then continue; fi
  UPDATE_JSON="${UPDATE_JSON##*/}"
  VER=$(echo "$ZIP_S" | grep version= || true)
  VER="${VER##*=}"
  DLURL="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/releases/download/$NEXT_VER_CODE/${OUTPUT}"
  get_update_json "$VER" "$DLURL" >"../$UPDATE_JSON"
done
cd - >/dev/null
