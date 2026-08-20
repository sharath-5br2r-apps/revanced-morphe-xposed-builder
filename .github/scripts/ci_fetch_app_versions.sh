#!/bin/bash
set -euo pipefail

# Convert utils.sh to Unix line endings if needed
dos2unix utils.sh 2>/dev/null || true

source utils.sh
set_prebuilts

# Find all app configs in configs/ directory
CONFIG_FILES=$(find configs/patches configs -maxdepth 2 -name "*.toml" 2>/dev/null | sort -u)

if [ -z "$CONFIG_FILES" ]; then
    echo "No config files found in configs/"
    exit 0
fi

# Convert all TOML files to a single JSON
# shellcheck disable=SC2086
yq -o=json eval-all '. as $item ireduce ({}; . * $item)' $CONFIG_FILES > temp_all_configs.json

APP_VERSIONS_FILE="configs/app_versions.json"
[ -f "$APP_VERSIONS_FILE" ] || echo '{}' > "$APP_VERSIONS_FILE"

> fetched_app_versions.jsonl
CHECK_ONLY_LISTED=$(jq -r '."_check_only_listed" // false' "$APP_VERSIONS_FILE")

if [ "$CHECK_ONLY_LISTED" = "true" ]; then
    jq -r 'to_entries | map(select(.key | startswith("_") | not)) | .[] | "\(.key)|\(.value.keys[0])"' "$APP_VERSIONS_FILE" > check_list.txt
else
    # All enabled apps
    ENABLED_APPS=$(jq -r 'to_entries | map(select((.value | type == "object") and .value.enabled == true)) | .[].key' temp_all_configs.json)
    
    # Get all grouped apps to exclude them
    GROUPED_APPS=$(jq -r 'to_entries | map(select(.key | startswith("_") | not)) | .[].value.keys[]?' "$APP_VERSIONS_FILE" 2>/dev/null || echo "")
    
    > check_list.txt
    
    # Add groups first
    jq -r 'to_entries | map(select(.key | startswith("_") | not)) | .[] | "\(.key)|\(.value.keys[0])"' "$APP_VERSIONS_FILE" >> check_list.txt
    
    # Add non-grouped enabled apps
    for app in $ENABLED_APPS; do
        if ! echo "$GROUPED_APPS" | grep -qx "$app"; then
            echo "$app|$app" >> check_list.txt
        fi
    done
fi

declare -A cached_versions

