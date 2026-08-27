#!/bin/bash
set -euo pipefail

[ "${DISABLE_CONFIG_UPDATE:-false}" = "true" ] && { echo "::notice::Config JSON updates disabled via option."; exit 0; }

[ -f tags_old.json ] && TAGS_OLD=$(cat tags_old.json) || TAGS_OLD='{}'
[ -f tags_new.json ] && TAGS_NEW=$(cat tags_new.json) || TAGS_NEW='{}'
[ -f active_apps.json ] || echo '[]' > active_apps.json
[ -f active_patch_apps.stable.json ] || echo '[]' > active_patch_apps.stable.json
[ -f active_patch_apps.dev.json ] || echo '[]' > active_patch_apps.dev.json

if [ "${SKIP_VERSION_CHECK:-false}" = "true" ]; then
  echo "::notice::Skipping version check / tag comparison as SKIP_VERSION_CHECK is true."
  [ -f active.stable.json ] || echo '[]' > active.stable.json
  [ -f active.prerelease.json ] || echo '[]' > active.prerelease.json
else
  jq -rn --argjson new "$TAGS_NEW" --argjson old "$TAGS_OLD" '
    [ $new | to_entries[] | . as $e
        | ($old[$e.key] // {}) as $o
        | select($e.value.stable != "" and $e.value.stable != ($o.stable // ""))
        | select($e.value.enabled != false and $e.value.enabledStable != false)
        | $e.value.repo | ascii_downcase
    ]
  ' > active.stable.json

  jq -rn --argjson new "$TAGS_NEW" --argjson old "$TAGS_OLD" '
    [ $new | to_entries[] | . as $e
        | ($old[$e.key] // {}) as $o
        | select($e.value.prerelease != "" and $e.value.prerelease != ($o.prerelease // ""))
        | select($e.value.enabled != false and $e.value.enabledDev != false)
        | select(($e.value.pre_date // "") > ($e.value.stable_date // ""))
        | $e.value.repo | ascii_downcase
    ]
  ' > active.prerelease.json
fi

split_config_json() {
  local src_json=$1
  local prefix=$2
  local max_files=${3:-5}

  # Touch all part files upfront to guarantee existence
  for idx in $(seq 1 "$max_files"); do
    local empty_file="configs/${prefix}.part${idx}.json"
    [ -f "$empty_file" ] || echo "{}" > "$empty_file"
  done

  if [ ! -s "$src_json" ]; then return 0; fi

  jq --arg prefix "$prefix" --argjson max_files "$max_files" '
    . as $root |
    to_entries | map(select(.value | type == "object" and (.value.enabled // true) != false)) as $enabled |
    ($enabled | length) as $total |
    if $total == 0 then {} else
      (if $total < $max_files then 1 else (($total / $max_files) | ceil) end) as $chunk_size |
      range(0; $max_files) as $idx |
      ($enabled[$idx * $chunk_size : ($idx + 1) * $chunk_size]) as $slice |
      {
        filename: "configs/\($prefix).part\($idx + 1).json",
        data: (
          if ($slice | length) > 0 then
            { "patches-version": ($root["patches-version"] // "latest"), "enable-module-update": ($root["enable-module-update"] // true) } +
            ($slice | from_entries)
          else {} end
        )
      }
    end
  ' "$src_json" | jq -c '.' | while IFS= read -r item; do
    [ -z "$item" ] || [ "$item" = "null" ] || [ "$item" = "{}" ] && continue
    local fname data
    fname=$(jq -r '.filename // empty' <<<"$item")
    data=$(jq '.data' <<<"$item")
    if [ -n "$fname" ] && [ "$fname" != "null" ]; then
      if [ "$data" = "{}" ]; then
        echo "{}" > "$fname"
        echo "[+] Created empty part file $fname"
      else
        echo "$data" > "$fname"
        echo "[+] Split enabled apps into $fname"
      fi
    fi
  done
}

if [ "${TRIGGER_STABLE:-0}" = "1" ] || [ "${TRIGGER_APP_UPDATE:-0}" = "1" ] || [ "${TRIGGER_BLOCKED:-0}" = "1" ] || [ "${SKIP_VERSION_CHECK:-false}" = "true" ]; then
  python3 -c "
import glob, os, tomllib, json

stable_configs = [f for f in sorted(glob.glob('configs/patches/*.toml')) if not f.endswith('.dev.toml')]
merged = {}
for f in stable_configs:
    with open(f, 'rb') as fp:
        data = tomllib.load(fp)
        for k, v in data.items():
            if isinstance(v, dict):
                merged[k] = v

with open('config.stable.json', 'w', encoding='utf-8') as out:
    json.dump(merged, out, indent=2)
"

  jq --slurpfile active active.stable.json --slurpfile activeApps active_apps.json --slurpfile activePatchApps active_patch_apps.stable.json '
    with_entries(
      if .value | type == "object" then
        .key as $k |
        .value as $app |
        (($app["patches-source"] // "morpheapp/morphe-patches") | ascii_downcase | gsub("[\"'\''\\n\\r\\t]"; " ") | split(" ") | map(select(. != ""))) as $srcs |
        if ((($srcs - $active[0]) != $srcs) and ($activePatchApps[0] | index($k))) or ($activeApps[0] | index($k)) then . else empty end
      else empty end
    ) |
    { "patches-version": "latest", "enable-module-update": true } + .
  ' config.stable.json > configs/config.stable.updated.json

  split_config_json "configs/config.stable.updated.json" "config.stable" 5
fi

if [ "${TRIGGER_PRERELEASE:-0}" = "1" ] || [ "${TRIGGER_APP_UPDATE:-0}" = "1" ] || [ "${TRIGGER_BLOCKED:-0}" = "1" ] || [ "${SKIP_VERSION_CHECK:-false}" = "true" ]; then
  python3 -c "
import glob, os, tomllib, json

dev_configs = [f for f in sorted(glob.glob('configs/patches/*.toml')) if not f.endswith('.stable.toml')]
merged = {}
for f in dev_configs:
    with open(f, 'rb') as fp:
        data = tomllib.load(fp)
        for k, v in data.items():
            if isinstance(v, dict):
                merged[k] = v

with open('config.dev.json', 'w', encoding='utf-8') as out:
    json.dump(merged, out, indent=2)
"

  jq --slurpfile active active.prerelease.json --slurpfile activePatchApps active_patch_apps.dev.json '
    with_entries(
      if .value | type == "object" then
        .key as $k |
        .value as $app |
        (($app["patches-source"] // "morpheapp/morphe-patches") | ascii_downcase | gsub("[\"'\''\\n\\r\\t]"; " ") | split(" ") | map(select(. != ""))) as $srcs |
        if (($srcs - $active[0]) != $srcs) and ($activePatchApps[0] | index($k)) then . else empty end
      else empty end
    ) |
    { "patches-version": "dev", "enable-module-update": false } + .
  ' config.dev.json > configs/config.dev.updated.json

  split_config_json "configs/config.dev.updated.json" "config.dev" 5
fi

if [ "${TRIGGER_STABLE:-0}" = "1" ] || [ "${TRIGGER_APP_UPDATE:-0}" = "1" ] || [ "${TRIGGER_BLOCKED:-0}" = "1" ] || [ "${SKIP_VERSION_CHECK:-false}" = "true" ]; then
  python3 -c "
import glob, os, tomllib, json

dev_configs = [f for f in sorted(glob.glob('configs/patches/*.toml')) if not f.endswith('.stable.toml')]
merged = {}
for f in dev_configs:
    with open(f, 'rb') as fp:
        data = tomllib.load(fp)
        for k, v in data.items():
            if isinstance(v, dict):
                merged[k] = v

with open('config.latest.json', 'w', encoding='utf-8') as out:
    json.dump(merged, out, indent=2)
"

  jq --slurpfile active active.stable.json --slurpfile activeApps active_apps.json --slurpfile activePatchApps active_patch_apps.stable.json '
    with_entries(
      if .value | type == "object" then
        .key as $k |
        .value as $app |
        (($app["patches-source"] // "morpheapp/morphe-patches") | ascii_downcase | gsub("[\"'\''\\n\\r\\t]"; " ") | split(" ") | map(select(. != ""))) as $srcs |
        if ((($srcs - $active[0]) != $srcs) and ($activePatchApps[0] | index($k))) or ($activeApps[0] | index($k)) then . else empty end
      else empty end
    ) |
    { "patches-version": "latest", "enable-module-update": false } + .
  ' config.latest.json > configs/config.latest.updated.json

  split_config_json "configs/config.latest.updated.json" "config.latest" 5
fi
