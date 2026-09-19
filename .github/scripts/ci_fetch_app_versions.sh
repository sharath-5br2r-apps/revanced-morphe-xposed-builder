#!/bin/bash
set -euo pipefail

# This script is also used by scripts/fetch_versions.sh and local builders, so
# never assume GitHub Actions' working directory or command annotations.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
    SCRIPT_PATH=$(readlink "$SCRIPT_PATH")
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_PATH"
done
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
cd "$ROOT_DIR"

CONFIG_DIR="${CONFIG_DIR:-$ROOT_DIR/configs}"
APP_VERSIONS_FILE="${APP_VERSIONS_FILE:-$CONFIG_DIR/app_versions.json}"
OUTPUT_FILE="${FETCHED_APP_VERSIONS_FILE:-$ROOT_DIR/fetched_app_versions.json}"
NO_SLEEP="${NO_SLEEP:-${CI_FETCH_NO_SLEEP:-false}}"
CONFIG_LIST="${CONFIG_FILES:-}"
ALLOWED_APPS="${CI_FETCH_ALLOWED_APPS:-}"
if [ "${1:-}" = "--allowed-apps" ] && [ -n "${2:-}" ]; then
    ALLOWED_APPS="$2"
elif [[ "${1:-}" == --allowed-apps=* ]]; then
    ALLOWED_APPS="${1#--allowed-apps=}"
fi

source "$ROOT_DIR/scripts/utils.sh"
set_prebuilts

# Version detection is intentionally based only on the source patch TOMLs.
# Generated channel/batch configs are build artifacts and may be stale or absent.
python3 "$ROOT_DIR/.github/scripts/merge_toml_configs.py" \
    .dev.toml "$ROOT_DIR/temp_all_configs.json"
if [ ! -s "$ROOT_DIR/temp_all_configs.json" ]; then
    echo "No patch configs found under configs/patches."
    exit 0
fi

[ -f "$APP_VERSIONS_FILE" ] || echo '{}' > "$APP_VERSIONS_FILE"

WORK_FILE=$(mktemp "${TMPDIR:-/tmp}/ci-fetch.XXXXXX")
trap 'rm -f "$ROOT_DIR/temp_all_configs.json" "$WORK_FILE" "$ROOT_DIR/check_list.txt"' EXIT
: > "$WORK_FILE"
CHECK_ONLY_LISTED=$(jq -r '."_check_only_listed" // false' "$APP_VERSIONS_FILE")

if [ "$CHECK_ONLY_LISTED" = "true" ]; then
    jq -r 'to_entries | map(select((.key | startswith("_") | not) and (.value.keys[0] != null) and (.value.keys[0] != "null") and (.value.keys[0] != ""))) | .[] | "\(.key)|\(.value.keys[0])"' "$APP_VERSIONS_FILE" > check_list.txt
else
    # All enabled apps
    ENABLED_APPS=$(jq -r 'to_entries | map(select((.value | type == "object") and .value.enabled == true)) | .[].key' temp_all_configs.json)
    
    # Get all grouped apps to exclude them
    GROUPED_APPS=$(jq -r 'to_entries | map(select(.key | startswith("_") | not)) | .[].value.keys[]?' "$APP_VERSIONS_FILE" 2>/dev/null || echo "")
    
    > check_list.txt
    
    # Add groups first (filtering out null app keys)
    jq -r 'to_entries | map(select((.key | startswith("_") | not) and (.value.keys[0] != null) and (.value.keys[0] != "null") and (.value.keys[0] != ""))) | .[] | "\(.key)|\(.value.keys[0])"' "$APP_VERSIONS_FILE" >> check_list.txt
    
    # Add non-grouped enabled apps
    for app in $ENABLED_APPS; do
        if [ -n "$app" ] && [ "$app" != "null" ]; then
            if ! echo "$GROUPED_APPS" | grep -qx "$app"; then
                echo "$app|$app" >> check_list.txt
            fi
        fi
    done
fi

if [ -n "$ALLOWED_APPS" ]; then
    allowed_apps_file=$(mktemp "${TMPDIR:-/tmp}/ci-fetch-allowed.XXXXXX")
    tr ', ' '\n' <<< "$ALLOWED_APPS" | sed '/^$/d' > "$allowed_apps_file"
    awk -F'|' 'NR==FNR { patterns[++n]=$1; next } {
        for (i=1; i<=n; i++) if ($1 ~ patterns[i] || $2 ~ patterns[i]) { print; next }
    }' \
        "$allowed_apps_file" check_list.txt > "${allowed_apps_file}.list"
    mv "${allowed_apps_file}.list" check_list.txt
    rm -f "$allowed_apps_file"
fi

declare -A cached_versions
declare -A args