while IFS='|' read -r group app; do
    if [ -z "$group" ] || [ -z "$app" ]; then continue; fi
    echo "::group::Fetching version for $group ($app)..."
    
    repo_url=$(jq -r ".\"$app\".\"repo-dlurl\" // empty" temp_all_configs.json)
    repo_dlurl_filter=$(jq -r ".\"$app\".\"repo-dlurl-filter\" // empty" temp_all_configs.json)
    repo_dlurl_exclude_filter=$(jq -r ".\"$app\".\"repo-dlurl-exclude-filter\" // empty" temp_all_configs.json)
    repo_dlurl_tag_filter=$(jq -r ".\"$app\".\"repo-dlurl-tag-filter\" // empty" temp_all_configs.json)
    repo_dlurl_release_name_filter=$(jq -r ".\"$app\".\"repo-dlurl-release-name-filter\" // empty" temp_all_configs.json)
    if [ -z "$repo_dlurl_release_name_filter" ]; then
        repo_dlurl_release_name_filter=$(jq -r ".\"$app\".\"repo-dlurl-release-filter\" // empty" temp_all_configs.json)
    fi
    repo_dlurl_release_filter="$repo_dlurl_release_name_filter"
    repo_dlurl_source=$(jq -r ".\"$app\".\"repo-dlurl-source\" // empty" temp_all_configs.json)

    apkmirror_url=$(jq -r ".\"$app\".\"apkmirror-dlurl\" // empty" temp_all_configs.json)
    uptodown_url=$(jq -r ".\"$app\".\"uptodown-dlurl\" // empty" temp_all_configs.json)
    apkpure_url=$(jq -r ".\"$app\".\"apkpure-dlurl\" // empty" temp_all_configs.json)
    apkcombo_url=$(jq -r ".\"$app\".\"apkcombo-dlurl\" // empty" temp_all_configs.json)

    version=$(jq -r ".\"$app\".\"version\" // empty" temp_all_configs.json)
    if [ "$version" == "beta" ] || [ "$version" == "dev" ]; then __AAV__="true"; else __AAV__="false"; fi
    prefer_apk_mode=$(jq -r ".\"$app\".\"prefer-apk-mode\" // empty" temp_all_configs.json)
    prefer_dl_mode=$(jq -r ".\"$app\".\"prefer-dl-mode\" // empty" temp_all_configs.json)
    [ -n "$prefer_dl_mode" ] || prefer_dl_mode="${prefer_apk_mode:-apk}"
    apkmirror_example_url=$(jq -r ".\"$app\".\"apkmirror-example-url\" // empty" temp_all_configs.json)
    dpi=$(jq -r ".\"$app\".\"dpi\" // empty" temp_all_configs.json)
    min_sdk=$(jq -r ".\"$app\".\"min-sdk\" // empty" temp_all_configs.json)
    pkg_name=$(jq -r ".\"$app\".\"pkg-name\" // empty" temp_all_configs.json)
    check_sig=$(jq -r ".\"$app\".\"check-sig\" // false" temp_all_configs.json)
    custom_microg_patches=$(jq -r ".\"$app\".\"custom-microg-patches\" // empty" temp_all_configs.json)
    export dpi min_sdk pkg_name check_sig custom_microg_patches prefer_apk_mode prefer_dl_mode apkmirror_example_url repo_dlurl_filter repo_dlurl_exclude_filter repo_dlurl_tag_filter repo_dlurl_release_name_filter repo_dlurl_release_filter repo_dlurl_source

    dlurls=()
    sources=()
    [ -n "$repo_url" ] && { dlurls+=("$repo_url"); sources+=("repo"); }
    [ -n "$apkmirror_url" ] && { dlurls+=("$apkmirror_url"); sources+=("apkmirror"); }
    [ -n "$uptodown_url" ] && { dlurls+=("$uptodown_url"); sources+=("uptodown"); }
    [ -n "$apkpure_url" ] && { dlurls+=("$apkpure_url"); sources+=("apkpure"); }
    [ -n "$apkcombo_url" ] && { dlurls+=("$apkcombo_url"); sources+=("apkcombo"); }

    if [ ${#dlurls[@]} -eq 0 ]; then
        echo "::warning::No dlurl for $app, skipping"
        echo "::endgroup::"
        continue
    fi
    
    latest_ver=""
    for i in "${!dlurls[@]}"; do
        dlurl="${dlurls[$i]}"
        source="${sources[$i]}"
        cache_key="url_${dlurl//[^a-zA-Z0-9]/_}"
        
        if [ -n "${cached_versions["$cache_key"]:-}" ]; then
            latest_ver="${cached_versions["$cache_key"]}"
            echo "::notice::Reusing cached version for $app: $latest_ver"
            break
        else
            if [[ "$source" == "repo" ]]; then
                get_repo_resp "$dlurl" || { echo "::warning::Failed repo resp for $app"; continue; }
                vers=$(get_repo_vers) || { echo "::warning::Failed repo vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "apkmirror" ]]; then
                get_apkmirror_resp "$dlurl" || { echo "::warning::Failed apkmirror resp for $app"; continue; }
                vers=$(get_apkmirror_vers) || { echo "::warning::Failed apkmirror vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "uptodown" ]]; then
                get_uptodown_resp "$dlurl" || { echo "::warning::Failed uptodown resp for $app"; continue; }
                vers=$(get_uptodown_vers) || { echo "::warning::Failed uptodown vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "apkpure" ]]; then
                get_apkpure_resp "$dlurl" || { echo "::warning::Failed apkpure resp for $app"; continue; }
                vers=$(get_apkpure_vers) || { echo "::warning::Failed apkpure vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            elif [[ "$source" == "apkcombo" ]]; then
                get_apkcombo_resp "$dlurl" || { echo "::warning::Failed apkcombo resp for $app"; continue; }
                vers=$(get_apkcombo_vers) || { echo "::warning::Failed apkcombo vers for $app"; continue; }
                latest_ver=$(echo "$vers" | get_highest_ver) || true
            fi
            
            if [ -n "$latest_ver" ]; then
                cached_versions["$cache_key"]="$latest_ver"
                # Sleep to avoid rate limiting only if we actually fetched
                sleep $((RANDOM % 5 + 3))
                break
            fi
        fi
    done
    
    if [ -n "$latest_ver" ]; then
        echo "Latest version for $group is $latest_ver"
        jq -n --arg grp "$group" --arg ver "$latest_ver" '{($grp): $ver}' >> fetched_app_versions.jsonl
    else
        echo "::error::Could not find latest version for $group"
    fi
    echo "::endgroup::"
done < check_list.txt

if [ -s fetched_app_versions.jsonl ]; then
    FETCHED_JSON=$(jq -s 'reduce .[] as $item ({}; . * $item)' fetched_app_versions.jsonl)
else
    FETCHED_JSON="{}"
fi

echo "$FETCHED_JSON" > fetched_app_versions.json

rm -f temp_all_configs.json fetched_app_versions.jsonl check_list.txt
