#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

# Engine is run with repo root as CWD (workflows, CI scripts) but lives beside
# utils.sh under scripts/; source the sibling explicitly.
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
echo '{}' > "$BUILD_JSON_FILE"

CONFIG_FILE="config.toml"
ALLOWED_APPS=""
OUTPUT_DIR=""
while [ $# -gt 0 ]; do
	case "$1" in
		--config=*) CONFIG_FILE="${1#*=}" ;;
		--config) shift; CONFIG_FILE="${1:?missing value for --config}" ;;
		--allowed-apps=*) ALLOWED_APPS="${1#*=}" ;;
		--allowed-apps) shift; ALLOWED_APPS="${1:?missing value for --allowed-apps}" ;;
		--output=*) OUTPUT_DIR="${1#*=}" ;;
		--output) shift; OUTPUT_DIR="${1:?missing value for --output}" ;;
		--clean) CLEAN_REQUESTED=true ;;
		clean) CLEAN_REQUESTED=true ;;
		*) [ "$CONFIG_FILE" = config.toml ] && CONFIG_FILE="$1" || abort "Unknown option: $1" ;;
	esac
	shift
done

if [ -n "$OUTPUT_DIR" ]; then BUILD_DIR="$OUTPUT_DIR"; fi

trap "abort" INT

if [ "${CLEAN_REQUESTED:-false}" = true ]; then
	rm -r "$TEMP_DIR" "$BUILD_DIR" build.md
	exit 0
fi

jq --version >/dev/null || abort "\`jq\` is not installed. install it with 'apt install jq' or equivalent"
java --version >/dev/null || abort "\`java\` is not installed. install it with 'apt install openjdk-21-jre' or equivalent"
zip --version >/dev/null || abort "\`zip\` is not installed. install it with 'apt install zip' or equivalent"

set_prebuilts

vtf() { if ! isoneof "${1}" "true" "false"; then abort "ERROR: '${1}' is not a valid option for '${2}': only true or false is allowed"; fi; }

# -- Main config --
toml_prep "$CONFIG_FILE" || abort "could not find config file '$CONFIG_FILE'\n\tUsage: $0 [--config=path] [--allowed-apps=regex] [--output=dir]"
main_config_t=$(toml_get_table_main)
COMPRESSION_LEVEL=$(toml_get "$main_config_t" compression-level) || COMPRESSION_LEVEL="9"
REMOVE_RV_INTEGRATIONS_CHECKS=$(toml_get "$main_config_t" remove-rv-integrations-checks) || REMOVE_RV_INTEGRATIONS_CHECKS="false"
DEF_PATCHES_VER=$(toml_get "$main_config_t" patches-version) || DEF_PATCHES_VER="both"
[ "$DEF_PATCHES_VER" = "both" ] && DEF_PATCHES_VER="beta"
DEF_CLI_VER=$(toml_get "$main_config_t" cli-version) || DEF_CLI_VER="stable"
DEF_PATCHES_SRC=$(toml_get "$main_config_t" patches-source) || DEF_PATCHES_SRC="MorpheApp/morphe-patches"
DEF_PATCHES_SRC_HOST=$(toml_get "$main_config_t" patches-source-host) || DEF_PATCHES_SRC_HOST="github"
DEF_CLI_SRC=$(toml_get "$main_config_t" cli-source) || DEF_CLI_SRC="MorpheApp/morphe-desktop"
DEF_CLI_SRC_HOST=$(toml_get "$main_config_t" cli-source-host) || DEF_CLI_SRC_HOST="github"
DEF_BRAND=$(toml_get "$main_config_t" brand) || DEF_BRAND=""
DEF_ENGINE_BRAND=$(toml_get "$main_config_t" engine-brand) || DEF_ENGINE_BRAND=""
DEF_PATCH_BRAND=$(toml_get "$main_config_t" patch-brand) || DEF_PATCH_BRAND=""
DEF_VARIANT=$(toml_get "$main_config_t" variant) || DEF_VARIANT=""
DEF_SUB_VARIANT=$(toml_get "$main_config_t" sub-variant) || DEF_SUB_VARIANT=""
[ -z "$DEF_SUB_VARIANT" ] && { DEF_SUB_VARIANT=$(toml_get "$main_config_t" sub_variant) || DEF_SUB_VARIANT=""; }
DEF_DPI=$(toml_get "$main_config_t" dpi) || DEF_DPI="nodpi anydpi auto"
DEF_ARCH=$(toml_get "$main_config_t" arch) || DEF_ARCH="both"
DEF_BUILD_MODE=$(toml_get "$main_config_t" build-mode) || DEF_BUILD_MODE="apk"
DEF_AUTHOR_NAME=$(toml_get "$main_config_t" author) || DEF_AUTHOR_NAME="nullcpy"
DEF_AUTHOR_PAGE=$(toml_get "$main_config_t" author-page) || DEF_AUTHOR_PAGE="github.com/nullcpy/rvb"
mkdir -p "$TEMP_DIR" "$BUILD_DIR"

