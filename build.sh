#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

source utils.sh
echo '{}' > "$BUILD_JSON_FILE"

trap "abort" INT

# Parse command-line arguments
DO_CLEAN=false
DO_CONFIG_UPDATE=false
CLI_CONFIG_FILE=""
ALLOWED_APPS_REGEX=""
CLI_OUTPUT_DIR=""
POSITIONAL_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
		--clean|clean)
			DO_CLEAN=true
			shift
			;;
		--config-update)
			DO_CONFIG_UPDATE=true
			shift
			;;
		--config=*)
			CLI_CONFIG_FILE="${1#*=}"
			shift
			;;
		--config)
			[ $# -lt 2 ] && abort "Missing argument for --config"
			CLI_CONFIG_FILE="$2"
			shift 2
			;;
		--allowed-apps=*)
			ALLOWED_APPS_REGEX="${1#*=}"
			shift
			;;
		--allowed-apps)
			[ $# -lt 2 ] && abort "Missing argument for --allowed-apps"
			ALLOWED_APPS_REGEX="$2"
			shift 2
			;;
		--output=*)
			CLI_OUTPUT_DIR="${1#*=}"
			shift
			;;
		--output)
			[ $# -lt 2 ] && abort "Missing argument for --output"
			CLI_OUTPUT_DIR="$2"
			shift 2
			;;
		--)
			shift
			while [ $# -gt 0 ]; do
				POSITIONAL_ARGS+=("$1")
				shift
			done
			break
			;;
		-*)
			abort "Unknown option: $1"
			;;
		*)
			POSITIONAL_ARGS+=("$1")
			shift
			;;
	esac
done

if [ "$DO_CLEAN" = true ]; then
	[ -n "$CLI_OUTPUT_DIR" ] && BUILD_DIR="$CLI_OUTPUT_DIR"
	rm -rf "$TEMP_DIR" "$BUILD_DIR" build.md
	exit 0
fi

if [ "$DO_CONFIG_UPDATE" = true ]; then
	config_update
	exit 0
fi

if [ -n "$CLI_OUTPUT_DIR" ]; then
	BUILD_DIR="$CLI_OUTPUT_DIR"
fi

rm -f "$TEMP_DIR/cf_get.lock"

jq --version >/dev/null || abort "\`jq\` is not installed. install it with 'apt install jq' or equivalent"
java --version >/dev/null || abort "\`java\` is not installed. install it with 'apt install openjdk-21-jre' or equivalent"
zip --version >/dev/null || abort "\`zip\` is not installed. install it with 'apt install zip' or equivalent"

set_prebuilts

vtf() { if ! isoneof "${1}" "true" "false"; then abort "ERROR: '${1}' is not a valid option for '${2}': only true or false is allowed"; fi; }

# -- Main config --
cfg_file=""
if [ -n "$CLI_CONFIG_FILE" ]; then
	cfg_file="$CLI_CONFIG_FILE"
