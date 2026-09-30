#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

# Engine is run with repo root as CWD (workflows, CI scripts) but lives beside
# utils.sh under scripts/; keep the absolute path for isolated worker shells.
RVB_UTILS_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
export RVB_UTILS_SH
source "$RVB_UTILS_SH"
echo '{}' > "$BUILD_JSON_FILE"
: > "${RVB_ERROR_LOG:-error.log}"
echo '[]' > "${RVB_ERROR_JSON:-error.json}"
echo '[]' > "${RVB_LOG_JSON:-build_log.json}"

CONFIG_FILE="config.toml"
ALLOWED_APPS=""
OUTPUT_DIR=""
PATCHES_VERSION_OVERRIDE=""

print_help() {
	cat <<'EOF'
Usage: build.sh [OPTIONS] [CONFIG_FILE]

Build patched APKs from a TOML configuration file.

Options:
  --config=PATH, --config PATH
      Path to the TOML config file (default: config.toml).
      Can also be passed as the first positional argument.

  --allowed-apps=REGEX, --allowed-apps REGEX
      Only build app tables whose name matches the given regex.

  --output=DIR, --output DIR
      Override the output directory for built APKs.

  --patches-version=VER, --patches-version VER
      Override the patches version for all apps.
      Values: stable | latest | both | <specific-tag>

  --clean, clean
      Remove all temp/build artifacts and exit.

  --help, -h
      Show this help message and exit.

Note:
  When building locally without pinned versions, run scripts/fetch_versions.sh
  first to discover and populate latest APK versions in state/app_versions.json.

For config file keys and per-app table options, see Documentation.md.

Environment variables:
  GITHUB_TOKEN              GitHub API token (increases rate limit; required for private repos)
  PARALLEL_JOBS             Number of parallel build jobs (default: nproc)
  NEXT_VER_CODE             Override version code for built APKs (default: YYYYMMDD)
  NORB                      Set to 'true' to skip rebuilding already-patched APKs

  Keystore / signing:
  RVB_KEYSTORE              Path to keystore file (default: ks.keystore)
  RVB_KEYSTORE_PASS         Keystore + key password (default: 123456789)
  RVB_KEY_ALIAS             Key alias in keystore (default: jhc)
  KEYSTORE_FILE             Alternative: path to an existing keystore file
  KEYSTORE_BASE64           Alternative: base64-encoded keystore content
  KEYSTORE_PASSWORD         Alternative: keystore password (alias for RVB_KEYSTORE_PASS)
  KEYSTORE_KEY_PASSWORD     Alternative: key password if different from keystore password
  KEYSTORE_ALIAS            Alternative: key alias (alias for RVB_KEY_ALIAS)

  Downloads:
  RVB_DL_MAX_TIME           Max download time in seconds (default: 1800)
  APK_CACHE_DIR             Directory to cache downloaded APKs (default: TEMP_DIR/apks)
  UPLOAD_APKS_REPO          GitHub repo (user/repo) to upload built APKs to

  Cloudflare bypass (cf_get.py):
  CF_COOKIES                Cloudflare cookies to inject into protected downloads
  TRAWL_URL                 Base URL of a Trawl/FlareSolverr-8191 sidecar
  CFB_URL                   Base URL of a cf-bypasser sidecar (default: http://localhost:8000)
  FS_URL                    Base URL of a FlareSolverr instance
  FLARESOLVERR_URL          Alias for FS_URL
  CF_BYPASS_SOLVER_FS_URL   Alias for FS_URL (legacy name)

  Patcher behaviour:
  RVB_CHECK_SIG             Verify APK signature before patching (default: false)
  RVB_MORPHE_PASSTHROUGH    Set to 'false' to use legacy merge-at-download Morphe flow
  RVB_INSTAFEL_DEFAULT_PATCHES   Space-separated default patches for Instafel
  RVB_INSTAFEL_FALLBACK_COMMIT   Instafel fallback git commit to use if latest fails

  Paths (usually auto-detected):
  ANDROID_HOME              Android SDK root (also: ANDROID_SDK_ROOT)
  JAVA_HOME                 Java installation root
  TMPDIR                    Override system temp directory
EOF
}

[ $# -eq 0 ] && { print_help; exit 0; }

while [ $# -gt 0 ]; do
	case "$1" in
		--help|-h) print_help; exit 0 ;;
		--config=*) CONFIG_FILE="${1#*=}" ;;
		--config) shift; CONFIG_FILE="${1:?missing value for --config}" ;;
		--allowed-apps=*) ALLOWED_APPS="${1#*=}" ;;
		--allowed-apps) shift; ALLOWED_APPS="${1:?missing value for --allowed-apps}" ;;
		--output=*) OUTPUT_DIR="${1#*=}" ;;
		--output) shift; OUTPUT_DIR="${1:?missing value for --output}" ;;
		--patches-version=*) PATCHES_VERSION_OVERRIDE="${1#*=}" ;;
		--patches-version) shift; PATCHES_VERSION_OVERRIDE="${1:?missing value for --patches-version}" ;;
		--clean) CLEAN_REQUESTED=true ;;
		clean) CLEAN_REQUESTED=true ;;
		*) [ "$CONFIG_FILE" = config.toml ] && CONFIG_FILE="$1" || abort "Unknown option: $1" ;;
	esac
	shift