# Build process pool. Each child re-sources utils.sh so patcher state and
# caches remain isolated; architecture slices use this same table queue.
PAR_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 1)}"
[[ "$PAR_JOBS" =~ ^[0-9]+$ ]] || PAR_JOBS="$(nproc 2>/dev/null || echo 1)"
((PAR_JOBS < 1)) && PAR_JOBS=1
QUEUE_DIR="$TEMP_DIR/queue"
declare -gA JOB_PID=() JOB_LABEL=() JOB_LOG=() JOB_RC=()
JOB_SEQ=0
if ((PAR_JOBS > 1)); then
	mkdir -p "$QUEUE_DIR"
	export RVB_UTILS_SH COMPRESSION_LEVEL ENABLE_MODULE_UPDATE DEF_AUTHOR_NAME REMOVE_RV_INTEGRATIONS_CHECKS
	_reap_done() {
		local id rc
		for id in "${!JOB_PID[@]}"; do
			[ -f "${JOB_RC[$id]}" ] || { kill -0 "${JOB_PID[$id]}" 2>/dev/null && continue || echo 137 >"${JOB_RC[$id]}"; }
			rc=$(cat "${JOB_RC[$id]}" 2>/dev/null) || rc=1
			[ -n "${GITHUB_REPOSITORY:-}" ] && echo "::group::Building ${JOB_LABEL[$id]}"
			cat "${JOB_LOG[$id]}" 2>/dev/null
			[ -n "${GITHUB_REPOSITORY:-}" ] && echo "::endgroup::"
			[ "$rc" = 0 ] || epr "Build failed for ${JOB_LABEL[$id]} (exit $rc)"
			rm -f "${JOB_LOG[$id]}" "${JOB_RC[$id]}"
			unset "JOB_PID[$id]" "JOB_LABEL[$id]" "JOB_LOG[$id]" "JOB_RC[$id]"
		done
	}
	_wait_slot() { while ((${#JOB_PID[@]} >= PAR_JOBS)); do _reap_done; ((${#JOB_PID[@]} < PAR_JOBS)) && break; wait -n >/dev/null 2>&1 || true; done; }
	_enqueue_build() {
		_wait_slot
		local id=$((JOB_SEQ + 1)); JOB_SEQ=$id
		(
			set +e
			RVB_CHILD=1 bash -c 'set -euo pipefail; shopt -s nullglob; source "$RVB_UTILS_SH"; set_prebuilts; build_rv "$1"' _ "$1" >"$QUEUE_DIR/$id.log" 2>&1
			echo $? >"$QUEUE_DIR/$id.rc"
		) &
		JOB_PID[$id]=$!; JOB_LABEL[$id]="$2"; JOB_LOG[$id]="$QUEUE_DIR/$id.log"; JOB_RC[$id]="$QUEUE_DIR/$id.rc"
	}
fi
_run_build() {
	if ((PAR_JOBS <= 1)); then
		[ -n "${GITHUB_REPOSITORY:-}" ] && echo "::group::Building $1"
		build_rv "$2" || epr "Build failed for $1"
		[ -n "${GITHUB_REPOSITORY:-}" ] && echo "::endgroup::"
	else
		_enqueue_build "$2" "$1"
	fi
}

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
echo "${DEF_AUTHOR_NAME}${DEF_AUTHOR_PAGE:+ ($DEF_AUTHOR_PAGE)}" > "${MODULE_TEMPLATE_DIR}/maintainer.txt"

for table_name in $(toml_get_table_names); do
	if [ -z "$table_name" ]; then continue; fi
	if [ -n "$ALLOWED_APPS" ] && ! [[ "$table_name" =~ $ALLOWED_APPS ]]; then continue; fi
	t=$(toml_get_table "$table_name")
	enabled=$(toml_get "$t" enabled) || enabled=true
	vtf "$enabled" "enabled"
	if [ "$enabled" = false ]; then continue; fi

	declare -A app_args
	patches_src=$(toml_get "$t" patches-source) || patches_src=$DEF_PATCHES_SRC
	patches_src_host=$(toml_get "$t" patches-source-host) || patches_src_host=$DEF_PATCHES_SRC_HOST
	patches_ver=$(toml_get "$t" patches-version) || patches_ver=$DEF_PATCHES_VER
	[ -n "${OVERRIDE_PATCHES_VERSION:-}" ] && patches_ver="$OVERRIDE_PATCHES_VERSION"
	[ "$patches_ver" = "both" ] && { [[ "${1:-}" == *"beta"* ]] && patches_ver="beta" || patches_ver="stable"; }
	cli_src=$(toml_get "$t" cli-source) || cli_src=$DEF_CLI_SRC
	cli_src_host=$(toml_get "$t" cli-source-host) || cli_src_host=$DEF_CLI_SRC_HOST
	cli_ver=$(toml_get "$t" cli-version) || cli_ver=$DEF_CLI_VER
	cli_type=$(toml_get "$t" cli-type) || cli_type="morphe"
	# Explicit downstream types override every source field. Hosts remain valid
	# placeholders because the normal source validation still runs, but no
	# source download/list operation is performed for these patcher types.
	if [ "$cli_type" = "none" ] || [ "$cli_type" = "apksigner" ]; then
		cli_src="$cli_type"
		patches_src="$cli_type"
		cli_src_host="github"
		patches_src_host="github"
	fi
	if ! isoneof "$cli_src_host" github gitlab; then abort "ERROR: cli-source-host '$cli_src_host' is not a valid option for '$table_name': only 'github' or 'gitlab' is allowed"; fi
	resolve_patcher "$cli_src" "$cli_type"
	# Engine branding is determined by the explicit patcher type resolved by
	# patchers.sh. A configured legacy brand may still identify the patch source.
	case "$PATCHER_KIND" in
		morphe)    resolved_engine_brand="Morphe" ;;
		revanced)  resolved_engine_brand="ReVanced" ;;
		xposed)    resolved_engine_brand="NPatch" ;;
		instafel)  resolved_engine_brand="Instafel" ;;
		apksigner) resolved_engine_brand="Signed" ;;
		none)      resolved_engine_brand="" ;;
		*)         resolved_engine_brand="" ;;
	esac

	# Parse patch sources: may be a single string or multiline (quoted list)
	IFS=$'\n'
	p_srcs=($(list_args "$patches_src" | tr -d \"\')); [ ${#p_srcs[@]} -eq 0 ] && p_srcs=("$patches_src")
	p_hosts=($(list_args "$patches_src_host" | tr -d \"\')); [ ${#p_hosts[@]} -eq 0 ] && p_hosts=("$patches_src_host")
	p_vers=($(list_args "$patches_ver" | tr -d \"\')); [ ${#p_vers[@]} -eq 0 ] && p_vers=("$patches_ver")
	unset IFS
	for h in "${p_hosts[@]}"; do
		if ! isoneof "$h" github gitlab; then abort "ERROR: patches-source-host '$h' is not a valid option for '$table_name': only 'github' or 'gitlab' is allowed"; fi
	done

	cli_filter=$(toml_get "$t" cli-source-filter) || cli_filter=""
	cli_tag_filter=$(toml_get "$t" cli-tag-filter) || cli_tag_filter=""
	cli_name_filter=$(toml_get "$t" cli-release-name-filter) || cli_name_filter=""
	patches_filter=$(toml_get "$t" patches-source-filter) || patches_filter=""
	patches_tag_filter=$(toml_get "$t" patches-tag-filter) || patches_tag_filter=""
	patches_name_filter=$(toml_get "$t" patches-release-name-filter) || patches_name_filter=""
	if ! PREBUILTS="$(get_prebuilts "$cli_src_host" "$cli_src" "$cli_ver" "$patches_src_host" "$patches_src" "$patches_ver" "$cli_type" "$cli_filter" "$patches_filter" "$cli_tag_filter" "$patches_tag_filter" "$cli_name_filter" "$patches_name_filter")"; then
		epr "Could not get prebuilts"
		continue
	fi
	read -r cli_jar patches_jar_all <<< "$PREBUILTS"
	app_args[cli]=$cli_jar
	app_args[ptjar]=$patches_jar_all
	app_args[cli_source]=$cli_src
	app_args[cli_type]=$cli_type
	app_args[patches_sources_all]="${p_srcs[*]}"

	# Build aggregated patches_ref and changelog_url from all sources
	patches_ref_all="" changelog_url_all=""
	for i in "${!p_srcs[@]}"; do
		psrc="${p_srcs[$i]}"
		phost="${p_hosts[$i]:-${p_hosts[0]}}"
		# Find the downloaded bundle for this source to get actual version
		pdir=${psrc%/*}; pdir=${TEMP_DIR}/${pdir,,}-rv
		case "$PATCHER_FLOW" in
			xposed-module) pfile=$(find "$pdir" -name '*.apk' 2>/dev/null | sort | tail -1) ;;
			instafel-workflow) pfile=$(find "$pdir" -name 'ifl-patcher*.jar' 2>/dev/null | sort | tail -1) ;;
			*) pfile=$(find "$pdir" \( -name 'patches-*.rvp' -o -name 'patches-*.jar' -o -name '*.mpp' \) 2>/dev/null | sort | tail -1) ;;
		esac
		if [ -n "$pfile" ]; then
			pfilename=${pfile##*/}
			
			if [ -f "${pdir}/tag_name.txt" ]; then
				ptag=$(cat "${pdir}/tag_name.txt")
			else
				pver_actual=${pfilename#*-}; pver_actual=${pver_actual%.*}
				ptag="v${pver_actual#v}"
			fi
			
			patches_ref_all+="${psrc%%/*}/${pfilename} "
			if [ "$phost" = github ]; then
				changelog_url_all+="https://github.com/${psrc}/releases/tag/${ptag} "
			else
				changelog_url_all+="https://gitlab.com/${psrc}/-/releases/${ptag} "
			fi
		fi
	done
	app_args[patches_src]=${p_srcs[0]}
	app_args[patches_ref]="${patches_ref_all% }"
	app_args[changelog_url]="${changelog_url_all% }"
	app_args[brand]=$(toml_get "$t" brand) || app_args[brand]="${DEF_BRAND:-${p_srcs[0]%%/*}}"
	configured_engine_brand=$(toml_get "$t" engine-brand) || configured_engine_brand=""
	app_args[engine_brand]="${configured_engine_brand:-$resolved_engine_brand}"
	app_args[patch_brand]=$(toml_get "$t" patch-brand) || app_args[patch_brand]="$DEF_PATCH_BRAND"
	app_args[variant]=$(toml_get "$t" variant) || app_args[variant]="$DEF_VARIANT"
	app_args[sub_variant]=$(toml_get "$t" sub-variant) || app_args[sub_variant]="$DEF_SUB_VARIANT"
	[ -z "${app_args[sub_variant]}" ] && { app_args[sub_variant]=$(toml_get "$t" sub_variant) || app_args[sub_variant]="$DEF_SUB_VARIANT"; }

	app_args[excluded_patches]=$(toml_get "$t" excluded-patches) || app_args[excluded_patches]=""
	if [ -n "${app_args[excluded_patches]}" ] && [[ ${app_args[excluded_patches]} != *'"'* ]]; then abort "patch names inside excluded-patches must be quoted"; fi
	app_args[included_patches]=$(toml_get "$t" included-patches) || app_args[included_patches]=""
	if [ -n "${app_args[included_patches]}" ] && [[ ${app_args[included_patches]} != *'"'* ]]; then abort "patch names inside included-patches must be quoted"; fi
	app_args[exclusive_patches]=$(toml_get "$t" exclusive-patches) || app_args[exclusive_patches]=false
	app_args[version]=$(toml_get "$t" version) || app_args[version]="auto"
	app_args[version_code]=$(toml_get "$t" version-code) || app_args[version_code]=""
	app_args[app_name]=$(toml_get "$t" app-name) || app_args[app_name]=$table_name
	app_args[patcher_args]=$(toml_get "$t" patcher-args) || app_args[patcher_args]=""
	# Preserve the extended source/download controls supported by utils.sh.
	for opt in \
		github-dlurl-regex github-release-regex github-release-name-regex github-dlurl-exclude-filter github-dlurl-source \
		gitlab-dlurl-regex gitlab-release-regex gitlab-release-name-regex gitlab-dlurl-exclude-filter \
		forgejo-dlurl-regex forgejo-release-regex forgejo-release-name-regex forgejo-dlurl-exclude-filter \
		apkmirror-example-url apkmirror-release-filter check-sig prefer-dl-mode custom-microg-patches version-filter; do
		key="${opt//-/_}"
		app_args[$key]=$(toml_get "$t" "$opt") || app_args[$key]=""
	done
	app_args[check_sig]=$(toml_get "$t" check-sig) || app_args[check_sig]="false"
	[ -n "${app_args[check_sig]}" ] || app_args[check_sig]="false"
	app_args[github_regex]="${app_args[github_dlurl_regex]}"
	app_args[gitlab_regex]="${app_args[gitlab_dlurl_regex]}"
	app_args[forgejo_regex]="${app_args[forgejo_dlurl_regex]}"
	app_args[apkmirror_version_filter]="${app_args[version_filter]}"
	for opt in cli-source-filter cli-tag-filter cli-release-name-filter \
		patches-source-filter patches-tag-filter patches-release-name-filter; do
		key="${opt//-/_}"
		app_args[$key]=$(toml_get "$t" "$opt") || app_args[$key]=""
	done
	app_args[table]=$table_name
	app_args[build_mode]=$(toml_get "$t" build-mode) || app_args[build_mode]="$DEF_BUILD_MODE"
	if ! isoneof "${app_args[build_mode]}" both apk module; then
		abort "ERROR: build-mode '${app_args[build_mode]}' is not a valid option for '${table_name}': only 'both', 'apk' or 'module' is allowed"
	fi
	app_args[include_stock]=$(toml_get "$t" include-stock) && {
		if ! isoneof "${app_args[include_stock]}" disable merged split; then
			abort "ERROR: include-stock '${app_args[include_stock]}' is not a valid option for '${table_name}': only 'disable', 'merged' or 'split' is allowed"
		fi
	} || app_args[include_stock]=merged

	for dl_from in "${DL_SRCS[@]}"; do
		if app_args[${dl_from}_dlurl]=$(toml_get "$t" "${dl_from}-dlurl"); then
			app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%/}
			app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%download}
			app_args[${dl_from}_dlurl]=${app_args[${dl_from}_dlurl]%/}
			app_args[dl_from]=${dl_from}
		else
			app_args[${dl_from}_dlurl]=""
		fi
	done
	if [ -z "${app_args[dl_from]-}" ]; then abort "ERROR: no 'dlurl' option was set for '$table_name'. (${DL_SRCS[*]})"; fi
	app_args[arch]=$(toml_get "$t" arch) || app_args[arch]="$DEF_ARCH"
	arch_valid=true
	read -r -a arch_values <<< "${app_args[arch]}"
	[ "${#arch_values[@]}" -eq 0 ] && arch_values=("${app_args[arch]}")
	for arch_value in "${arch_values[@]}"; do
		if ! isoneof "$arch_value" "auto" "both" "all" "arm64-v8a" "arm-v7a" "x86_64" "x86"; then
			arch_valid=false
			break
		fi
	done
	if [ "$arch_valid" != true ]; then
		abort "wrong arch '${app_args[arch]}' for '$table_name'"
	fi

	app_args[pkg_name]=$(toml_get "$t" pkg-name) || app_args[pkg_name]=""
	app_args[patched_pkg_name]=$(toml_get "$t" patched-pkg-name) || app_args[patched_pkg_name]=""
	app_args[dpi]=$(toml_get "$t" dpi) || app_args[dpi]="$DEF_DPI"
	app_args[github_regex]=$(toml_get "$t" github-regex) || app_args[github_regex]=""
	app_args[github_release_regex]=$(toml_get "$t" github-release-regex) || app_args[github_release_regex]=""
	table_name_f=${table_name,,}
	table_name_f=${table_name_f// /-}
	app_args[module_prop_name]=$(toml_get "$t" module-prop-name) || app_args[module_prop_name]="${table_name_f}-${DEF_AUTHOR_NAME}"

	module_prop_name_b=${app_args[module_prop_name]}
	read -r -a arch_values <<< "${app_args[arch]}"
	[ "${#arch_values[@]}" -gt 0 ] || arch_values=("${app_args[arch]}")
	case " ${arch_values[*]} " in
		*" both "*) arch_values=(arm64-v8a arm-v7a) ;;
		*" all "*) arch_values=(arm64-v8a arm-v7a x86_64 x86) ;;
	esac
	for arch_value in "${arch_values[@]}"; do
		app_args[table]="$table_name ($arch_value)"
		app_args[arch]="$arch_value"
		app_args[module_prop_name]="$module_prop_name_b"
		case "$arch_value" in
			arm64-v8a) app_args[module_prop_name]="${module_prop_name_b}-arm64" ;;
			arm-v7a) app_args[module_prop_name]="${module_prop_name_b}-arm" ;;
		esac
		_run_build "${app_args[table]}" "$(declare -p app_args)"
	done
done
while ((PAR_JOBS > 1 && ${#JOB_PID[@]} > 0)); do
	_reap_done
	((${#JOB_PID[@]} > 0)) || break
	wait -n >/dev/null 2>&1 || true
done
rm -rf "$QUEUE_DIR"
rm -rf temp/tmp.*
if [ -z "$(ls -A1 "${BUILD_DIR}")" ]; then abort "All builds failed."; fi

if command -v python3 >/dev/null 2>&1; then
	python3 .github/scripts/generate_release_notes.py
fi

pr "Done"