elif [ ${#POSITIONAL_ARGS[@]} -gt 0 ] && [ -f "${POSITIONAL_ARGS[0]}" ]; then
	cfg_file="${POSITIONAL_ARGS[0]}"
	POSITIONAL_ARGS=("${POSITIONAL_ARGS[@]:1}")
elif [ -f "configs/config.toml" ]; then
	cfg_file="configs/config.toml"
elif [ -f "config.toml" ]; then
	cfg_file="config.toml"
elif [ -f "configs/config.manual.generated.toml" ]; then
	cfg_file="configs/config.manual.generated.toml"
fi

toml_prep "$cfg_file" || abort "could not find config file '$cfg_file'\n\tUsage: $0 [--clean] [--config-update] [--config=path/to/config] [--allowed-apps=\"regex\"] [--output=path/to/output/dir]"
main_config_t=$(toml_get_table_main)
COMPRESSION_LEVEL=$(toml_get "$main_config_t" compression-level) || COMPRESSION_LEVEL="9"
REMOVE_RV_INTEGRATIONS_CHECKS=$(toml_get "$main_config_t" remove-rv-integrations-checks) || REMOVE_RV_INTEGRATIONS_CHECKS="false"
DEF_PATCHES_VER=$(toml_get "$main_config_t" patches-version) || DEF_PATCHES_VER="latest"
DEF_CLI_VER=$(toml_get "$main_config_t" cli-version) || DEF_CLI_VER="latest"
DEF_PATCHES_SRC=$(toml_get "$main_config_t" patches-source) || DEF_PATCHES_SRC="MorpheApp/morphe-patches"
DEF_PATCHES_SRC_HOST=$(toml_get "$main_config_t" patches-source-host) || DEF_PATCHES_SRC_HOST="github"
DEF_CLI_SRC=$(toml_get "$main_config_t" cli-source) || DEF_CLI_SRC="MorpheApp/morphe-desktop"
DEF_CLI_SRC_HOST=$(toml_get "$main_config_t" cli-source-host) || DEF_CLI_SRC_HOST="github"
DEF_RV_BRAND=$(toml_get "$main_config_t" rv-brand) || DEF_RV_BRAND="ReVanced"
DEF_DPI=$(toml_get "$main_config_t" dpi) || DEF_DPI="nodpi anydpi auto"
mkdir -p "$TEMP_DIR" "$BUILD_DIR"

: >build.md
ENABLE_MODULE_UPDATE=$(toml_get "$main_config_t" enable-module-update) || ENABLE_MODULE_UPDATE=true
if [ "$ENABLE_MODULE_UPDATE" = true ] && [ -z "${GITHUB_REPOSITORY-}" ]; then
	pr "You are building locally. Module updates will not be enabled."
	ENABLE_MODULE_UPDATE=false
fi
if ((COMPRESSION_LEVEL > 9)) || ((COMPRESSION_LEVEL < 0)); then abort "compression-level must be within 0-9"; fi

rm -rf module/bin/*/tmp.*
for file in "$TEMP_DIR"/*/changelog.md; do
	[ -f "$file" ] && : >"$file"
done

mkdir -p ${MODULE_TEMPLATE_DIR}/bin/arm64 ${MODULE_TEMPLATE_DIR}/bin/arm ${MODULE_TEMPLATE_DIR}/bin/x86 ${MODULE_TEMPLATE_DIR}/bin/x64
[ -f "${MODULE_TEMPLATE_DIR}/bin/arm64/cmpr" ] || gh_dl "${MODULE_TEMPLATE_DIR}/bin/arm64/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-arm64-v8a"
[ -f "${MODULE_TEMPLATE_DIR}/bin/arm/cmpr" ] || gh_dl "${MODULE_TEMPLATE_DIR}/bin/arm/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-armeabi-v7a"
[ -f "${MODULE_TEMPLATE_DIR}/bin/x86/cmpr" ] || gh_dl "${MODULE_TEMPLATE_DIR}/bin/x86/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-x86"
[ -f "${MODULE_TEMPLATE_DIR}/bin/x64/cmpr" ] || gh_dl "${MODULE_TEMPLATE_DIR}/bin/x64/cmpr" "https://github.com/j-hc/cmpr/releases/latest/download/cmpr-x86_64"

config_tables=()
readarray -t config_tables < <(toml_get_table_names)
for table_name in "${config_tables[@]}"; do
	if [ -z "$table_name" ]; then continue; fi
	t=$(toml_get_table "$table_name")

	# Check filter via --allowed-apps regex if specified
	if [ -n "$ALLOWED_APPS_REGEX" ]; then
		if [[ "$ALLOWED_APPS_REGEX" == !* ]]; then
			pat="${ALLOWED_APPS_REGEX#!}"
			if [ -n "$pat" ] && [[ "$table_name" =~ $pat ]]; then
				continue
			fi
		elif ! [[ "$table_name" =~ $ALLOWED_APPS_REGEX ]]; then
			continue
		fi
	fi

	# Check positional arguments for app matching/exclusion
	if [ ${#POSITIONAL_ARGS[@]} -gt 0 ]; then
		skip_table=false
		has_pos_args=false
		pos_matched=false
		for arg in "${POSITIONAL_ARGS[@]}"; do
			if [[ "$arg" == !* ]]; then
				pat="${arg#!}"
				if [ -n "$pat" ] && [[ "$table_name" =~ $pat ]]; then
					skip_table=true
					break
				fi
			else
				has_pos_args=true
				if [[ "$table_name" =~ $arg ]]; then
					pos_matched=true
				fi
			fi
		done
		if [ "$skip_table" = true ]; then continue; fi
		if [ "$has_pos_args" = true ] && [ "$pos_matched" = false ]; then continue; fi
	fi
	enabled=$(toml_get "$t" enabled) || enabled=true
	vtf "$enabled" "enabled"
	if [ "$enabled" = false ]; then continue; fi

	declare -A app_args
	patches_src=$(toml_get "$t" patches-source) || patches_src=$DEF_PATCHES_SRC
	patches_src_host=$(toml_get "$t" patches-source-host) || patches_src_host=$DEF_PATCHES_SRC_HOST
	patches_ver=$(toml_get "$t" patches-version) || patches_ver=$DEF_PATCHES_VER
	[ -n "${OVERRIDE_PATCHES_VERSION:-}" ] && patches_ver="${OVERRIDE_PATCHES_VERSION}"
	cli_src=$(toml_get "$t" cli-source) || cli_src=$DEF_CLI_SRC
	cli_src_host=$(toml_get "$t" cli-source-host) || cli_src_host=$DEF_CLI_SRC_HOST
	cli_ver=$(toml_get "$t" cli-version) || cli_ver=$DEF_CLI_VER
	cli_host_type="" cli_host_inst=""
	if ! parse_host_spec "$cli_src_host" cli_host_type cli_host_inst; then
		abort "ERROR: cli-source-host '$cli_src_host' is not a valid option for '$table_name'"
	fi

	# Parse patch sources: natively supported array or single string
	readarray -t p_srcs < <(list_args "$patches_src")
	[ ${#p_srcs[@]} -eq 0 ] && p_srcs=("$patches_src")
	readarray -t p_hosts < <(list_args "$patches_src_host")
	[ ${#p_hosts[@]} -eq 0 ] && p_hosts=("$patches_src_host")
	readarray -t p_vers < <(list_args "$patches_ver")
	[ ${#p_vers[@]} -eq 0 ] && p_vers=("$patches_ver")
	for h in "${p_hosts[@]}"; do
		ph_type="" ph_inst=""
		if ! parse_host_spec "$h" ph_type ph_inst; then
			abort "ERROR: patches-source-host '$h' is not a valid option for '$table_name'"
		fi
	done

	cli_src_filter=$(toml_get "$t" cli-source-filter) || cli_src_filter=$(toml_get "$t" cli-filter) || cli_src_filter=""
	cli_tag_filter=$(toml_get "$t" cli-tag-filter) || cli_tag_filter=$(toml_get "$t" cli-version-filter) || cli_tag_filter=""
	cli_rel_name_filter=$(toml_get "$t" cli-release-name-filter) || cli_rel_name_filter=$(toml_get "$t" cli-release-filter) || cli_rel_name_filter=""

	patches_src_filter=$(toml_get "$t" patches-source-filter) || patches_src_filter=$(toml_get "$t" patches-filter) || patches_src_filter=""
	patches_tag_filter=$(toml_get "$t" patches-tag-filter) || patches_tag_filter=$(toml_get "$t" patches-version-filter) || patches_tag_filter=""
	patches_rel_name_filter=$(toml_get "$t" patches-release-name-filter) || patches_rel_name_filter=$(toml_get "$t" patches-release-filter) || patches_rel_name_filter=""

	if ! PREBUILTS="$(get_prebuilts "$cli_src_host" "$cli_src" "$cli_ver" "${p_hosts[*]}" "${p_srcs[*]}" "${p_vers[*]}" "$cli_src_filter" "$patches_src_filter" "$cli_tag_filter" "$patches_tag_filter" "$cli_rel_name_filter" "$patches_rel_name_filter")"; then
		epr "Could not get prebuilts"
		continue
	fi
	read -r cli_jar patches_jar_all <<<"$PREBUILTS"
	app_args[cli]=$cli_jar
	app_args[ptjar]=$patches_jar_all
	app_args[cli_source]=$cli_src
	app_args[patches_sources_all]="${p_srcs[*]}"

	# Build aggregated patches_ref and changelog_url from all sources
	patches_ref_all="" changelog_url_all=""
	for i in "${!p_srcs[@]}"; do
		raw_ph="${p_hosts[$i]:-${p_hosts[0]}}"
		phost_type="" phost_inst=""
		parse_host_spec "$raw_ph" phost_type phost_inst || true
		psrc="${p_srcs[$i]}"
		pver="${p_vers[$i]:-${p_vers[0]}}"
		pref=""
		if [ "$pver" != "latest" ] && [ "$pver" != "dev" ] && [ "$pver" != "absolutelatest" ] && [[ "$pver" != regex:* ]]; then
			pref="${pver}"
		fi
		patches_ref_all="${patches_ref_all}${pref},"
		ptag="${pref}"
		if [ -z "$ptag" ]; then
			p_dir="${psrc%/*}"
			p_dir="${TEMP_DIR}/${p_dir,,}-rv"
			if [ -f "${p_dir}/tag_name.txt" ]; then
				ptag=$(cat "${p_dir}/tag_name.txt" 2>/dev/null || echo "latest")
			else
				ptag="latest"
			fi
		fi
		if [ "$phost_type" = "none" ]; then
			changelog_url_all="${changelog_url_all}passthrough "
		else
			changelog_url=$(source_release_web_url "$phost_type" "$psrc" "$ptag" "$phost_inst" 2>/dev/null || true)
			changelog_url_all="${changelog_url_all}${changelog_url:-passthrough} "
		fi
	done
	app_args[patches_src]=${p_srcs[0]}
	app_args[patches_version]="${p_vers[0]}"
	app_args[patches_ref]="${patches_ref_all%,}"
	app_args[changelog_url]="${changelog_url_all% }"
	app_args[rv_brand]=$(toml_get "$t" rv-brand) || app_args[rv_brand]="${p_srcs[0]%%/*}"
	app_args[github_regex]=$(toml_get "$t" github-dlurl-regex) || app_args[github_regex]=$(toml_get "$t" github-regex) || app_args[github_regex]=""
	app_args[github_dlurl_regex]="${app_args[github_regex]}"
	app_args[github_release_regex]=$(toml_get "$t" github-release-regex) || app_args[github_release_regex]=""
	app_args[github_release_name_regex]=$(toml_get "$t" github-release-name-regex) || app_args[github_release_name_regex]=""
	app_args[github_dlurl_exclude_filter]=$(toml_get "$t" github-dlurl-exclude-filter) || app_args[github_dlurl_exclude_filter]=$(toml_get "$t" github-exclude-filter) || app_args[github_dlurl_exclude_filter]=""
	app_args[github_dlurl_source]=$(toml_get "$t" github-dlurl-source) || app_args[github_dlurl_source]=""

	app_args[gitlab_regex]=$(toml_get "$t" gitlab-dlurl-regex) || app_args[gitlab_regex]=$(toml_get "$t" gitlab-regex) || app_args[gitlab_regex]=""
	app_args[gitlab_dlurl_regex]="${app_args[gitlab_regex]}"
	app_args[gitlab_release_regex]=$(toml_get "$t" gitlab-release-regex) || app_args[gitlab_release_regex]=""
	app_args[gitlab_release_name_regex]=$(toml_get "$t" gitlab-release-name-regex) || app_args[gitlab_release_name_regex]=""
	app_args[gitlab_dlurl_exclude_filter]=$(toml_get "$t" gitlab-dlurl-exclude-filter) || app_args[gitlab_dlurl_exclude_filter]=$(toml_get "$t" gitlab-exclude-filter) || app_args[gitlab_dlurl_exclude_filter]=""

	app_args[forgejo_regex]=$(toml_get "$t" forgejo-dlurl-regex) || app_args[forgejo_regex]=$(toml_get "$t" forgejo-regex) || app_args[forgejo_regex]=""
	app_args[forgejo_dlurl_regex]="${app_args[forgejo_regex]}"
	app_args[forgejo_release_regex]=$(toml_get "$t" forgejo-release-regex) || app_args[forgejo_release_regex]=""
	app_args[forgejo_release_name_regex]=$(toml_get "$t" forgejo-release-name-regex) || app_args[forgejo_release_name_regex]=""
	app_args[forgejo_dlurl_exclude_filter]=$(toml_get "$t" forgejo-dlurl-exclude-filter) || app_args[forgejo_dlurl_exclude_filter]=$(toml_get "$t" forgejo-exclude-filter) || app_args[forgejo_dlurl_exclude_filter]=""


	app_args[apkmirror_example_url]=$(toml_get "$t" apkmirror-example-url) || app_args[apkmirror_example_url]=$(toml_get "$t" apkmirror-example-dlurl) || app_args[apkmirror_example_url]=""
	app_args[apkmirror_release_filter]=$(toml_get "$t" apkmirror-release-filter) || app_args[apkmirror_release_filter]=$(toml_get "$t" release-filter) || app_args[apkmirror_release_filter]=""
	app_args[check_sig]=$(toml_get "$t" check-sig) || app_args[check_sig]=false
	app_args[prefer_dl_mode]=$(toml_get "$t" prefer-dl-mode) || app_args[prefer_dl_mode]=apk
	app_args[custom_microg_patches]=$(toml_get "$t" custom-microg-patches) || app_args[custom_microg_patches]=""
	app_args[excluded_patches]=$(toml_get "$t" excluded-patches) || app_args[excluded_patches]=""
	app_args[included_patches]=$(toml_get "$t" included-patches) || app_args[included_patches]=""
	app_args[exclusive_patches]=$(toml_get "$t" exclusive-patches) || app_args[exclusive_patches]=false
	app_args[version]=$(toml_get "$t" version) || app_args[version]="auto"
	app_args[version_filter]=$(toml_get "$t" version-filter) || app_args[version_filter]=$(toml_get "$t" apkmirror-version-filter) || app_args[version_filter]=""
	app_args[apkmirror_version_filter]=$(toml_get "$t" apkmirror-version-filter) || app_args[apkmirror_version_filter]="${app_args[version_filter]}"
	app_args[version_code]=$(toml_get "$t" version-code) || app_args[version_code]=""
	app_args[app_name]=$(toml_get "$t" app-name) || app_args[app_name]=$table_name
	app_args[patcher_args]=$(toml_get "$t" patcher-args) || app_args[patcher_args]=""
	app_args[table]=$table_name
	app_args[build_mode]=$(toml_get "$t" build-mode) && {
		if ! isoneof "${app_args[build_mode]}" both apk module; then
			abort "ERROR: build-mode '${app_args[build_mode]}' is not a valid option for '${table_name}': only 'both', 'apk' or 'module' is allowed"
		fi
	} || app_args[build_mode]=apk
	app_args[include_stock]=$(toml_get "$t" include-stock) && {
		if ! isoneof "${app_args[include_stock]}" disable merged split; then
			abort "ERROR: include-stock '${app_args[include_stock]}' is not a valid option for '${table_name}': only 'disable', 'merged' or 'split' is allowed"
		fi
	} || app_args[include_stock]=merged

	for dl_from in "${DL_SRCS[@]}"; do
		if app_args[${dl_from}_dlurl]=$(toml_get "$t" "${dl_from}-dlurl") || app_args[${dl_from}_dlurl]=$(toml_get "$t" "${dl_from}_dlurl"); then
			app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%/}
			app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%download}
			app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%/}
			app_args[dl_from]=${dl_from}
		else
			app_args[${dl_from}_dlurl]=""
		fi
	done
	if [ -z "${app_args[dl_from]-}" ]; then abort "ERROR: no 'dlurl' option was set for '$table_name'. (${DL_SRCS[*]})"; fi

	raw_arch=$(toml_get "$t" arch) || raw_arch="auto"
	readarray -t arch_list < <(list_args "$raw_arch")
	[ "${#arch_list[@]}" -eq 0 ] && arch_list=("auto")

	for a in "${arch_list[@]}"; do
		if ! isoneof "$a" "auto" "all" "arm64-v8a" "arm-v7a" "x86_64" "x86"; then
			abort "wrong arch '$a' for '$table_name'"
		fi
	done

	app_args[pkg_name]=$(toml_get "$t" pkg-name) || app_args[pkg_name]=""
	app_args[dpi]=$(toml_get "$t" dpi) || app_args[dpi]="$DEF_DPI"
	app_args[dpi]="${app_args[dpi]:-$DEF_DPI}"
	table_name_f=${table_name,,}
	table_name_f=${table_name_f// /-}
	app_args[module_prop_name]=$(toml_get "$t" module-prop-name) || app_args[module_prop_name]="${table_name_f}-jhc"
	module_prop_name_b=${app_args[module_prop_name]}

	app_args[arch]="${arch_list[*]}"
	app_args[table]="$table_name"

	if [ -n "${GITHUB_REPOSITORY:-}" ]; then echo "::group::Building ${app_args[table]}"; fi
	build_rv "$(declare -p app_args)" || epr "Build failed for ${app_args[table]}, continuing..."
	if [ -n "${GITHUB_REPOSITORY:-}" ]; then echo "::endgroup::"; fi
done
rm -rf temp/tmp.*
if [ -z "$(ls -A1 "${BUILD_DIR}")" ]; then
	wpr "WARNING: No builds completed or output directory is empty."
	exit 0
fi

log "\n**Notes:**"
log "• Install [MicroG-RE](https://github.com/MorpheApp/MicroG-RE/releases/latest) or [MicroG](https://github.com/ReVanced/GmsCore/releases/latest), required for Google APKs."
log "• Use [Zygisk Detach](https://github.com/j-hc/zygisk-detach) to stop Play Store from updating Modules."
log "\n[GitHub](https://github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder) | [Website](https://sharath-5br2r-apps.github.io)\n"

changelog_merged=$(cat "$TEMP_DIR"/*/changelog.md 2>/dev/null || :)
changelog_merged=$(awk '
{
	line=$0
	if (line ~ /^(CLI|Patches): /) {
		key=line
		sub(/\r$/, "", key)
		gsub(/[[:space:]]+$/, "", key)
		if (seen[key]++) {
			skip_changelog = 1
			next
		}
		skip_changelog = 0
	} else if (skip_changelog) {
		if (line ~ /^\[Changelog\]/ || line ~ /^<details>/ || line ~ /^<summary>/ || line ~ /^<\/details>/ || line == "" || line == "\r") {
			next
		}
		skip_changelog = 0
	}
	print line
}' <<<"$changelog_merged")
log "$changelog_merged"

if [ -f "$BUILD_JSON_FILE" ]; then
	patches_summary=$(jq -r '
		to_entries | map(
			.key as $app |
			.value as $val |
			if ($val.applied_patches | length) > 0 then
				"<details><summary><b>" + $app + " (" + (($val.applied_patches | length) | tostring) + " patches)</b></summary>\n\n" +
				($val.applied_patches | map("• " + .) | join("\n")) +
				"\n</details>"
			else
				empty
			fi
		) | join("\n\n")
	' "$BUILD_JSON_FILE" 2>/dev/null || true)
	if [ -n "$patches_summary" ]; then
		log "\n<details><summary><b>Applied Patches Details</b></summary>\n\n${patches_summary}\n</details>\n"
	fi
fi

SKIPPED=$(cat "$TEMP_DIR"/skipped 2>/dev/null || :)
if [ -n "$SKIPPED" ]; then
	log "\nSkipped:"
	log "$SKIPPED"
fi

pr "Done"