done

if [ -n "$OUTPUT_DIR" ]; then BUILD_DIR="$OUTPUT_DIR"; fi

trap "abort" INT

if [ "${CLEAN_REQUESTED:-false}" = true ]; then
	rm -rf "$TEMP_DIR" "$BUILD_DIR" build.md error.log error.json build_log.json error.md build.json.lock
	exit 0
fi

jq --version >/dev/null || abort "\`jq\` is not installed. install it with 'apt install jq' or equivalent"
java --version >/dev/null || abort "\`java\` is not installed. install it with 'apt install openjdk-21-jre' or equivalent"
zip --version >/dev/null || abort "\`zip\` is not installed. install it with 'apt install zip' or equivalent"

set_prebuilts

vtf() { if ! isoneof "${1}" "true" "false"; then abort "ERROR: '${1}' is not a valid option for '${2}': only true or false is allowed"; fi; }

# -- Main config --
toml_prep "$CONFIG_FILE" || { print_help; abort "could not find config file '$CONFIG_FILE'"; }
main_config_t=$(toml_get_table_main)
COMPRESSION_LEVEL=$(toml_get "$main_config_t" compression-level) || COMPRESSION_LEVEL="9"
REMOVE_RV_INTEGRATIONS_CHECKS=$(toml_get "$main_config_t" remove-rv-integrations-checks) || REMOVE_RV_INTEGRATIONS_CHECKS="false"
DEF_PATCHES_VER=$(toml_get "$main_config_t" patches-version) || DEF_PATCHES_VER="both"
# "both" means "whichever pool this config is for", and the only signal for that is
# the file being built: the beta pool is configs/beta_build.json (a hand-written
# config names itself with .beta.).
[ "$DEF_PATCHES_VER" = "both" ] && { if [[ "${1:-}" == *"beta"* ]]; then DEF_PATCHES_VER="beta"; else DEF_PATCHES_VER="stable"; fi; }
DEF_CLI_VER=$(toml_get "$main_config_t" cli-version) || DEF_CLI_VER="stable"
DEF_PATCHES_SRC=$(toml_get "$main_config_t" patches-source) || DEF_PATCHES_SRC="MorpheApp/morphe-patches"
DEF_PATCHES_SRC_HOST=$(toml_get "$main_config_t" patches-source-host) || DEF_PATCHES_SRC_HOST="github"
DEF_CLI_TYPE=$(toml_get "$main_config_t" cli-type) || DEF_CLI_TYPE=""
DEF_CLI_SRC=$(toml_get "$main_config_t" cli-source) || DEF_CLI_SRC=""
if [ -z "$DEF_CLI_SRC" ]; then
	case "${DEF_CLI_TYPE,,}" in
		morphe) DEF_CLI_SRC="MorpheApp/morphe-desktop" ;;
		revanced) DEF_CLI_SRC="ReVanced/revanced-cli" ;;
		npatch) DEF_CLI_SRC="7723mod/NPatch" ;;
		lspatch) DEF_CLI_SRC="JingMatrix/LSPatch" ;;
		instafel) DEF_CLI_SRC="instafel/p-rel" ;;
		none|apksigner) DEF_CLI_SRC="" ;;
		*) DEF_CLI_SRC="MorpheApp/morphe-desktop" ;;
	esac
