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
  local min_apps=${4:-3}

  if [ ! -s "$src_json" ]; then return 0; fi

  jq --arg prefix "$prefix" --argjson max_files "$max_files" --argjson min_apps "$min_apps" '
    to_entries | map(select(.value | type == "object" and (.value.enabled // true) != false)) as $enabled |
    ($enabled | length) as $total |
    if $total == 0 then {} else
      (($total / $max_files) | ceil | if . < $min_apps then $min_apps else . end) as $chunk_size |
      range(0; $max_files) as $idx |
      ($enabled[$idx * $chunk_size : ($idx + 1) * $chunk_size]) as $slice |
      select(($slice | length) >= $min_apps or ($idx == 0 and ($slice | length) > 0)) |
      {
        filename: "configs/\($prefix).part\($idx + 1).json",
        data: (
          { "patches-version": (.[ "patches-version" ] // "latest"), "enable-module-update": (.[ "enable-module-update" ] // true) } +
          ($slice | from_entries)
        )
      }
    end
  ' "$src_json" | jq -c '.' | while IFS= read -r item; do
    [ -z "$item" ] && continue
    local fname
    fname=$(jq -r '.filename' <<<"$item")
    jq '.data' <<<"$item" > "$fname"
    echo "[+] Split enabled apps into $fname"
  done
}

if [ "${TRIGGER_STABLE:-0}" = "1" ] || [ "${TRIGGER_APP_UPDATE:-0}" = "1" ] || [ "${TRIGGER_BLOCKED:-0}" = "1" ] || [ "${SKIP_VERSION_CHECK:-false}" = "true" ]; then
  STABLE_CONFIGS=$(find configs/patches -name "*.toml" ! -name "*.dev.toml" 2>/dev/null | sort -u)
  if [ -n "$STABLE_CONFIGS" ]; then
    # shellcheck disable=SC2086
    yq -o=json eval-all '. as $item ireduce ({}; . * $item)' $STABLE_CONFIGS > config.stable.json
  else
    echo "{}" > config.stable.json
  fi

  jq --slurpfile active active.stable.json --slurpfile activeApps active_apps.json --slurpfile activePatchApps active_patch_apps.stable.json '
    { "patches-version": "latest", "enable-module-update": true } as $force |
    ($force + . + $force) |
    with_entries(
      if .value | type == "object" then
        .key as $k |
        .value as $app |
        (($app["patches-source"] // "morpheapp/morphe-patches") | ascii_downcase | gsub("[\"'\''\\n\\r\\t]"; " ") | split(" ") | map(select(. != ""))) as $srcs |
        if ((($srcs - $active[0]) != $srcs) and ($activePatchApps[0] | index($k))) or ($activeApps[0] | index($k)) then . else empty end
      else . end
    )
  ' config.stable.json > configs/config.stable.updated.json

  split_config_json "configs/config.stable.updated.json" "config.stable" 5 3
fi

if [ "${TRIGGER_PRERELEASE:-0}" = "1" ] || [ "${TRIGGER_APP_UPDATE:-0}" = "1" ] || [ "${TRIGGER_BLOCKED:-0}" = "1" ] || [ "${SKIP_VERSION_CHECK:-false}" = "true" ]; then
  DEV_CONFIGS=$(find configs/patches -name "*.toml" ! -name "*.stable.toml" 2>/dev/null | sort -u)
  if [ -n "$DEV_CONFIGS" ]; then
    # shellcheck disable=SC2086
    yq -o=json eval-all '. as $item ireduce ({}; . * $item)' $DEV_CONFIGS > config.dev.json
  else
    echo "{}" > config.dev.json
  fi

  jq --slurpfile active active.prerelease.json --slurpfile activeApps active_apps.json --slurpfile activePatchApps active_patch_apps.dev.json --argjson tags "$TAGS_NEW" '
    { "patches-version": "dev", "enable-module-update": false } as $force |
    ($force + . + $force) |
    with_entries(
      if .value | type == "object" then
        .key as $k |
        .value as $app |
        (($app["patches-source"] // "morpheapp/morphe-patches") | ascii_downcase | gsub("[\"'\''\\n\\r\\t]"; " ") | split(" ") | map(select(. != ""))) as $srcs |
        
        # Check if the app has any source where pre_date > stable_date or where no pre_date exists (fallback to stable or active)
        (
          $srcs | map(
            . as $src |
            ($tags | to_entries | map(select((.value.repo | ascii_downcase) == $src)) | .[0].value) as $t |
            if $t == null then true
            elif ($t.prerelease // "") == "" then true
            else ($t.pre_date // "") >= ($t.stable_date // "") end
          ) | any
        ) as $has_valid_dev |

        if ((($srcs - $active[0]) != $srcs) and ($activePatchApps[0] | index($k))) or (($activeApps[0] | index($k)) and $has_valid_dev) then . else empty end
      else . end
    )
  ' config.dev.json > configs/config.dev.updated.json

  split_config_json "configs/config.dev.updated.json" "config.dev" 5 3
fi