while IFS='|' read -r group app; do
    if [ -z "$group" ] || [ -z "$app" ]; then continue; fi
    [ -n "${GITHUB_ACTIONS:-}" ] && echo "::group::Fetching version for $group ($app)..." || echo "Fetching version for $group ($app)..."
    
    args=()
    archive_url=$(jq -r ".\"$app\".\"archive-dlurl\" // empty" temp_all_configs.json)
    github_url=$(jq -r ".\"$app\".\"github-dlurl\" // empty" temp_all_configs.json)
    gitlab_url=$(jq -r ".\"$app\".\"gitlab-dlurl\" // empty" temp_all_configs.json)
    forgejo_url=$(jq -r ".\"$app\".\"forgejo-dlurl\" // empty" temp_all_configs.json)

    apkmirror_url=$(jq -r ".\"$app\".\"apkmirror-dlurl\" // empty" temp_all_configs.json)
    uptodown_url=$(jq -r ".\"$app\".\"uptodown-dlurl\" // empty" temp_all_configs.json)
    apkpure_url=$(jq -r ".\"$app\".\"apkpure-dlurl\" // empty" temp_all_configs.json)
    apkcombo_url=$(jq -r ".\"$app\".\"apkcombo-dlurl\" // empty" temp_all_configs.json)

    # Restore the source-specific overrides used by downstream configs.
    archive_regex=$(jq -r ".\"$app\".\"archive-dlurl-regex\" // empty" temp_all_configs.json)

    version=$(jq -r ".\"$app\".\"version\" // empty" temp_all_configs.json)
    if [ "$version" == "beta" ] || [ "$version" == "dev" ]; then __AAV__="true"; else __AAV__="false"; fi
    prefer_apk_mode=$(jq -r ".\"$app\".\"prefer-apk-mode\" // empty" temp_all_configs.json)
    prefer_dl_mode=$(jq -r ".\"$app\".\"prefer-dl-mode\" // empty" temp_all_configs.json)
    [ -n "$prefer_dl_mode" ] || prefer_dl_mode="${prefer_apk_mode:-apk}"
    github_asset_regex=$(jq -r ".\"$app\".\"github-asset-regex\" // .\"$app\".\"github-dlurl-regex\" // .\"$app\".\"github-regex\" // empty" temp_all_configs.json)
    github_dlurl_regex="$github_asset_regex"
    github_regex="$github_dlurl_regex"
    github_release_regex=$(jq -r ".\"$app\".\"github-release-regex\" // empty" temp_all_configs.json)
    github_release_name_regex=$(jq -r ".\"$app\".\"github-release-name-regex\" // empty" temp_all_configs.json)
    github_dlurl_exclude_filter=$(jq -r ".\"$app\".\"github-dlurl-exclude-filter\" // .\"$app\".\"github-exclude-filter\" // empty" temp_all_configs.json)
    github_dlurl_source=$(jq -r ".\"$app\".\"github-dlurl-source\" // empty" temp_all_configs.json)

    gitlab_dlurl_regex=$(jq -r ".\"$app\".\"gitlab-dlurl-regex\" // .\"$app\".\"gitlab-regex\" // empty" temp_all_configs.json)
    [ -n "$gitlab_dlurl_regex" ] || gitlab_dlurl_regex="$github_asset_regex"
    gitlab_regex="$gitlab_dlurl_regex"
    gitlab_release_regex=$(jq -r ".\"$app\".\"gitlab-release-regex\" // empty" temp_all_configs.json)
    gitlab_release_name_regex=$(jq -r ".\"$app\".\"gitlab-release-name-regex\" // empty" temp_all_configs.json)
    gitlab_dlurl_exclude_filter=$(jq -r ".\"$app\".\"gitlab-dlurl-exclude-filter\" // .\"$app\".\"gitlab-exclude-filter\" // empty" temp_all_configs.json)

    forgejo_dlurl_regex=$(jq -r ".\"$app\".\"forgejo-dlurl-regex\" // .\"$app\".\"forgejo-regex\" // empty" temp_all_configs.json)
    [ -n "$forgejo_dlurl_regex" ] || forgejo_dlurl_regex="$github_asset_regex"
    forgejo_regex="$forgejo_dlurl_regex"
    forgejo_release_regex=$(jq -r ".\"$app\".\"forgejo-release-regex\" // empty" temp_all_configs.json)
    forgejo_release_name_regex=$(jq -r ".\"$app\".\"forgejo-release-name-regex\" // empty" temp_all_configs.json)
    forgejo_dlurl_exclude_filter=$(jq -r ".\"$app\".\"forgejo-dlurl-exclude-filter\" // .\"$app\".\"forgejo-exclude-filter\" // empty" temp_all_configs.json)

    apkmirror_example_url=$(jq -r ".\"$app\".\"apkmirror-example-url\" // .\"$app\".\"apkmirror-example-dlurl\" // empty" temp_all_configs.json)
    apkmirror_release_filter=$(jq -r ".\"$app\".\"apkmirror-release-filter\" // .\"$app\".\"release-filter\" // empty" temp_all_configs.json)
    dpi=$(jq -r ".\"$app\".\"dpi\" // empty" temp_all_configs.json)
    min_sdk=$(jq -r ".\"$app\".\"min-sdk\" // empty" temp_all_configs.json)
    pkg_name=$(jq -r ".\"$app\".\"pkg-name\" // empty" temp_all_configs.json)
    check_sig=$(jq -r ".\"$app\".\"check-sig\" // false" temp_all_configs.json)
    custom_microg_patches=$(jq -r ".\"$app\".\"custom-microg-patches\" // empty" temp_all_configs.json)

    version_filter=$(jq -r ".\"$app\".\"version-filter\" // .\"$app\".\"apkmirror-version-filter\" // empty" temp_all_configs.json)
    apkmirror_version_filter="$version_filter"
    included_patches=$(jq -r ".\"$app\".\"included-patches\" // empty" temp_all_configs.json)
    excluded_patches=$(jq -r ".\"$app\".\"excluded-patches\" // empty" temp_all_configs.json)
    exclusive_patches=$(jq -r ".\"$app\".\"exclusive-patches\" // false" temp_all_configs.json)
    arch=$(jq -r ".\"$app\".\"arch\" // empty" temp_all_configs.json)
    build_mode=$(jq -r ".\"$app\".\"build-mode\" // \"apk\"" temp_all_configs.json)

    args["github_dlurl"]="$github_url"
    args["github_dlurl_regex"]="$github_dlurl_regex"
    args["github_asset_regex"]="$github_asset_regex"
    args["github_regex"]="$github_regex"
    args["github_release_regex"]="$github_release_regex"
    args["github_release_name_regex"]="$github_release_name_regex"
    args["github_dlurl_exclude_filter"]="$github_dlurl_exclude_filter"
    args["github_dlurl_source"]="$github_dlurl_source"

    args["gitlab_dlurl"]="$gitlab_url"
    args["gitlab_dlurl_regex"]="$gitlab_dlurl_regex"
    args["gitlab_regex"]="$gitlab_regex"
    args["gitlab_release_regex"]="$gitlab_release_regex"
    args["gitlab_release_name_regex"]="$gitlab_release_name_regex"
    args["gitlab_dlurl_exclude_filter"]="$gitlab_dlurl_exclude_filter"

    args["forgejo_dlurl"]="$forgejo_url"
    args["forgejo_dlurl_regex"]="$forgejo_dlurl_regex"
    args["forgejo_regex"]="$forgejo_regex"
    args["forgejo_release_regex"]="$forgejo_release_regex"
    args["forgejo_release_name_regex"]="$forgejo_release_name_regex"
    args["forgejo_dlurl_exclude_filter"]="$forgejo_dlurl_exclude_filter"

    args["archive_dlurl"]="$archive_url"
    args["archive_dlurl_regex"]="$archive_regex"

    args["apkmirror_dlurl"]="$apkmirror_url"
    args["apkmirror_example_url"]="$apkmirror_example_url"
    args["apkmirror_release_filter"]="$apkmirror_release_filter"
    args["apkmirror_version_filter"]="$apkmirror_version_filter"
    args["version_filter"]="$version_filter"

    args["pkg_name"]="$pkg_name"
    args["app_name"]="$group"
    args["table"]="$app"
    args["dpi"]="$dpi"
    args["min_sdk"]="$min_sdk"
    args["check_sig"]="$check_sig"
    args["custom_microg_patches"]="$custom_microg_patches"
    args["included_patches"]="$included_patches"
    args["excluded_patches"]="$excluded_patches"
    args["exclusive_patches"]="$exclusive_patches"
    args["arch"]="$arch"
    args["build_mode"]="$build_mode"

    export dpi min_sdk pkg_name check_sig custom_microg_patches prefer_apk_mode prefer_dl_mode apkmirror_example_url apkmirror_release_filter apkmirror_version_filter version_filter github_dlurl_regex github_release_regex github_release_name_regex github_dlurl_exclude_filter github_dlurl_source gitlab_dlurl_regex gitlab_release_regex gitlab_release_name_regex gitlab_dlurl_exclude_filter forgejo_dlurl_regex forgejo_release_regex forgejo_release_name_regex forgejo_dlurl_exclude_filter archive_regex included_patches excluded_patches exclusive_patches arch build_mode

    dlurls=()
    sources=()
    [ -n "$github_url" ] && { dlurls+=("$github_url"); sources+=("github"); }
    [ -n "$gitlab_url" ] && { dlurls+=("$gitlab_url"); sources+=("gitlab"); }
    [ -n "$forgejo_url" ] && { dlurls+=("$forgejo_url"); sources+=("forgejo"); }
    [ -n "$apkmirror_url" ] && { dlurls+=("$apkmirror_url"); sources+=("apkmirror"); }
    [ -n "$uptodown_url" ] && { dlurls+=("$uptodown_url"); sources+=("uptodown"); }
    [ -n "$apkpure_url" ] && { dlurls+=("$apkpure_url"); sources+=("apkpure"); }
    [ -n "$apkcombo_url" ] && { dlurls+=("$apkcombo_url"); sources+=("apkcombo"); }

    if [ ${#dlurls[@]} -eq 0 ]; then
        wpr "No dlurl for $app, skipping"
        continue
    fi
    
    latest_ver=""
    for i in "${!dlurls[@]}"; do
        dlurl="${dlurls[$i]}"
        source="${sources[$i]}"
        cache_key="url_${source}_${dlurl//[^a-zA-Z0-9]/_}_${github_release_name_regex//[^a-zA-Z0-9]/_}_${github_release_regex//[^a-zA-Z0-9]/_}_${gitlab_release_name_regex//[^a-zA-Z0-9]/_}_${forgejo_release_name_regex//[^a-zA-Z0-9]/_}"
        
        if [ -n "${cached_versions["$cache_key"]:-}" ]; then
            latest_ver="${cached_versions["$cache_key"]}"
            echo "Reusing cached version for $app: $latest_ver"
            break
        else
            if [[ "$source" == "archive" ]]; then
                "get_${source}_resp" "$dlurl" || continue
                latest_ver=$("get_${source}_vers" | get_highest_ver) || true
            elif [[ "$source" == "github" ]]; then
                get_github_resp "$dlurl" || { wpr "Failed github resp for $app"; continue; }
                vers=$(get_github_vers) || { wpr "Failed github vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "gitlab" ]]; then
                get_gitlab_resp "$dlurl" || { wpr "Failed gitlab resp for $app"; continue; }
                vers=$(get_gitlab_vers) || { wpr "Failed gitlab vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "forgejo" ]]; then
                get_forgejo_resp "$dlurl" || { wpr "Failed forgejo resp for $app"; continue; }
                vers=$(get_forgejo_vers) || { wpr "Failed forgejo vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "apkmirror" ]]; then
                __APKMIRROR_RELEASE_FILTER__="${apkmirror_release_filter:-}"
                export __APKMIRROR_RELEASE_FILTER__
                get_apkmirror_resp "$dlurl" || { wpr "Failed apkmirror resp for $app"; continue; }
                vers=$(get_apkmirror_vers) || { wpr "Failed apkmirror vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "uptodown" ]]; then
                get_uptodown_resp "$dlurl" || { wpr "Failed uptodown resp for $app"; continue; }
                vers=$(get_uptodown_vers) || { wpr "Failed uptodown vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "apkpure" ]]; then
                get_apkpure_resp "$dlurl" || { wpr "Failed apkpure resp for $app"; continue; }
                vers=$(get_apkpure_vers) || { wpr "Failed apkpure vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "apkcombo" ]]; then
                get_apkcombo_resp "$dlurl" || { wpr "Failed apkcombo resp for $app"; continue; }
                vers=$(get_apkcombo_vers) || { wpr "Failed apkcombo vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            fi
            
            if [ -n "$latest_ver" ]; then
                cached_versions["$cache_key"]="$latest_ver"
                # Sleep to avoid rate limiting only if we actually fetched
                if [ "$NO_SLEEP" != true ] && [ "$NO_SLEEP" != 1 ]; then
                    sleep $((RANDOM % 5 + 3))
                fi
                break
            fi
        fi
    done
    
    if [ -n "$latest_ver" ]; then
        echo "Latest version for $group is $latest_ver"
        jq -n --arg grp "$group" --arg ver "$latest_ver" '{($grp): $ver}' >> "$WORK_FILE"
    else
        epr "Could not find latest version for $group"
    fi
done < check_list.txt

if [ -s "$WORK_FILE" ]; then
    FETCHED_JSON=$(jq -s 'reduce .[] as $item ({}; . * $item)' "$WORK_FILE")
else
    FETCHED_JSON="{}"
fi

# With --allowed-apps, retain the current version for every unselected group.
# This mirrors build.sh: restricted runs update only the requested applications.
if [ -n "$ALLOWED_APPS" ]; then
    existing_versions=$(jq '
        with_entries(
            if (.value | type) == "object" then
                .value = (.value.version // null)
            else . end
        ) | with_entries(select(.value != null and .value != ""))
    ' "$APP_VERSIONS_FILE")
    FETCHED_JSON=$(jq -n --argjson existing "$existing_versions" --argjson fetched "$FETCHED_JSON" '$existing * $fetched')
fi

echo "$FETCHED_JSON" > "$OUTPUT_FILE"