fi
DEF_CLI_SRC_HOST=$(toml_get "$main_config_t" cli-source-host) || DEF_CLI_SRC_HOST="github"
DEF_ENGINE_BRAND=$(toml_get "$main_config_t" engine-brand) || DEF_ENGINE_BRAND=""
DEF_PATCH_BRAND=$(toml_get "$main_config_t" patch-brand) || DEF_PATCH_BRAND=""
DEF_VARIANT=$(toml_get "$main_config_t" variant) || DEF_VARIANT=""
DEF_SUB_VARIANT=$(toml_get "$main_config_t" sub-variant) || DEF_SUB_VARIANT=""
DEF_DPI=$(toml_get "$main_config_t" dpi) || DEF_DPI="nodpi anydpi auto"
DEF_ARCH=$(toml_get "$main_config_t" arch) || DEF_ARCH="all arm64-v8a x86_64 armeabi-v7a x86"
DEF_BUILD_MODE=$(toml_get "$main_config_t" build-mode) || DEF_BUILD_MODE="apk"
DEF_AUTHOR_NAME=$(toml_get "$main_config_t" author) || DEF_AUTHOR_NAME="sharath-5br2r"
DEF_AUTHOR_PAGE=$(toml_get "$main_config_t" author-page) || DEF_AUTHOR_PAGE="github.com/sharath-5br2r-apps/revanced-morphe-xposed-builder"
mkdir -p "$TEMP_DIR" "$BUILD_DIR"

# Concurrent table builds. The ONLY knob is the PARALLEL_JOBS env set in
# .github/workflows/build.yml — it is not read from any config file.
# 1 (default) keeps the historical fully-sequential path untouched.
PAR_JOBS="${PARALLEL_JOBS:-1}"
[[ "$PAR_JOBS" =~ ^[0-9]+$ ]] || { epr "PARALLEL_JOBS '$PAR_JOBS' is not a number; falling back to 1"; PAR_JOBS=1; }
((PAR_JOBS < 1)) && PAR_JOBS=1
((PAR_JOBS > 8)) && { wpr "capping parallel-jobs at 8 (runner is 4-core/16GB)"; PAR_JOBS=8; }
pr "PARALLEL_JOBS: $PAR_JOBS"
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
echo "${DEF_AUTHOR_NAME}${DEF_AUTHOR_PAGE:+ ($DEF_AUTHOR_PAGE)}" > "${MODULE_TEMPLATE_DIR}/maintainer.txt"

# -- Build process pool (parallel-jobs > 1) --
# Each table build runs as a fresh `bash -c` child that re-sources utils.sh,
# so PATCHER_*/PATCH_OUTPUT globals and in-process caches are per-job by
# construction. Children log to temp/queue/<id>.log and drop an rc file; the
# parent replays finished logs inside their own ::group:: (completion order)
# so the Actions log stays as clean as the sequential one. Serial mode
# (PAR_JOBS=1) bypasses all of this and behaves exactly as before.
QUEUE_DIR="$TEMP_DIR/queue"
# =() initializers are required: bash 5.3+ treats bare `declare -gA` as unset
# under `set -u`, breaking ${#JOB_PID[@]} on the empty pool.
declare -gA JOB_PID=() JOB_LABEL=() JOB_LOG=() JOB_RC=()
JOB_SEQ=0

if ((PAR_JOBS > 1)); then
	mkdir -p "$QUEUE_DIR"
	# vars build_rv reads as globals; children get them through the env
	export RVB_UTILS_SH COMPRESSION_LEVEL ENABLE_MODULE_UPDATE DEF_AUTHOR_NAME REMOVE_RV_INTEGRATIONS_CHECKS RVB_ERROR_LOG RVB_ERROR_JSON RVB_LOG_JSON

	_reap_done() {
		local id rc
		for id in "${!JOB_PID[@]}"; do
			if [ ! -f "${JOB_RC[$id]}" ]; then
				# still running → keep waiting; wrapper died without an rc (killed
				# externally, rare) → synthesize a failure so the drain can't hang
				kill -0 "${JOB_PID[$id]}" 2>/dev/null && continue
				echo 137 >"${JOB_RC[$id]}"
			fi
			rc=$(cat "${JOB_RC[$id]}" 2>/dev/null) || rc=1
			if [ -n "${GITHUB_REPOSITORY:-}" ]; then
				echo "::group::Building ${JOB_LABEL[$id]}"
			else
				pr "Building ${JOB_LABEL[$id]}"
			fi
			cat "${JOB_LOG[$id]}" 2>/dev/null
			if [ -n "${GITHUB_REPOSITORY:-}" ]; then
				echo "::endgroup::"
			else
				pr "End of ${JOB_LABEL[$id]}"
			fi
			if [ "$rc" != 0 ]; then
				CURRENT_APP_NAME="${JOB_LABEL[$id]}" epr "Build failed for ${JOB_LABEL[$id]} (exit $rc)"
			fi
			rm -f "${JOB_LOG[$id]}" "${JOB_RC[$id]}"
			unset "JOB_PID[$id]" "JOB_LABEL[$id]" "JOB_LOG[$id]" "JOB_RC[$id]"
		done
		return 0
	}
	_wait_slot() {
		while ((${#JOB_PID[@]} >= PAR_JOBS)); do
			_reap_done
			((${#JOB_PID[@]} < PAR_JOBS)) && break
			wait -n >/dev/null 2>&1 || true
			sleep 1
		done
		return 0
	}
	_enqueue_build() {
		_wait_slot
		local id=$((JOB_SEQ + 1)); JOB_SEQ=$id
		(
			set +e
			export CURRENT_APP_NAME="$2"
			if [[ "$-" == *x* ]]; then
				RVB_CHILD=1 bash -xc 'set -euo pipefail; shopt -s nullglob; source "$RVB_UTILS_SH"; set_prebuilts; build_rv "$1"' _ "$1" >"$QUEUE_DIR/$id.log" 2>&1
			else
				RVB_CHILD=1 bash -c 'set -euo pipefail; shopt -s nullglob; source "$RVB_UTILS_SH"; set_prebuilts; build_rv "$1"' _ "$1" >"$QUEUE_DIR/$id.log" 2>&1
			fi
			echo $? >"$QUEUE_DIR/$id.rc"
		) &
		JOB_PID[$id]=$!; JOB_LABEL[$id]="$2"; JOB_LOG[$id]="$QUEUE_DIR/$id.log"; JOB_RC[$id]="$QUEUE_DIR/$id.rc"
	}
fi
_run_build() {
	if ((PAR_JOBS <= 1)); then
		if [ -n "${GITHUB_REPOSITORY:-}" ]; then
			echo "::group::Building $1"
		else
			pr "Building $1"
		fi
		export CURRENT_APP_NAME="$1"
		build_rv "$2" || epr "Build failed for $1"
		if [ -n "${GITHUB_REPOSITORY:-}" ]; then
			echo "::endgroup::"
		else
			pr "End of $1"
		fi
	else
		_enqueue_build "$2" "$1"
	fi
}

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
	# "both" is not a channel — it is routing, resolved here from the config being
	# built: a beta-named file, or a file-level default already set to beta.
	[ "$patches_ver" = "both" ] && { if [[ "${1:-}" == *"beta"* ]] || [ "$DEF_PATCHES_VER" = "beta" ]; then patches_ver="beta"; else patches_ver="stable"; fi; }
	[ -n "$PATCHES_VERSION_OVERRIDE" ] && patches_ver="$PATCHES_VERSION_OVERRIDE"
	cli_type=$(toml_get "$t" cli-type) || cli_type="$DEF_CLI_TYPE"
	cli_src=$(toml_get "$t" cli-source) || cli_src=""
	# Generated JSON/TOML from older revisions used cli-source as the flow
	# selector. Infer it when cli-type is absent so stale batch parts remain
	# buildable until the next config regeneration.
	[ -n "$cli_type" ] || case "${cli_src,,}" in
		none) cli_type="none" ;;
		apksigner) cli_type="apksigner" ;;
		*) cli_type="morphe" ;;
	esac
	cli_type="${cli_type,,}"
	if [ -z "$cli_src" ]; then
		case "$cli_type" in
			morphe) cli_src="MorpheApp/morphe-desktop" ;;
			revanced) cli_src="ReVanced/revanced-cli" ;;
			npatch) cli_src="7723mod/NPatch" ;;
			lspatch) cli_src="JingMatrix/LSPatch" ;;
			instafel) cli_src="instafel/p-rel" ;;
			none|apksigner) cli_src="" ;;
			*) cli_src="$DEF_CLI_SRC" ;;
		esac
	fi
	cli_src_host=$(toml_get "$t" cli-source-host) || cli_src_host=$DEF_CLI_SRC_HOST
	cli_ver=$(toml_get "$t" cli-version) || cli_ver=$DEF_CLI_VER
	# Non-patching flows do not have a meaningful patch-app compatibility
	# query; enable the same bypass dynamically for all signer/no-op/NPatch
	# configurations, including generated legacy config fragments.
	case "$cli_type" in
		npatch|lspatch|none|apksigner) skip_patch_app_check=true ;;
	esac
	# Explicit none/apksigner types have no CLI or patch bundle.
	# Setting both sources to empty triggers the skip logic in get_prebuilts.
	if [ "$cli_type" = "none" ] || [ "$cli_type" = "apksigner" ]; then
		cli_src=""
		patches_src=""
		cli_src_host=""
		patches_src_host=""
	fi
	if [ -n "$cli_src_host" ] && ! isoneof "$cli_src_host" github gitlab codeberg forgejo gitea none; then abort "ERROR: cli-source-host '$cli_src_host' is not a valid option for '$table_name': expected github, gitlab, codeberg, forgejo, gitea, or none"; fi
	resolve_patcher "$cli_src" "$cli_type"
	# Engine branding is determined by the explicit patcher type resolved by
	# patchers.sh. A configured legacy brand may still identify the patch source.
	case "$PATCHER_KIND" in
		morphe)    resolved_engine_brand="Morphe" ;;
		revanced)  resolved_engine_brand="ReVanced" ;;
		npatch)    resolved_engine_brand="NPatch" ;;
		lspatch)   resolved_engine_brand="LSPatch" ;;
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
		if [ -n "$h" ] && ! isoneof "$h" github gitlab codeberg forgejo gitea none; then abort "ERROR: patches-source-host '$h' is not a valid option for '$table_name': expected github, gitlab, codeberg, forgejo, gitea, or none"; fi
	done

	cli_filter=$(toml_get "$t" cli-source-filter) || cli_filter=""
	cli_tag_filter=$(toml_get "$t" cli-tag-filter) || cli_tag_filter=""
	cli_name_filter=$(toml_get "$t" cli-release-name-filter) || cli_name_filter=""
	patches_filter=$(toml_get "$t" patches-source-filter) || patches_filter=""
	patches_tag_filter=$(toml_get "$t" patches-tag-filter) || patches_tag_filter=""
	patches_name_filter=$(toml_get "$t" patches-release-name-filter) || patches_name_filter=""
	# NOTE: called directly, not via $(...), so the __PREBUILTS_CACHE__ write in
	# get_prebuilts survives in this shell (see get_prebuilts in utils.sh).
	if ! get_prebuilts "$cli_src_host" "$cli_src" "$cli_ver" "$patches_src_host" "$patches_src" "$patches_ver" "$cli_type" "$cli_filter" "$patches_filter" "$cli_tag_filter" "$patches_tag_filter" "$cli_name_filter" "$patches_name_filter"; then
		epr "Could not get prebuilts"
		continue
	fi
	read -r -a __pb <<< "$__PREBUILTS_RESULT"
	cli_jar=${__pb[0]}
	patches_jar_all="${__pb[*]:1}"
	# Resolved patch bundles, index-aligned with p_srcs (both derive from the same
	# patches_src string via list_args), so metadata can name the exact file used.
	__pb_patches=("${__pb[@]:1}")
	app_args[cli]=$cli_jar
	app_args[ptjar]=$patches_jar_all
	app_args[cli_source]=$cli_src
	app_args[cli_type]=$cli_type
	app_args[patches_sources_all]="${p_srcs[*]}"

	# Build aggregated patches_ref and changelog_url from all sources
	patches_ref_all="" changelog_url_all=""
	for i in "${!p_srcs[@]}"; do
		psrc="${p_srcs[$i]}"
		# The explicit none or empty patcher has no patch bundle. Do not search for a
		# synthetic temp/none-rv directory or manufacture patch metadata.
		[ -z "$psrc" ] || [ "${psrc,,}" = none ] && continue
		phost="${p_hosts[$i]:-${p_hosts[0]}}"
		# Use the exact bundle resolved for THIS build (index-aligned with p_srcs)
		# instead of re-scanning the folder, which would report the highest-sorted
		# version when several versions of the same repo coexist.
		pfile="${__pb_patches[$i]:-}"
		if [ -n "$pfile" ]; then
			pdir=$(dirname "$pfile")
			pfilename=${pfile##*/}
			
			if [ -f "${pfile}.tag" ]; then
				ptag=$(cat "${pfile}.tag")
			elif [ -f "${pdir}/tag_name.txt" ]; then
				ptag=$(cat "${pdir}/tag_name.txt")
			else
				pver_actual=${pfilename#*-}; pver_actual=${pver_actual%.*}
				ptag="v${pver_actual#v}"
			fi
			
			patches_ref_all+="${psrc%%/*}/${pfilename} "
			# One owner for the release-page shape (utils.sh). An unrecognised host
			# contributes no link rather than a guessed one.
			if cl_url=$(source_release_web_url "$phost" "$psrc" "$ptag"); then
				changelog_url_all+="${cl_url} "
			fi
		fi
	done
	app_args[patches_src]=${p_srcs[0]}
	app_args[patches_ref]="${patches_ref_all% }"
	app_args[patches_version]="$patches_ver"
	app_args[changelog_url]="${changelog_url_all% }"
	configured_engine_brand=$(toml_get "$t" engine-brand) || configured_engine_brand=""
	app_args[engine_brand]="${configured_engine_brand:-$resolved_engine_brand}"
	app_args[patch_brand]=$(toml_get "$t" patch-brand) || app_args[patch_brand]="$DEF_PATCH_BRAND"
	app_args[variant]=$(toml_get "$t" variant) || app_args[variant]="$DEF_VARIANT"
	app_args[sub_variant]=$(toml_get "$t" sub-variant) || app_args[sub_variant]="$DEF_SUB_VARIANT"

	app_args[excluded_patches]=$(toml_get "$t" excluded-patches) || app_args[excluded_patches]=""
	if [ -n "${app_args[excluded_patches]}" ] && [[ ${app_args[excluded_patches]} != *'"'* ]]; then abort "patch names inside excluded-patches must be quoted"; fi
	app_args[included_patches]=$(toml_get "$t" included-patches) || app_args[included_patches]=""
	if [ -n "${app_args[included_patches]}" ] && [[ ${app_args[included_patches]} != *'"'* ]]; then abort "patch names inside included-patches must be quoted"; fi
	app_args[exclusive_patches]=$(toml_get "$t" exclusive-patches) || app_args[exclusive_patches]=false
	# The mirror of exclusive-patches: true means "apply every patch this bundle
	# offers for the app" instead of "apply only the listed ones". Boolean only - it
	# does not take the patch-source form exclusive-patches accepts - and it cannot
	# be combined with it. utils.sh expands it into explicit names at patch time.
	# Placed right after exclusive-patches because the conflict check needs its value.
	app_args[inclusive_patches]=$(toml_get "$t" inclusive-patches) || app_args[inclusive_patches]=false
	if ! isoneof "${app_args[inclusive_patches]}" true false; then
		abort "ERROR: inclusive-patches '${app_args[inclusive_patches]}' for '$table_name' must be true or false (unlike exclusive-patches it takes no patch-source list)"
	fi
	if [ "${app_args[inclusive_patches]}" = true ] && [ "${app_args[exclusive_patches]}" != false ]; then
		abort "ERROR: inclusive-patches and exclusive-patches are opposites; set only one for '$table_name'"
	fi
	app_args[version]=$(toml_get "$t" version) || app_args[version]="auto"
	app_args[skip_patch_app_check]=$(toml_get "$t" skip-patch-app-check) || app_args[skip_patch_app_check]=false
	# `latest` is explicitly allowed to build the newest stock app even when
	# patch metadata has not caught up with its compatibility declaration.
	# Version fallback still handles download failures independently.
	[ "${app_args[version]}" = latest ] && app_args[skip_patch_app_check]=true
	case "${app_args[cli_type],,}" in
		npatch|lspatch|none|apksigner) app_args[skip_patch_app_check]=true ;;
	esac
	case "${PATCHER_KIND:-}" in
		npatch|lspatch) app_args[skip_patch_app_check]=true ;;
	esac
	app_args[version_code]=$(toml_get "$t" version-code) || app_args[version_code]=""
	app_args[skip_version_code_check]=$(toml_get "$t" skip-version-code-check) || app_args[skip_version_code_check]=false
	app_args[app_name]=$(toml_get "$t" app-name) || app_args[app_name]=$table_name
	app_args[patcher_args]=$(toml_get "$t" patcher-args) || app_args[patcher_args]=""
	# Preserve the extended source/download controls supported by utils.sh.
	for opt in \
		github-asset-regex \
		github-dlurl-regex github-release-regex github-release-name-regex github-dlurl-source \
		gitlab-dlurl-regex gitlab-release-regex gitlab-release-name-regex gitlab-dlurl-exclude-filter \
		forgejo-dlurl-regex forgejo-release-regex forgejo-release-name-regex forgejo-dlurl-exclude-filter \
		apkmirror-example-url apkmirror-release-filter check-sig prefer-dl-mode custom-microg-patches version-filter; do
		key="${opt//-/_}"
		app_args[$key]=$(toml_get "$t" "$opt") || app_args[$key]=""
	done
	app_args[check_sig]=$(toml_get "$t" check-sig) || app_args[check_sig]="false"
	[ -n "${app_args[check_sig]}" ] || app_args[check_sig]="false"
	app_args[github_asset_regex]=$(toml_get "$t" github-asset-regex) || app_args[github_asset_regex]=""
	[ -n "${app_args[github_asset_regex]}" ] || app_args[github_asset_regex]=$(toml_get "$t" github-regex) || app_args[github_asset_regex]=""
	app_args[github_regex]="${app_args[github_asset_regex]}"
	app_args[gitlab_regex]="${app_args[github_asset_regex]}"
	app_args[forgejo_regex]="${app_args[github_asset_regex]}"
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
	app_args[arch]="${arch_values[*]}"
	[ "${#arch_values[@]}" -eq 0 ] && arch_values=("${app_args[arch]}")
	for arch_value in "${arch_values[@]}"; do
		if ! isoneof "$arch_value" "auto" "both" "all" "arm64-v8a" "armeabi-v7a" "x86_64" "x86"; then
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
	# Keep the generic asset regex available to every release provider.
	app_args[github_regex]=$(toml_get "$t" github-regex) || app_args[github_regex]="${app_args[github_dlurl_regex]}"
	[ -n "${app_args[github_asset_regex]:-}" ] && app_args[github_regex]="${app_args[github_asset_regex]}"
	app_args[github_release_regex]=$(toml_get "$t" github-release-regex) || app_args[github_release_regex]=""
	table_name_f=${table_name,,}
	table_name_f=${table_name_f// /-}
	app_args[module_prop_name]=$(toml_get "$t" module-prop-name) || app_args[module_prop_name]="${table_name_f}-${DEF_AUTHOR_NAME}"

	# Automatically append -beta to the module ID for pre-release builds
	# so they have an independent update channel in Magisk. The channel value is
	# only ever "stable" or "beta"; the glob is the beta pool's own filename.
	if { [[ "${1:-}" == *"beta"* ]] || [ "${DEF_PATCHES_VER:-}" = "beta" ] || [ "${patches_ver:-}" = "beta" ]; } && [[ "${app_args[module_prop_name]}" != *"-beta"* ]]; then
		app_args[module_prop_name]="${app_args[module_prop_name]}-beta"
	fi

	module_prop_name_b=${app_args[module_prop_name]}
	read -r -a arch_values <<< "${app_args[arch]}"
	[ "${#arch_values[@]}" -gt 0 ] || arch_values=("${app_args[arch]}")
	case " ${arch_values[*]} " in
		*" both "*) arch_values=(arm64-v8a armeabi-v7a) ;;
	esac
	for arch_value in "${arch_values[@]}"; do
		app_args[table]="$table_name ($arch_value)"
		app_args[arch]="$arch_value"
		app_args[module_prop_name]="$module_prop_name_b"
		case "$arch_value" in
			arm64-v8a) app_args[module_prop_name]="${module_prop_name_b}-arm64" ;;
			armeabi-v7a) app_args[module_prop_name]="${module_prop_name_b}-arm" ;;
		esac
		_run_build "${app_args[table]}" "$(declare -p app_args)"
	done
done

# Drain the pool: replay every remaining job log as it finishes, then fold
# the per-job build.json fragments into the final catalog.
while ((PAR_JOBS > 1 && ${#JOB_PID[@]} > 0)); do
	_reap_done
	((${#JOB_PID[@]} > 0)) || break
	wait -n >/dev/null 2>&1 || true
	sleep 1
done
merge_build_info
rm -rf temp/tmp.* "$TEMP_DIR"/*-merge-tmp* "$TEMP_DIR"/*/*-merge-tmp* "$QUEUE_DIR" "$TEMP_DIR/dllocks" "$TEMP_DIR/apkslocks" "$TEMP_DIR/mergesplits_locks" "$TEMP_DIR"/morphe-stage-*
if [ -z "$(ls -A1 "${BUILD_DIR}")" ]; then abort "All builds failed."; fi

if command -v python3 >/dev/null 2>&1; then
	python3 .github/scripts/generate_release_notes.py || true
	if [ -f .github/scripts/generate_error_markdown.py ]; then
		python3 .github/scripts/generate_error_markdown.py . error.md || true
	fi
fi

pr "Done"
