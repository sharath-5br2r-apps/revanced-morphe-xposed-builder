#!/usr/bin/env bash

if [ -f .env ]; then
	echo >&2 -e "\033[0;32m[+] Using .env file for keystore and signing.\033[0m"
	source .env
fi
if [ -z "${KEYSTORE_BASE64:-}" ] || [ -z "${KEYSTORE_PASSWORD:-}" ] || [ -z "${KEYSTORE_ALIAS:-}" ]; then
	echo >&2 -e "\033[0;33m[!] Keystore information is not fully set. Please ensure KEYSTORE_BASE64, KEYSTORE_PASSWORD, and KEYSTORE_ALIAS are defined in .env or environment variables.\033[0m"
	echo >&2 -e "\033[0;33m[!] Auto generating values for KEYSTORE_BASE64, KEYSTORE_PASSWORD, and KEYSTORE_ALIAS.\033[0m"
	if [ ${GITHUB_REPOSITORY:-} ]; then
		echo >&2 -e "::warning::utils.sh [!] Keystore information is not fully set. Please ensure KEYSTORE_BASE64, KEYSTORE_PASSWORD, and KEYSTORE_ALIAS are defined in .env or environment variables.\n"
		echo >&2 -e "::warning::utils.sh [!] Auto generating values for KEYSTORE_BASE64, KEYSTORE_PASSWORD, and KEYSTORE_ALIAS.\n"
	fi
	source .env.default
fi
if [ -z "${KEYSTORE_KEY_PASSWORD:-}" ]; then
	echo >&2 -e "\033[0;32m[!] No KEYSTORE_KEY_PASSWORD provided, using KEYSTORE_PASSWORD instead. \033[0m"
	echo >&2 -e "::warning::utils.sh [!] No KEYSTORE_KEY_PASSWORD provided, using KEYSTORE_PASSWORD instead.\n"
	KEYSTORE_KEY_PASSWORD=${KEYSTORE_PASSWORD}
fi

set -u
MODULE_TEMPLATE_DIR="module"
CWD=$(pwd)
TEMP_DIR="temp"
BIN_DIR="bin"
BUILD_DIR="build"
DL_SRCS=("local" "repo" "direct" "github" "archive" "apkmirror" "uptodown" "apkpure" "apkcombo")
BUILD_JSON_FILE="build.json"
PATCH_OUTPUT=""
mkdir -p "$TEMP_DIR"

GH_TOKEN="${PERSONAL_ACCESS_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"
if [ "${GH_TOKEN-}" ]; then GH_HEADER="Authorization: token ${GH_TOKEN}"; else GH_HEADER=; fi
NEXT_VER_CODE=${NEXT_VER_CODE:-$(date +'%Y%m%d')}
OS=$(uname -o)
[[ $(uname -s) == *"NT"* ]] && javapathsep=";" || javapathsep=":"

declare -gA __PREBUILTS_CACHE__
declare -gA __PATCHES_LIST_CACHE__
declare -gA __PATCH_VER_CACHE__
declare -gA __PKG_VERS_CACHE__
declare -gA __DL_RESP_CACHE__

toml_prep() {
	if [ ! -f "$1" ]; then return 1; fi
	if [ "${1##*.}" == toml ]; then
		__TOML__=$(yq -o=json -I=0 "$1")
	elif [ "${1##*.}" == json ]; then
		__TOML__=$(cat "$1")
	else abort "config extension not supported"; fi
}
toml_get_table_names() { jq -r -e 'to_entries[] | select(.value | type == "object") | .key' <<<"$__TOML__"; }
toml_get_table_main() { jq -r -e 'to_entries | map(select(.value | type != "object")) | from_entries' <<<"$__TOML__"; }
toml_get_table() { jq -r -e ".\"${1}\"" <<<"$__TOML__"; }
toml_get() {
	local op quote_placeholder=$'\001'
	op=$(jq -r ".\"${2}\" | values" <<<"$1")
	if [ "$op" ]; then
		op="${op#"${op%%[![:space:]]*}"}"
		op="${op%"${op##*[![:space:]]}"}"
		op=${op//\\\'/$quote_placeholder}
		op=${op//"''"/$quote_placeholder}
		op=${op//"'"/'"'}
		op=${op//$quote_placeholder/$'\''}
		echo "$op"
	else return 1; fi
}

pr() { echo >&2 -e "\033[0;32m[+] ${1}\033[0m"; }
epr() {
	echo >&2 -e "\033[0;31m[-] ${1}\033[0m"
	if [ "${GITHUB_REPOSITORY-}" ]; then echo >&2 -e "::error::utils.sh [-] ${1}\n"; fi
}
wpr() {
	echo >&2 -e "\033[0;33m[!] ${1}\033[0m"
	if [ "${GITHUB_REPOSITORY-}" ]; then echo >&2 -e "::warning::utils.sh [!] ${1}\n"; fi
}
abort() {
	epr "ABORT: ${1-}"
	rm -rf ./${TEMP_DIR}/*tmp.* ./${TEMP_DIR}/*/*tmp.* ./${TEMP_DIR}/*-temporary-files ./${TEMP_DIR}/*.apk-temporary-files ./*-temporary-files
	trap - SIGTERM SIGINT EXIT
	exit 1
}
java() { env -i PATH="$PATH" HOME="$HOME" LANG="${LANG:-en_US.UTF-8}" java --enable-native-access=ALL-UNNAMED "$@"; }

pr "Setting up Keystore"
base64 -d <<<"$KEYSTORE_BASE64" >$TEMP_DIR/ks.keystore

parse_host_spec() {
	local spec="${1,,}"
	local raw_spec="$1"
	local host_var_name="${2:-host}"
	local instance_var_name="${3:-host_instance}"

	local host_type="github" host_inst=""

	if [[ "$spec" == *"|"* ]]; then
		host_inst="${raw_spec%%|*}"
		host_type="${spec##*|}"
		if [ -z "$host_inst" ] || [[ "$host_inst" == "$host_type" ]]; then
			if [[ "$host_type" == "forgejo" ]] || [[ "$host_type" == "gitea" ]]; then
				epr "ERROR: forgejo host requires a domain URL (e.g. 'git.example.com|forgejo')"
				return 1
			fi
		fi
		if [[ -n "$host_inst" ]] && [[ "$host_inst" != http://* ]] && [[ "$host_inst" != https://* ]]; then
			host_inst="https://${host_inst}"
		fi
	else
		host_type="$spec"
		case "$host_type" in
			github) host_inst="https://github.com" ;;
			gitlab) host_inst="https://gitlab.com" ;;
			forgejo|gitea)
				epr "ERROR: forgejo host requires a domain URL (e.g. 'git.example.com|forgejo')"
				return 1
				;;
			none) host_inst="none" ;;
			*)
				return 1
				;;
		esac
	fi

	eval "$host_var_name='$host_type'"
	eval "$instance_var_name='$host_inst'"
}

source_release_api_base() {
	local host=${1,,} src=$2 host_instance=$3
	if [ -n "$host_instance" ] && [[ "$host_instance" != http://* ]] && [[ "$host_instance" != https://* ]]; then
		host_instance="https://${host_instance}"
	fi
	case "$host" in
		github)
			if [ -n "$host_instance" ] && [[ "$host_instance" != "https://github.com" ]]; then
				echo "${host_instance}/api/v3/repos/${src}/releases"
			else
				echo "https://api.github.com/repos/${src}/releases"
			fi
			;;
		gitlab)
			encoded=$(jq -nr --arg v "$src" '$v | @uri')
			echo "${host_instance:-https://gitlab.com}/api/v4/projects/${encoded}/releases"
			;;
		forgejo|gitea)
			[ -z "$host_instance" ] && return 1
			echo "${host_instance}/api/v1/repos/${src}/releases"
			;;
		*) return 1 ;;
	esac
}

source_release_tag_api() {
	local host=${1,,} src=$2 tag=$3 base host_instance=$4
	base=$(source_release_api_base "$host" "$src" "$host_instance") || return 1
	case "$host" in
		github|forgejo|gitea) echo "${base}/tags/${tag}" ;;
		gitlab) echo "${base}/${tag}" ;;
		*) return 1 ;;
	esac
}

source_release_assets_json() {
	local host=${1,,}
	case "$host" in
		github|forgejo|gitea) jq -e '[.assets[]? | select(.name | (endswith("asc") or endswith("json")) | not)]' ;;
		gitlab) jq -e '[.assets.links[]? | select(.name | (endswith("asc") or endswith("json")) | not)]' ;;
		*) return 1 ;;
	esac
}

source_release_asset_url() {
	local host=${1,,}
	case "$host" in
		github|forgejo|gitea) jq -r '.browser_download_url // .url' ;;
		gitlab) jq -r '.direct_asset_url // .url' ;;
		*) return 1 ;;
	esac
}

source_release_pick_from_list() {
	local host=${1,,} mode=$2 host_instance=${3:-https://gitlab.com}
	case "$host" in
		github|forgejo|gitea)
			if [ "$mode" = dev ]; then
				jq -e -c 'map(select((.prerelease == true or (.tag_name | test("(?i)(dev|alpha|beta|rc)"))) and .tag_name != null and .tag_name != "")) | sort_by(.published_at // .created_at // "") | reverse | .[0] // empty'
			elif [ "$mode" = absolutelatest ]; then
				jq -e -c 'map(select(.tag_name != null and .tag_name != "")) | sort_by(.published_at // .created_at // "") | reverse | .[0] // empty'
			else
				jq -e -c 'map(select(.prerelease != true and (.tag_name | test("(?i)(dev|alpha|beta|rc)") | not) and .tag_name != null and .tag_name != "")) | sort_by(.published_at // .created_at // "") | reverse | .[0] // empty'
			fi
			;;
		gitlab)
			if [ "$mode" = dev ]; then
				jq -e -c 'map(select(.tag_name != null and .tag_name != "" and (.tag_name | test("(?i)(dev|alpha|beta|rc)")))) | sort_by(.released_at // .created_at // "") | reverse | .[0] // empty'
			elif [ "$mode" = absolutelatest ]; then
				jq -e -c 'map(select(.tag_name != null and .tag_name != "")) | sort_by(.released_at // .created_at // "") | reverse | .[0] // empty'
			else
				jq -e -c 'map(select(.tag_name != null and .tag_name != "" and (.tag_name | test("(?i)(dev|alpha|beta|rc)") | not))) | sort_by(.released_at // .created_at // "") | reverse | .[0] // empty'
			fi
			;;
		*) return 1 ;;
	esac
}

get_bcprov() {
	if [ -f "$TEMP_DIR/bcprov.jar" ] && [ -f "$TEMP_DIR/bc.security" ]; then return 0; fi
	local LAST_PROV bcversion
	bcversion=$(curl -fsSL https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/maven-metadata.xml | grep -oPm1 '(?<=<release>)[^<]+') || return 1
	pr "Downloading Bouncy Castle Provider"
	wget -qO $TEMP_DIR/bcprov.jar "https://repo1.maven.org/maven2/org/bouncycastle/bcprov-jdk18on/$bcversion/bcprov-jdk18on-$bcversion.jar" || return 1
	LAST_PROV=$(grep "^security.provider\." "$JAVA_HOME/conf/security/java.security" | grep -oP '(?<=security\.provider\.)\d+' | sort -n | tail -1)
	echo "security.provider.$((LAST_PROV + 1))=org.bouncycastle.jce.provider.BouncyCastleProvider" >$TEMP_DIR/bc.security
}

get_apkeditor() {
	if [ -f "$TEMP_DIR/apkeditor.jar" ]; then return 0; fi
	local api_resp dl_url
	api_resp=$(gh_req "https://api.github.com/repos/REAndroid/APKEditor/releases/latest" -) || true
	dl_url=$(echo "$api_resp" | jq -r '.assets[]? | select(.name | endswith(".jar")) | .browser_download_url' | head -1) || true
	if [ -z "$dl_url" ] || [ "$dl_url" = "null" ]; then
		dl_url="https://github.com/REAndroid/APKEditor/releases/download/V1.4.9/APKEditor-1.4.9.jar"
	fi
	pr "Downloading APKEditor"
	gh_dl "$TEMP_DIR/apkeditor.jar" "$dl_url" >/dev/null || return 1
}

get_prebuilts() {
	local cache_key="${1}_${2}_${3}_${4}_${5}_${6}_${7:-}_${8:-}"
	if [ -n "${__PREBUILTS_CACHE__["$cache_key"]:-}" ]; then
		echo "${__PREBUILTS_CACHE__["$cache_key"]}"
		return 0
	fi
	local result
	if ! result=$(_get_prebuilts "$@"); then return 1; fi
	__PREBUILTS_CACHE__["$cache_key"]="$result"
	echo "$result"
}

_get_prebuilts() {
	local cli_host=$1 cli_src=$2 cli_ver=$3 patches_host_list=$4 patches_src_list=$5 patches_ver_list=$6
	local cli_filter=${7:-} patches_filter_list=${8:-}
	
	local first_patch_src
	first_patch_src=$(list_args "$patches_src_list" | tr -d \"\' | head -n 1)
	pr "Getting prebuilts (${first_patch_src%/*})" >&2

	local cl_dir=${first_patch_src%/*}
	cl_dir=${TEMP_DIR}/${cl_dir,,}-rv
	[ -d "$cl_dir" ] || mkdir "$cl_dir"

	local raw_cli_host=$cli_host src=$cli_src tag="CLI" ver=${cli_ver} fprefix="cli" host="" host_instance=""
	if ! parse_host_spec "$raw_cli_host" host host_instance; then
		abort "source host '$raw_cli_host' is not supported"
	fi

	local grab_cl=false
	local dir=${src%/*}
	dir=${TEMP_DIR}/${dir,,}-rv
	[ -d "$dir" ] || mkdir "$dir"
	if [[ "$host" != "none" ]]; then
	local rv_rel release resp tag_name matches asset name url
	rv_rel=$(source_release_api_base "$host" "$src" "$host_instance") || return 1
	if [ "$ver" = "dev" ]; then
		resp=$({ if [ "$host" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || return 1
		release=$(source_release_pick_from_list "$host" dev "$host_instance" <<<"$resp") || true
		ver=$(jq -r '.tag_name' <<<"$release") || true
		if [ -z "$ver" ] || [ "$ver" = "null" ]; then
			ver=$(jq -e -r '.[].tag_name' <<<"$resp" | get_highest_ver) || return 1
			release="" # Clear release if we had to fallback to get_highest_ver
		fi
	fi
	if [ "$ver" = "latest" ]; then
		resp=$({ if [ "$host" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || return 1
		release=$(source_release_pick_from_list "$host" latest "$host_instance" <<<"$resp") || return 1
	elif [ -z "${release:-}" ]; then
		rv_rel=$(source_release_tag_api "$host" "$src" "$ver" "$host_instance") || return 1
		release=$({ if [ "$host" = github ]; then gh_req "$rv_rel" -; else req "$rv_rel" -; fi; }) || return 1
	fi
	tag_name=$(jq -r '.tag_name' <<<"$release") || return 1
	name_ver=$tag_name

	local file
	file=$(find "$dir" -name "*${fprefix}-${name_ver#v}.*" -type f 2>/dev/null | head -1)
	if [ -z "$file" ]; then
		matches=$(source_release_assets_json "$host" <<<"$release") || return 1
		if [ -n "$cli_filter" ]; then
			local matches_filtered
			matches_filtered=$(jq -c --arg f "$cli_filter" '
				map(
					. as $asset |
					($asset.name // "") as $name |
					select($name | test($f; "i"))
				)
			' <<<"$matches" 2>/dev/null) || true
			if [ -n "$matches_filtered" ] && [ "$matches_filtered" != "[]" ]; then
				matches="$matches_filtered"
			fi
		else
			if [ "$(jq 'length' <<<"$matches")" -gt 1 ]; then
				local matches_new
				matches_new=$(jq -e -r 'map(select(.name | test("\\.(jar|zip)$"; "i")))' <<<"$matches" 2>/dev/null) || true
				if [ -n "$matches_new" ] && [ "$(jq 'length' <<<"$matches_new")" -ge 1 ]; then
					matches=$matches_new
				fi
			fi
			if [ "$(jq 'length' <<<"$matches")" -gt 1 ]; then
				local matches_new
				matches_new=$(jq -e -r 'map(select(.name | contains("-dev") | not))' <<<"$matches")
				if [ "$(jq 'length' <<<"$matches_new")" -eq 1 ]; then
					matches=$matches_new
				fi
			fi
			if [ "$(jq 'length' <<<"$matches")" -gt 1 ]; then
				local matches_new
				matches_new=$(jq -e -r 'map(select(.name | contains("debug") | not))' <<<"$matches")
				if [ "$(jq 'length' <<<"$matches_new")" -ge 1 ]; then
					matches=$matches_new
				fi
			fi
		fi
		if [ "$(jq 'length' <<<"$matches")" -eq 0 ]; then
			epr "No asset was found"
			return 1
		elif [ "$(jq 'length' <<<"$matches")" -ne 1 ]; then
			wpr "More than 1 asset was found for this release. Falling back to the first one found..."
		fi
		asset=$(jq -r ".[0]" <<<"$matches")
		url=$(source_release_asset_url "$host" <<<"$asset")
		name=$(jq -r .name <<<"$asset")
		file="${dir}/${name}"
		if [ "$host" = github ]; then
			gh_dl "$file" "$url" >&2 || return 1
		else
			pr "Getting '$file' from '$url'"
			_req "$url" "$file" -H "Accept: application/octet-stream" >&2 || return 1
		fi
		echo "$tag: $(cut -d/ -f1 <<<"$src")/${name}  " >>"${cl_dir}/changelog.md"
	else
		grab_cl=false
		name=$(basename "$file")
		tag_name=$(cut -d'-' -f3- <<<"$name")
		tag_name=v${tag_name%.*}
	fi
	echo -n "$file "
	else
		pr "Not Getting anything as source is none"
		echo "none"
	fi

	local IFS=$'\n'
	local p_srcs=($(list_args "$patches_src_list" | tr -d \"\'))
	local p_hosts=($(list_args "$patches_host_list" | tr -d \"\'))
	local p_vers=($(list_args "$patches_ver_list" | tr -d \"\'))
	local p_filters=($(list_args "$patches_filter_list" | tr -d \"\'))
	unset IFS
	for i in "${!p_srcs[@]}"; do
		local raw_host="${p_hosts[$i]:-${p_hosts[0]}}"
		local src="${p_srcs[$i]}"
		local ver="${p_vers[$i]:-${p_vers[0]}}"
		local pf="${p_filters[$i]:-${p_filters[0]:-}}"
		local host="" host_instance=""
		if ! parse_host_spec "$raw_host" host host_instance; then
			abort "source host '$raw_host' is not supported"
		fi
		local tag="Patches" fprefix="patches"
		local grab_cl=true
		
		local dir=${src%/*}
		dir=${TEMP_DIR}/${dir,,}-rv
		[ -d "$dir" ] || mkdir "$dir"
		if [[ $host != "none" ]]; then
		local rv_rel release resp tag_name matches asset name url
		rv_rel=$(source_release_api_base "$host" "$src" "$host_instance") || return 1
		if [ "$ver" = "dev" ]; then
			resp=$({ if [ "$host" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || return 1
			release=$(source_release_pick_from_list "$host" dev "$host_instance" <<<"$resp") || true
			ver=$(jq -r '.tag_name' <<<"$release") || true
			if [ -z "$ver" ] || [ "$ver" = "null" ]; then
				ver=$(jq -e -r '.[].tag_name' <<<"$resp" | get_highest_ver) || return 1
				release="" # Clear release if we had to fallback to get_highest_ver
			fi
		fi
		if [ "$ver" = "absolutelatest" ]; then
			resp=$({ if [ "$host" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || return 1
			release=$(source_release_pick_from_list "$host" absolutelatest "$host_instance" <<<"$resp") || true
			ver=$(jq -r '.tag_name' <<<"$release") || true
			if [ -z "$ver" ] || [ "$ver" = "null" ]; then
				ver=$(jq -e -r '.[].tag_name' <<<"$resp" | get_highest_ver) || return 1
				release="" # Clear release if we had to fallback to get_highest_ver
			fi
		fi
		if [ "$ver" = "latest" ]; then
			resp=$({ if [ "$host" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || return 1
			release=$(source_release_pick_from_list "$host" latest "$host_instance" <<<"$resp") || return 1
		elif [ -z "${release:-}" ]; then
			rv_rel=$(source_release_tag_api "$host" "$src" "$ver" "$host_instance") || return 1
			release=$({ if [ "$host" = github ]; then gh_req "$rv_rel" -; else req "$rv_rel" -; fi; }) || return 1
		fi
		tag_name=$(jq -r '.tag_name' <<<"$release") || return 1
		name_ver=$tag_name

		local file
		file=$(find "$dir" -name "*${fprefix}-${name_ver#v}.*" -type f 2>/dev/null | head -1)
		if [ -z "$file" ]; then
			matches=$(source_release_assets_json "$host" <<<"$release") || return 1
			if [ -n "$pf" ]; then
				local matches_filtered
				matches_filtered=$(jq -c --arg f "$pf" '
					map(
						. as $asset |
						($asset.name // "") as $name |
						select($name | test($f; "i"))
					)
				' <<<"$matches" 2>/dev/null) || true
				if [ -n "$matches_filtered" ] && [ "$matches_filtered" != "[]" ]; then
					matches="$matches_filtered"
				fi
			else
				if [ "$(jq 'length' <<<"$matches")" -gt 1 ]; then
					local matches_new
					if echo "$cli_src" | grep -qiE "(npatch|lspatch)"; then
						matches_new=$(jq -e -r 'map(select(.name | test("\\.apk$"; "i")))' <<<"$matches")
					else
						matches_new=$(jq -e -r 'map(select(.name | test("\\.(rvp|mpp|jar)$"; "i")))' <<<"$matches")
					fi
					if [ "$(jq 'length' <<<"$matches_new")" -ge 1 ]; then
						matches=$matches_new
					fi
				fi
				if [ "$(jq 'length' <<<"$matches")" -gt 1 ]; then
					local matches_new
					matches_new=$(jq -e -r 'map(select(.name | contains("-dev") | not))' <<<"$matches")
					if [ "$(jq 'length' <<<"$matches_new")" -eq 1 ]; then
						matches=$matches_new
					fi
				fi
				if [ "$(jq 'length' <<<"$matches")" -gt 1 ]; then
					local matches_new
					matches_new=$(jq -e -r 'map(select(.name | contains("debug") | not))' <<<"$matches")
					if [ "$(jq 'length' <<<"$matches_new")" -ge 1 ]; then
						matches=$matches_new
					fi
				fi
			fi
			if [ "$(jq 'length' <<<"$matches")" -eq 0 ]; then
				epr "No asset was found"
				return 1
			elif [ "$(jq 'length' <<<"$matches")" -ne 1 ]; then
				wpr "More than 1 asset was found for this release. Falling back to the first one found..."
			fi
			asset=$(jq -r ".[0]" <<<"$matches")
			url=$(source_release_asset_url "$host" <<<"$asset")
			name=$(jq -r .name <<<"$asset")
			file="${dir}/${name}"
			if [ "$host" = github ]; then
				gh_dl "$file" "$url" >&2 || return 1
			else
				pr "Getting '$file' from '$url'"
				_req "$url" "$file" -H "Accept: application/octet-stream" >&2 || return 1
			fi
			echo "$tag: $(cut -d/ -f1 <<<"$src")/${name}  " >>"${cl_dir}/changelog.md"
		else
			grab_cl=false
			name=$(basename "$file")
		fi

		echo "$tag_name" > "${dir}/tag_name.txt"

		if [ "$grab_cl" = true ]; then
			if [ "$host" = github ]; then
				echo -e "[Changelog](${host_instance:-https://github.com}/${src}/releases/tag/${tag_name})\n" >>"${cl_dir}/changelog.md"
			elif [ "$host" = gitlab ]; then
				echo -e "[Changelog](${host_instance:-https://gitlab.com}/${src}/-/releases/${tag_name})\n" >>"${cl_dir}/changelog.md"
			elif [ "$host" = forgejo ] || [ "$host" = gitea ]; then
				echo -e "[Changelog](${host_instance}/${src}/releases/tag/${tag_name})\n" >>"${cl_dir}/changelog.md"
			fi
		fi
		if [ "$REMOVE_RV_INTEGRATIONS_CHECKS" = true ]; then
			local extensions_ext
			extensions_ext=$(unzip -l "${file}" "extensions/shared.*" | grep -o "shared\..*") extensions_ext="${extensions_ext#*.}"
			if ! (
				mkdir -p "${file}-zip" || return 1
				unzip -qo "${file}" -d "${file}-zip" || return 1
					java -cp "${BIN_DIR}/paccer.jar${javapathsep}${BIN_DIR}/dexlib2.jar" com.jhc.Main "${file}-zip/extensions/shared.${extensions_ext}" "${file}-zip/extensions/shared-patched.${extensions_ext}" || return 1
				mv -f "${file}-zip/extensions/shared-patched.${extensions_ext}" "${file}-zip/extensions/shared.${extensions_ext}" || return 1
				rm "${file}" || return 1
				cd "${file}-zip" || abort
				zip -0rq "${CWD}/${file}" . || return 1
			) >&2; then
				echo >&2 "Patching revanced-integrations failed"
			fi
			rm -r "${file}-zip" || :
		fi
		
		echo -n "$file "
		else
			pr "Not Getting anything as source is none"
			echo "none"
		fi
	done
	echo
}

set_prebuilts() {
	APKSIGNER="${BIN_DIR}/apksigner.jar"
	local arch kernel ext
	arch=$(uname -m)
	kernel=$(uname -s)
	if [ "$kernel" = Linux ]; then kernel=linux; fi
	if [ "$arch" = aarch64 ]; then arch=arm64; elif [ "${arch:0:5}" = "armv7" ]; then arch=arm; fi
	if [[ "$kernel" = *"NT"* ]]; then
		kernel=windows
		ext=.exe
	else ext=; fi
	HTMLQ="${BIN_DIR}/htmlq/htmlq-${kernel}-${arch}${ext}"
	if [ ! -f "$HTMLQ" ]; then
		epr "htmlq binary isnt currenly available for $kernel $arch. Currently not supported."
		exit 1
	fi
	AAPT2=$(command -v aapt2) || true
	if [ -z "$AAPT2" ]; then
		wpr "aapt2 not found in PATH, searching in Android SDK..."
		if [[ -d "${ANDROID_HOME:-}" ]]; then
			AAPT2=$(find /usr/local/lib/android/sdk/build-tools -name aapt2 | sort -r | head -n 1)
		else
			epr "Cannot Find aapt2, please install Android SDK or add aapt2 to PATH"
			if [ $(uname -o) = Android ]; then
				epr "On Android, you can install aapt2 with 'pkg install aapt2' or 'apt install aapt2'"
			fi
			exit 1
		fi
	fi
	pr "Using aapt2: $AAPT2"
	command -v yq >/dev/null 2>&1 || abort "\`yq\` is not installed. install it with 'apt install yq' or equivalent"
}

config_update() {
	if [ ! -f build.md ]; then abort "build.md not available"; fi
	declare -A sources
	: >"$TEMP_DIR"/skipped
	local upped=()
	local prcfg=false
	for table_name in $(toml_get_table_names); do
		if [ -z "$table_name" ]; then continue; fi
		t=$(toml_get_table "$table_name")
		enabled=$(toml_get "$t" enabled) || enabled=true
		if [ "$enabled" = "false" ]; then continue; fi
		local raw_patches_src raw_patches_host raw_patches_ver
		raw_patches_src=$(toml_get "$t" patches-source) || raw_patches_src=$DEF_PATCHES_SRC
		raw_patches_host=$(toml_get "$t" patches-source-host) || raw_patches_host=$DEF_PATCHES_SRC_HOST
		raw_patches_ver=$(toml_get "$t" patches-version) || raw_patches_ver=$DEF_PATCHES_VER
		local IFS=$'\n'
		local p_srcs=($(list_args "$raw_patches_src" | tr -d \"\')); [ ${#p_srcs[@]} -eq 0 ] && p_srcs=("$raw_patches_src")
		local p_hosts=($(list_args "$raw_patches_host" | tr -d \"\')); [ ${#p_hosts[@]} -eq 0 ] && p_hosts=("$raw_patches_host")
		local p_vers=($(list_args "$raw_patches_ver" | tr -d \"\')); [ ${#p_vers[@]} -eq 0 ] && p_vers=("$raw_patches_ver")
		unset IFS
		local table_updated=false
		for i in "${!p_srcs[@]}"; do
			local PATCHES_SRC="${p_srcs[$i]}"
			local PATCHES_HOST="${p_hosts[$i]:-${p_hosts[0]}}"
			if [[ "$PATCHES_HOST" == *"|gitlab" ]]; then
				PATCHES_GITLAB_HOST="${PATCHES_HOST%%|*}"
				PATCHES_HOST="gitlab"
			else
				PATCHES_GITLAB_HOST="https://gitlab.com"
			fi
			local PATCHES_VER="${p_vers[$i]:-${p_vers[0]}}"
			if [[ -v sources["$PATCHES_HOST/$PATCHES_SRC/$PATCHES_VER/$PATCHES_GITLAB_HOST"] ]]; then
				if [ "${sources["$PATCHES_HOST/$PATCHES_SRC/$PATCHES_VER/$PATCHES_GITLAB_HOST"]}" = 1 ]; then table_updated=true; fi
			else
				sources["$PATCHES_HOST/$PATCHES_SRC/$PATCHES_VER/$PATCHES_GITLAB_HOST/"]=0
				local rv_rel resp last_patches
				rv_rel=$(source_release_api_base "$PATCHES_HOST" "$PATCHES_SRC" "$PATCHES_GITLAB_HOST") || continue
				if [ "$PATCHES_VER" = "dev" ]; then
					resp=$({ if [ "$PATCHES_HOST" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || continue
					last_patches=$(source_release_pick_from_list "$PATCHES_HOST" dev <<<"$resp") || continue
				elif [ "$PATCHES_VER" = "latest" ]; then
					resp=$({ if [ "$PATCHES_HOST" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || continue
					last_patches=$(source_release_pick_from_list "$PATCHES_HOST" latest <<<"$resp") || continue
				elif [ "$PATCHES_VER" = "absolutelatest" ]; then
					resp=$({ if [ "$PATCHES_HOST" = github ]; then gh_req "$rv_rel?per_page=100" -; else req "$rv_rel?per_page=100" -; fi; }) || continue
					last_patches=$(source_release_pick_from_list "$PATCHES_HOST" absolutelatest <<<"$resp") || continue
				else
					rv_rel=$(source_release_tag_api "$PATCHES_HOST" "$PATCHES_SRC" "$PATCHES_VER" "$PATCHES_GITLAB_HOST") || continue
					last_patches=$({ if [ "$PATCHES_HOST" = github ]; then gh_req "$rv_rel" -; else req "$rv_rel" -; fi; }) || continue
				fi
				if ! last_patches=$(source_release_assets_json "$PATCHES_HOST" <<<"$last_patches" | jq -e -r '.[0].name'); then
					abort "config_update error: '$last_patches'"
				fi
				if [ "$last_patches" ]; then
					if ! OP=$(grep "^Patches: ${PATCHES_SRC%%/*}/" build.md | grep -m1 "$last_patches"); then
						sources["$PATCHES_HOST/$PATCHES_SRC/$PATCHES_VER/$PATCHES_GITLAB_HOST/"]=1
						prcfg=true
						table_updated=true
					else
						echo "$OP" >>"$TEMP_DIR"/skipped
					fi
				fi
			fi
		done
		[ "$table_updated" = true ] && upped+=("$table_name")
	done
	if [ "$prcfg" = true ]; then
		local query=""
		for table in "${upped[@]}"; do
			if [ -n "$query" ]; then query+=" or "; fi
			query+=".key == \"$table\""
		done
		jq "to_entries | map(select(${query} or (.value | type != \"object\"))) | from_entries" <<<"$__TOML__"
	fi
}

_req() {
	local ip="$1" op="$2"
	shift 2
	local dlp="$op"
	if [ "$op" != - ]; then
		if [ -f "$op" ]; then return; fi
		dlp="$(dirname "$op")/tmp.$(basename "$op")"
		if [ -f "$dlp" ]; then
			local wait_c=0
			while [ -f "$dlp" ] && [ $wait_c -lt 300 ]; do 
				sleep 1
				wait_c=$((wait_c+1))
			done
			if [ -f "$op" ]; then return 0; fi
		fi
	fi
	if ! curl -L -c "$TEMP_DIR/cookie.txt" -b "$TEMP_DIR/cookie.txt" --connect-timeout 10 --retry 1 --fail -s -S "$@" "$ip" -o "$dlp"; then
		epr "Request failed: $ip"
		if [ "$dlp" != - ]; then rm -f "$dlp"; fi
		return 1
	fi
	if [ "$dlp" != - ]; then
		mv -f "$dlp" "$op"
	fi
}
req() { _req "$1" "$2" -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:108.0) Gecko/20100101 Firefox/108.0"; }
gh_req() { _req "$1" "$2" -H "$GH_HEADER"; }
gh_dl() {
	if [ ! -f "$1" ]; then
		pr "Getting '$1' from '$2'"
		_req "$2" "$1" -H "$GH_HEADER" -H "Accept: application/octet-stream"
	fi
}

log() { echo -e "$1  " >>"build.md"; }
get_highest_ver() {
	local vers m
	vers=$(tee)
	m=$(head -1 <<<"$vers")
	if ! semver_validate "$m"; then echo "$m"; else sort -s -t- -k1,1Vr <<<"$vers" | head -1; fi
}
semver_validate() {
	local a="${1%-*}"
	local a="${a#v}"
	local ac="${a//[.0-9]/}"
	[ ${#ac} = 0 ]
}
get_patch_last_supported_ver() {
	local cache_key="${1}_${2}_${3:-}_${4:-}_${5:-}_${6:-}"
	if [ -n "${__PATCH_VER_CACHE__["$cache_key"]:-}" ]; then
		echo "${__PATCH_VER_CACHE__["$cache_key"]}"
		return 0
	fi
	local result
	if ! result=$(_get_patch_last_supported_ver "$@"); then return 1; fi
	__PATCH_VER_CACHE__["$cache_key"]="$result"
	echo "$result"
}

_get_patch_last_supported_ver() {
	local list_patches=$1 pkg_name=$2 inc_sel=${3:-} _exc_sel=${4:-} _exclusive=${5:-} cli_source=${6:-} # TODO: resolve using all of these
	local op
	if [ "$inc_sel" ]; then
		if ! op=$(awk '{$1=$1}1' <<<"$list_patches"); then
			epr "list-patches: '$op'"
			return 1
		fi
		local ver vers="" NL=$'\n'
		while IFS= read -r line; do
			line="${line:1:${#line}-2}"
			ver=$(sed -n "/^Name: $line\$/,/^\$/p" <<<"$op" | sed -n "/^Compatible versions:\$/,/^\$/p" | tail -n +2)
			vers="${vers}${ver}${NL}"
		done <<<"$(list_args "$inc_sel")"
		vers=$(awk '{$1=$1}1' <<<"$vers")
		if [ -n "$vers" ]; then
			echo "$vers" | tr ' ' '\n' | sort | uniq -c | sort -k1,1nr | awk '
				NR==1 { max=$1; print $2; next }
				$1==max { print $2 }
			' | get_highest_ver
			return
		fi
	fi
	op=$(patches_list_versions "$cli_jar" "$patches_jar" "$pkg_name" "$cli_source") || return 1
	op=$(sed -n '/Most common compatible versions:/,$p' <<<"$op" | sed '1d' | awk '{$1=$1}1')
	if [ "$op" = "Any" ]; then return; fi
	pcount=$(head -1 <<<"$op") pcount=${pcount#*(} pcount=${pcount% *}
	if [ -z "$pcount" ]; then
		return
	fi
	grep -F "($pcount patch" <<<"$op" | sed 's/ (.* patch.*//' | get_highest_ver || return 1
}

get_patch_exp_ver() {
	local cli_jar=$1 patches_jar=$2 pkg_name=$3 cli_source=$4
	local list_stable list_all

	list_stable=$(patches_list_versions "$cli_jar" "$patches_jar" "$pkg_name" "$cli_source" "") || return 1
	list_all=$(patches_list_versions "$cli_jar" "$patches_jar" "$pkg_name" "$cli_source" "-x") || return 1

	list_stable=$(sed -n '/Most common compatible versions:/,$p' <<<"$list_stable" | sed '1d' | awk '{print $1}')
	list_all=$(sed -n '/Most common compatible versions:/,$p' <<<"$list_all" | sed '1d' | awk '{print $1}')

	local exp_versions=""
	for ver in $list_all; do
		if [ -n "$ver" ] && ! echo "$list_stable" | grep -qFx "$ver"; then
			exp_versions+="$ver"$'\n'
		fi
	done

	if [ -n "$exp_versions" ]; then
		get_highest_ver <<<"$exp_versions"
	fi
}

patches_list_versions() {
	local cache_key="${1}_${2}_${3}_${4}_${5:-}"
	if [ -n "${__PATCH_VER_CACHE__["$cache_key"]:-}" ]; then
		echo "${__PATCH_VER_CACHE__["$cache_key"]}"
		return 0
	fi
	local result
	if ! result=$(_patches_list_versions "$@"); then return 1; fi
	__PATCH_VER_CACHE__["$cache_key"]="$result"
	echo "$result"
}

_patches_list_versions() {
	local cli_jar=$1 patches_jar=$2 pkg_name=$3 cli_source=$4 extra_args=${5:-} op
	local cli_source_l="${cli_source,,}"
	if [[ "$cli_source_l" != *"revanced"* ]] && [[ "$cli_source_l" != *"morphe"* ]]; then
		echo ""
		return 0
	fi

	local p_jars=($(echo "$patches_jar" | tr ' ' '\n' | grep -v '^$'))
	
	if [[ "$cli_source_l" == *"morphe-desktop"* ]]; then
		local p_args_morphe=""
		for j in "${p_jars[@]}"; do
			p_args_morphe+="--patches '$j' "
		done
		if ! op=$(eval java -jar "'$cli_jar'" list-versions $p_args_morphe -f "'$pkg_name'" $extra_args 2>&1); then
			epr "Could not list versions $cli_jar: '$op'"
			return 1
		fi
	else
		local p_args_revanced=""
		for j in "${p_jars[@]}"; do
			p_args_revanced+="-p '$j' "
		done
		if ! op=$(eval java -jar "'$cli_jar'" list-versions -b $p_args_revanced -f "'$pkg_name'" $extra_args 2>&1); then
			epr "Could not list versions $cli_jar: '$op'"
			return 1
		fi
	fi
	echo "$op"
}
patches_list() {
	local cache_key="${1}_${2}_${3}_${4}"
	if [ -n "${__PATCHES_LIST_CACHE__["$cache_key"]:-}" ]; then
		echo "${__PATCHES_LIST_CACHE__["$cache_key"]}"
		return 0
	fi
	local result
	if ! result=$(_patches_list "$@"); then return 1; fi
	__PATCHES_LIST_CACHE__["$cache_key"]="$result"
	echo "$result"
}

_patches_list() {
	local cli_jar=$1 patches_jar=$2 pkg_name=$3 cli_source=$4 op
	local cli_source_l="${cli_source,,}"
	if [[ "$cli_source_l" == *"npatch"* ]] || [[ "$cli_source_l" == *"lspatch"* ]]; then
		echo "Name: xposed-module-dummy"
		return 0
	fi
	if [[ "$cli_source_l" == "apksigner" ]] || [[ "$cli_source_l" == "none" ]]; then
		echo "Name: passthrough-dummy"
		return 0
	fi
	local p_jars=($(echo "$patches_jar" | tr ' ' '\n' | grep -v '^$'))
	if [[ "$cli_source_l" == *"instafel"* ]]; then
		local cli_dir
		cli_dir=$(dirname "$cli_jar")
		for j in "${p_jars[@]}"; do
			cp "$j" "$cli_dir/ifl-patcher-core-8e4756f.jar" 2>/dev/null || :
			cp "$j" "ifl-patcher-core-8e4756f.jar" 2>/dev/null || :
		done
		if ! op=$(eval java -jar "'$cli_jar'" list 2>&1); then
			epr "Could not get patches list $cli_jar: '$op'"
			return 1
		fi
		echo "$op"
		return 0
	fi
	if [[ "$cli_source_l" == *"morphe-desktop"* ]]; then
		local p_args_morphe=""
		for j in "${p_jars[@]}"; do
			p_args_morphe+="--patches '$j' "
		done
		if ! op=$(eval java -jar "'$cli_jar'" list-patches $p_args_morphe -f "'$pkg_name'" --with-versions --with-packages 2>&1); then
			epr "Could not get patches list $cli_jar: '$op'"
			return 1
		fi
	else
		local p_args_revanced=""
		for j in "${p_jars[@]}"; do
			p_args_revanced+="-p '$j' "
		done
		if ! op=$(eval java -jar "'$cli_jar'" list-patches -b $p_args_revanced --packages --versions --options --filter-package-name="'$pkg_name'" 2>&1); then
			epr "Could not get patches list $cli_jar: '$op'"
			return 1
		fi
	fi
	echo "$op"
}

isoneof() {
	local i=$1 v
	shift
	for v; do [ "$v" = "$i" ] && return 0; done
	return 1
}
sign_apk() {
	get_bcprov
	local input=$1 output=$2 verbose=${3:-none}
	if ! OP=$(java -cp "$APKSIGNER$javapathsep$TEMP_DIR/bcprov.jar" com.android.apksigner.ApkSignerTool sign --ks $TEMP_DIR/ks.keystore --ks-provider-class org.bouncycastle.jce.provider.BouncyCastleProvider --ks-type BKS --ks-pass "pass:$KEYSTORE_PASSWORD" --key-pass "pass:$KEYSTORE_KEY_PASSWORD" --ks-key-alias "$KEYSTORE_ALIAS" --out="${output}" "${input}" 2>&1); then
		epr "apksigner error: $OP"
		return 1
	fi
	rm "${output}.idsig" "${output}-unsigned" 2>/dev/null || :
	if [ "$verbose" = "verbose" ]; then
		echo "$OP"
	fi
	return 0
}
merge_splits() {
	local bundle=$1 output=$2
	if unzip -l "$bundle" 2>/dev/null | grep '^[[:space:]]*[0-9].*AndroidManifest\.xml$'; then
		pr "Downloaded bundle is actually a standard APK. Bypassing merge."
		mv -f "$bundle" "$output"
		return 0
	fi
	pr "Merging splits"
	get_apkeditor || return 1
	if ! OP=$(java -jar "$TEMP_DIR/apkeditor.jar" merge -i "$bundle" -o "${output}-unsigned" -clean-meta -f 2>&1); then
		epr "APKEditor error: $OP"
		return 1
	fi
	# sign the merged stock apk
	sign_apk "${output}-unsigned" "${output}"
}

_trawl_get() {
	local url=$1 referer=${2:-}
	local max_retries=2 attempt
	local trawl_base="${TRAWL_URL:-${CF_BYPASS_SOLVER_TRAWL_8191_URL:-}}"
	[ -z "$trawl_base" ] && return 1
	local solver_url="${trawl_base%/}/scrape"
	local extra_headers=""
	[ -n "$referer" ] && extra_headers=",\"headers\":{\"Referer\":\"$referer\"}"
	for attempt in $(seq 1 $max_retries); do
		local response status
		response=$(curl -m 15 -s -X POST "$solver_url" \
			-H 'Content-Type: application/json' \
			-d "{\"url\":\"$url\",\"maxTimeout\":15000,\"skipHttp\":true${extra_headers}}") || true
		status=$(echo "$response" | jq -r '.statusCode // empty')
		if [[ "$status" =~ ^[1-3][0-9][0-9]$ ]]; then
			html=$(echo "$response" | jq -r '.html // empty')
			if [[ -n "$html" && "$html" != *"Attention Required!"* && "$html" != *"Just a moment..."* && "$html" != *"Please Wait... | Cloudflare"* && "$html" != *"Verify you are human"* ]]; then
				export CF_COOKIES
				CF_COOKIES=$(echo "$response" | jq -r '[.cookies[] | .name + "=" + .value] | join("; ")')
				user_agent=$(echo "$response" | jq -r '.userAgent // empty')
				return 0
			fi
		fi
		wpr "Trawl attempt $attempt/$max_retries failed for: $url"
		sleep 2
	done
	wpr "[!] Trawl failed after $max_retries attempts: $url"
	return 1
}

_cfb_get() {
	local url=$1 referer=${2:-}
	local max_retries=2 attempt
	local cfb_base="${CFB_URL:-${CF_BYPASS_SOLVER_CFB_URL:-}}"
	[ -z "$cfb_base" ] && return 1
	local solver_url="${cfb_base%/}/html"

	for attempt in $(seq 1 $max_retries); do
		local response_file
		rm -f "$TEMP_DIR/cfb_response_headers.txt"
		response_file=$(mktemp)
		local http_code
		http_code=$(curl -s -o "$response_file" -w '%{http_code}' \
			-D "$TEMP_DIR/cfb_response_headers.txt" \
			-G --data-urlencode "url=$url" \
			--max-time 15 \
			"$solver_url") || true
		if [[ "$http_code" == "200" ]]; then
			html=$(cat "$response_file")
			if [[ -n "$html" && "$html" != *"Attention Required!"* && "$html" != *"Just a moment..."* && "$html" != *"Please Wait... | Cloudflare"* && "$html" != *"Verify you are human"* ]]; then
				export CF_COOKIES
				CF_COOKIES=$(grep -i '^x-cf-bypasser-cookies:' "$TEMP_DIR/cfb_response_headers.txt" 2>/dev/null | cut -d':' -f2- | xargs)
				local cfb_ua
				cfb_ua=$(grep -i '^x-cf-bypasser-user-agent:' "$TEMP_DIR/cfb_response_headers.txt" 2>/dev/null | cut -d':' -f2- | xargs)
				[[ -n "$cfb_ua" ]] && user_agent="$cfb_ua"
				rm -f "$response_file" "$TEMP_DIR/cfb_response_headers.txt"
				return 0
			fi
		fi
		rm -f "$response_file" "$TEMP_DIR/cfb_response_headers.txt"
		wpr "CFB attempt $attempt/$max_retries failed for: $url"
		sleep 2
	done
	wpr "[!] CFB failed after $max_retries attempts: $url"
	return 1
}

_fs_get() {
	local url=$1 referer=${2:-}
	local max_retries=2 attempt
	local fs_base="${FS_URL:-${FLARESOLVERR_URL:-${CF_BYPASS_SOLVER_FS_URL:-}}}"
	[ -z "$fs_base" ] && return 1
	local solver_url="${fs_base%/}/v1"
	local extra_headers=""
	[ -n "$referer" ] && extra_headers=",\"headers\":{\"Referer\":\"$referer\"}"
	for attempt in $(seq 1 $max_retries); do
		local response status
		response=$(curl -m 15 -s -X POST "$solver_url" \
			-H 'Content-Type: application/json' \
			-d "{\"cmd\":\"request.get\",\"url\":\"$url\",\"maxTimeout\":15000${extra_headers}}") || true
		status=$(echo "$response" | jq -r '.status // empty')
		if [[ "$status" == "ok" ]]; then
			html=$(echo "$response" | jq -r '.solution.response // empty')
			if [[ -n "$html" && "$html" != *"Attention Required!"* && "$html" != *"Just a moment..."* && "$html" != *"Please Wait... | Cloudflare"* && "$html" != *"Verify you are human"* ]]; then
				export CF_COOKIES
				CF_COOKIES=$(echo "$response" | jq -r '[.solution.cookies[] | .name + "=" + .value] | join("; ")')
				user_agent=$(echo "$response" | jq -r '.solution.userAgent // empty')
				return 0
			fi
		fi
		wpr "FlareSolverr attempt $attempt/$max_retries failed for: $url"
		sleep 2
	done
	wpr "[!] FlareSolverr failed after $max_retries attempts: $url"
	return 1
}

_fallback_get(){
	local url=$1
	html=$(curl -L -c "$TEMP_DIR/cookie.txt" -b "$TEMP_DIR/cookie.txt" --connect-timeout 10 --retry 1 -s -f "$url" -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/109.0") || return 1
	if [[ "$html" == *"Attention Required!"* || "$html" == *"Just a moment..."* || "$html" == *"Please Wait... | Cloudflare"* || "$html" == *"Verify you are human"* ]]; then
		return 1
	fi
	CF_COOKIES=""
	user_agent="Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/109.0"
}

_unqueued_cf_get() {
	local trawl_base="${TRAWL_URL:-${CF_BYPASS_SOLVER_TRAWL_8191_URL:-}}"
	local cfb_base="${CFB_URL:-${CF_BYPASS_SOLVER_CFB_URL:-}}"
	local fs_base="${FS_URL:-${FLARESOLVERR_URL:-${CF_BYPASS_SOLVER_FS_URL:-}}}"

	if [ -n "$trawl_base" ]; then
		_trawl_get "$@" && return 0
	fi

	if [ -n "$cfb_base" ]; then
		_cfb_get "$@" && return 0
	fi

	if [ -n "$fs_base" ]; then
		_fs_get "$@" && return 0
	fi

	_fallback_get "$@" && return 0

	epr "All methods failed for: $1"
	return 1
}
_cf_get() {
	mkdir -p "$TEMP_DIR"
	local lock=$TEMP_DIR/cf_get.lock
	exec 200>"$lock"
	flock -x 200
	trap 'exec 200>&-' RETURN EXIT INT TERM
	_unqueued_cf_get "$@"
}

# -------------------- apkmirror --------------------
get_apkmirror_resp() {
	local url="${1}"
	if [ -n "${__DL_RESP_CACHE__["apkmirror_resp_$url"]:-}" ]; then
		__APKMIRROR_RESP__="${__DL_RESP_CACHE__["apkmirror_resp_$url"]}"
		__APKMIRROR_CAT__="${__DL_RESP_CACHE__["apkmirror_cat_$url"]}"
		return 0
	fi
	local html=""
	_cf_get "${url}" || return 1
	__APKMIRROR_RESP__="$html"
	local clean_url="${url%/}"
	__APKMIRROR_CAT__="${clean_url##*/}"
	__DL_RESP_CACHE__["apkmirror_resp_$url"]="$__APKMIRROR_RESP__"
	__DL_RESP_CACHE__["apkmirror_cat_$url"]="$__APKMIRROR_CAT__"
	set +u
	__APKMIRROR_EXAMPLE_URL__="${apkmirror_example_url:-}" 
	set -u
}

get_apkmirror_vers() {
	local vers apkm_resp html=""
	_cf_get "https://www.apkmirror.com/uploads/?appcategory=${__APKMIRROR_CAT__}" || return 1
	apkm_resp="$html"
	vers=$(sed -n 's;.*Version:</span><span class="infoSlide-value">\(.*\) </span>.*;\1;p' <<<"$apkm_resp" | awk '{$1=$1}1')
	if [ "${__AAV__:-false}" = false ]; then
		local IFS=$'\n'
		vers=$(grep -iv "\(beta\|alpha\)" <<<"$vers")
		local v r_vers=()
		for v in $vers; do
			grep -iq "${v} \(beta\|alpha\)" <<<"$apkm_resp" || r_vers+=("$v")
		done
		echo "${r_vers[*]}"
	else
		echo "$vers"
	fi
}

get_apkmirror_pkg_name() { sed -n 's;.*id=\(.*\)" class="accent_color.*;\1;p' <<<"$__APKMIRROR_RESP__"; }

apkmirror_search() {
	local resp="$1" dpi="$2" arch="$3" apk_bundle="$4" clean_search_version="$5" search_version="$6"
	local dlurl="" node app_table emptyCheck

	local appdpi=("nodpi" "anydpi")
	local match_any_dpi=false
	if [ "$dpi" ]; then
		appdpi+=($dpi)
		if isoneof "auto" "${appdpi[@]}"; then
			match_any_dpi=true
		fi
	fi

	local best_fallback_url=""
	local specific_arch_url=""
	local specific_arch_fallback_url=""

	for ((n = 1; n < 40; n++)); do
		node=$($HTMLQ "div.table-row.headerFont:nth-last-child($n)" <<<"$resp")
		if [ -z "$node" ]; then break; fi
		
		dlurl=$($HTMLQ --base https://www.apkmirror.com --attribute href "div.table-cell:nth-child(1) > a:nth-child(1)" <<<"$node")
		if [ -z "$dlurl" ]; then continue; fi
		


		local node_apk_bundle node_arch node_dpi
		node_apk_bundle=$($HTMLQ "div.table-cell:nth-child(1) span.apkm-badge:first-of-type" --text <<<"$node" | xargs)
		[ -z "$node_apk_bundle" ] && node_apk_bundle="APK"

		node_arch=$($HTMLQ "div.table-cell:nth-child(2)" --text <<<"$node" | xargs)
		node_dpi=$($HTMLQ "div.table-cell:nth-child(4)" --text <<<"$node" | xargs)

		if [ "$node_apk_bundle" != "$apk_bundle" ]; then continue; fi

		if [ -n "$clean_search_version" ]; then
			if [[ "$dlurl" != *"$clean_search_version"* ]] && [[ "$dlurl" != *"$search_version"* ]]; then
				continue
			fi
		fi

		# Pass 1 Logic: Return Universal/Fat Bundles immediately to optimize cache size
		if isoneof "$node_arch" 'universal' 'noarch' 'arm64-v8a + x86_64' 'arm64-v8a + armeabi-v7a'; then
			if isoneof "$node_dpi" "${appdpi[@]}"; then
				echo "$dlurl"
				return 0
			elif [ "$match_any_dpi" = true ] && [ -z "$best_fallback_url" ]; then
				best_fallback_url="$dlurl"
			fi
		# Pass 2 Logic: If it's strictly the requested arch, save it as a fallback in case no universal is found
		elif [ "$node_arch" = "$arch" ]; then
			if isoneof "$node_dpi" "${appdpi[@]}"; then
				[ -z "$specific_arch_url" ] && specific_arch_url="$dlurl"
			elif [ "$match_any_dpi" = true ] && [ -z "$specific_arch_fallback_url" ]; then
				specific_arch_fallback_url="$dlurl"
			fi
		fi
	done

	if [ -n "$best_fallback_url" ]; then
		echo "$best_fallback_url"
		return 0
	elif [ -n "$specific_arch_url" ]; then
		echo "$specific_arch_url"
		return 0
	elif [ -n "$specific_arch_fallback_url" ]; then
		echo "$specific_arch_fallback_url"
		return 0
	fi
	return 1
}

dl_apkmirror() {
	local url=$1 version=${2// /-} output=$3 arch=$4 dpi=$5 is_bundle=false
	local base_url="https://www.apkmirror.com"
	local html=""

	if [ -f "${output%.apk}.apkm" ]; then
		merge_splits "${output%.apk}.apkm" "${output}"
		return 0
	fi

	if [ "$arch" = "arm-v7a" ]; then arch="armeabi-v7a"; fi

	local clean_version="${version//[^0-9.]/}"
	local clean_search_version="${clean_version//./-}"

	local short_version="" short_search_version=""
	if [[ "$clean_version" == *.*.*.* ]]; then
		short_version=$(echo "$clean_version" | cut -d. -f1-3)
	elif [[ "$clean_version" == *.*.* ]]; then
		short_version=$(echo "$clean_version" | cut -d. -f1-2)
	fi
	if [ -n "$short_version" ]; then
		short_search_version="${short_version//./-}"
	fi

	local resp release_url=""

	if [ -n "${__APKMIRROR_EXAMPLE_URL__:-}" ]; then
		local example_path="${__APKMIRROR_EXAMPLE_URL__#$base_url}"
		local slug_ver target_ver
		slug_ver=$(echo "$example_path" | grep -oP '\d+(-\d+)+' | tail -1)
		target_ver=$(echo "$version" | tr '.' '-' | grep -oP '\d+(-\d+)+')
		if [ -n "$slug_ver" ] && [ -n "$target_ver" ]; then
			release_url="${base_url}${example_path/$slug_ver/$target_ver}"
				_cf_get "$release_url" || true
			resp="$html"
			if [[ "$resp" == *"Page Not Found"* ]] || [[ "$resp" == *"404 Whoops"* ]] || [ -z "$resp" ]; then
					release_url=""
			fi
		fi
	fi

	local search_version="${version//./-}"
	search_version="${search_version//_/-}"
	search_version="${search_version,,}"
	search_version="${search_version//[^a-z0-9-]/}"
	search_version="${search_version//---/-}"

	if [ -z "$release_url" ]; then
		local apkmname
		apkmname=$($HTMLQ "h1.marginZero" --text <<<"$__APKMIRROR_RESP__")
		apkmname="${apkmname,,}" apkmname="${apkmname// /-}" apkmname="${apkmname//[^a-z0-9-]/}"
		release_url="${url%/}/${apkmname}-${search_version}-release/"
		_cf_get "$release_url" || true
		resp="$html"
		if [[ "$resp" == *"Page Not Found"* ]] || [[ "$resp" == *"404 Whoops"* ]] || [ -z "$resp" ]; then
			release_url=""
		fi
	fi

	if [ -z "$release_url" ]; then
		local list_url="${url%/}"
		local version_href=""
		for page_num in $(seq 1 10); do
			local page_url="$list_url/"
			[[ $page_num -gt 1 ]] && page_url="$list_url/page/$page_num/"
			_cf_get "$page_url" || return 1
			

			local html_flat=$(echo "$html" | tr -d '\n\r')
			local html_split="${html_flat//<\/a>/<\/a>
}"

			local all_links=$(echo "$html_split" | grep -oP 'href="\K/apk/[^"]+')
			
			# 1. Exact URL match (strict)
			version_href=$(echo "$all_links" | grep -F "$search_version-release" | head -1) || true
			
			# 2. Exact text match
			if [ -z "$version_href" ]; then
				version_href=$(echo "$html_split" | grep -F "$version" | grep -oP 'href="\K[^"]+' | head -1) || true
			fi
			
			# 3. Clean text match
			if [ -z "$version_href" ] && [ -n "$clean_version" ] && [ "$clean_version" != "$version" ]; then
				version_href=$(echo "$html_split" | grep -F "$clean_version" | grep -oP 'href="\K[^"]+' | head -1) || true
			fi

			# 4. Clean URL match
			if [ -z "$version_href" ] && [ -n "$clean_search_version" ]; then
				version_href=$(echo "$all_links" | grep -E "${clean_search_version}(-[a-z0-9]+)*-release" | head -1) || true
			fi

			# 5. Safe Short URL match (for grouped versions)
			if [ -z "$version_href" ] && [ -n "$short_search_version" ] && [ "$short_search_version" != "$clean_search_version" ]; then
				version_href=$(echo "$all_links" | grep -E "${short_search_version}(-[0-9])?-release/?$" | head -1) || true
			fi

			if [ -n "$version_href" ]; then
				release_url="$base_url$version_href"
				_cf_get "$release_url" || return 1
				resp="$html"
				break
			fi
		done
		
		# Fallback to direct search if not found on first 5 pages
		if [ -z "$release_url" ]; then
			local search_list_url="https://www.apkmirror.com/?post_type=app_release&searchtype=apk&s=${__APKMIRROR_CAT__}+${version}"
			_cf_get "$search_list_url" || true
			if [ -n "$html" ] && [ "$html" != "null" ]; then
				local search_links=""
				if [[ "$html" != *"No results found matching your query"* ]]; then
					search_links=$($HTMLQ --attribute href "div.appRow h5 a" <<<"$html")
				fi
				
				# Try to find exact version match first to be safe, otherwise fallback to top result
				version_href=$(echo "$search_links" | grep -F "$search_version-release" | head -1) || true
				if [ -z "$version_href" ] && [ -n "$clean_search_version" ]; then
					version_href=$(echo "$search_links" | grep -E "${clean_search_version}(-[a-z0-9]+)*-release" | head -1) || true
				fi
				
				# Search query is exact, so the top search result is the best match if strict regexes fail
				if [ -z "$version_href" ]; then
					version_href=$(echo "$search_links" | head -1) || true
				fi

				if [ -n "$version_href" ]; then
					release_url="$base_url$version_href"
					_cf_get "$release_url" || return 1
					resp="$html"
				fi
			fi
		fi

		if [ -z "$release_url" ]; then
			epr "Could not find version $version on APKMirror"
			return 1
		fi
	fi

	local node dlurl=""
	node=$($HTMLQ "div.table-row.headerFont:nth-last-child(1)" -r "span:nth-child(n+3)" <<<"$resp")
	if [ "$node" ]; then
		if [ "${prefer_dl_mode}" == "bundle" ]; then
			pr "Preferring Bundle "
			types="BUNDLE APK"
		else
			types="APK BUNDLE"
		fi
		for type in $types; do
			if dlurl=$(apkmirror_search "$resp" "$dpi" "$arch" "$type" "$clean_search_version" "$search_version"); then
				[ "$type" = "BUNDLE" ] && is_bundle=true || is_bundle=false
				break
			fi
		done
		if [ -z "$dlurl" ]; then return 1; fi
		
		_cf_get "$dlurl" || return 1
		resp="$html"
		
	fi

	local all_dl_btns btn_url
	all_dl_btns=$(echo "$resp" | $HTMLQ "a.downloadButton" --attribute href)
	if [ "$is_bundle" = true ]; then
		btn_url=$(echo "$all_dl_btns" | grep -v 'forcebaseapk' | head -1)
		[ -z "$btn_url" ] && btn_url=$(echo "$all_dl_btns" | head -1)
	else
		btn_url=$(echo "$all_dl_btns" | grep 'forcebaseapk' | head -1)
		[ -z "$btn_url" ] && btn_url=$(echo "$all_dl_btns" | head -1)
	fi
	if [ -z "$btn_url" ]; then epr "Could not find download button on APKMirror"; return 1; fi
	btn_url=$(echo "$btn_url" | sed 's/&amp;/\&/g')

	_cf_get "$base_url$btn_url" || return 1
	local final_url
	final_url=$($HTMLQ "a#download-link" --attribute href <<<"$html" 2>/dev/null | head -1) || true
	[ -z "$final_url" ] && final_url=$(echo "$html" | grep -oP 'id="download-link"[^>]*href="\K[^"]+' | head -1) || true
	if [ -z "$final_url" ]; then epr "Could not find final download link on APKMirror"; return 1; fi
	final_url=$(echo "$final_url" | sed 's/&amp;/\&/g')
	[[ "$final_url" != http* ]] && final_url="${base_url}${final_url}"

	pr "Downloading APK: $final_url"
	local cookie_args=()
	[ -n "${CF_COOKIES:-}" ] && cookie_args=(--header "Cookie: $CF_COOKIES")
	local referer_url="$base_url$btn_url"
	[[ "$btn_url" == http* ]] && referer_url="$btn_url"

	if [ "$is_bundle" = true ]; then
		wget -nv -O "${output%.apk}.apkm" \
			--header="User-Agent: ${user_agent:-Mozilla/5.0}" \
			--referer="$referer_url" \
			"${cookie_args[@]}" \
			--timeout=300 \
			"$final_url" || return 1
		if ! unzip -l "${output%.apk}.apkm" >/dev/null 2>&1; then
			epr "Downloaded file is not a valid zip (apkm): $final_url"
			return 1
		fi
		merge_splits "${output%.apk}.apkm" "${output}"
	else
		wget -nv -O "${output}" \
			--header="User-Agent: ${user_agent:-Mozilla/5.0}" \
			--referer="$referer_url" \
			"${cookie_args[@]}" \
			--timeout=300 \
			"$final_url" || return 1
	fi
}

# -------------------- apkpure --------------------
get_apkpure_resp() {
	local url="${1}"
	if [ -n "${__DL_RESP_CACHE__["apkpure_resp_$url"]:-}" ]; then
		__APKPURE_BASE_URL__="${__DL_RESP_CACHE__["apkpure_base_$url"]}"
		__APKPURE_PKG__="${__DL_RESP_CACHE__["apkpure_pkg_$url"]}"
		__APKPURE_RESP__="${__DL_RESP_CACHE__["apkpure_resp_$url"]}"
		return 0
	fi
	url="${url%/downloading*}"
	url="${url%/download*}"
	url="${url%/}"
	__APKPURE_BASE_URL__="$url"
	__APKPURE_PKG__=$(echo "$url" | grep -oP '[a-zA-Z][a-zA-Z0-9]*(\.[a-zA-Z][a-zA-Z0-9]*){1,}' | tail -1)
	local html=""
	_cf_get "${url}/downloading/" || return 1
	__APKPURE_RESP__="$html"
	__DL_RESP_CACHE__["apkpure_base_$1"]="$__APKPURE_BASE_URL__"
	__DL_RESP_CACHE__["apkpure_pkg_$1"]="$__APKPURE_PKG__"
	__DL_RESP_CACHE__["apkpure_resp_$1"]="$__APKPURE_RESP__"
}

get_apkpure_vers() {
	local ver
	ver=$(echo "$__APKPURE_RESP__" | sed 's/<h2[^>]*>/\n__H2__/g' | grep '__H2__' | sed 's/__H2__//' | grep -oP '[0-9]+\.[0-9][0-9.]*' | head -1) || true
	[ -z "$ver" ] && ver=$(echo "$__APKPURE_RESP__" | grep -oP '"softwareVersion":"\K[^"]+' | head -1) || true
	echo "$ver"
}

get_apkpure_pkg_name() { echo "$__APKPURE_PKG__"; }

dl_apkpure() {
	local url=$1 version=$2 output=$3 arch=${4:-} _dpi=${5:-}
	local html=""

	local dl_page_url
	if [ -n "$version" ]; then
		dl_page_url="${__APKPURE_BASE_URL__}/downloading/${version}"
	else
		dl_page_url="${__APKPURE_BASE_URL__}/downloading/"
	fi

	_cf_get "$dl_page_url" || return 1

	if [ -z "$version" ]; then
		version=$(echo "$html" | sed 's/<h2[^>]*>/\n__H2__/g' | grep '__H2__' | sed 's/__H2__//' | grep -oP '[0-9]+\.[0-9][0-9.]*' | head -1) || true
		[ -z "$version" ] && version=$(echo "$html" | grep -oP '"softwareVersion":"\K[^"]+' | head -1) || true
	fi

	local download_url
	download_url=$($HTMLQ "a#download_link" --attribute href <<<"$html" 2>/dev/null | head -1) || true
	[ -z "$download_url" ] && \
		download_url=$(echo "$html" | grep -oP '<a[^>]+id="download_link"[^>]+href="\Khttps://[^"]+' | head -1) || true
	[ -z "$download_url" ] && \
		download_url=$(echo "$html" | grep -oP 'id="download_link"[^>]*href="\Khttps://[^"]+' | head -1) || true

	if [ -z "$download_url" ]; then
		epr "Could not find download link on APKPure"
		return 1
	fi

	pr "Downloading from APKPure: $download_url"
	local cookie_header=()
	[ -n "${CF_COOKIES:-}" ] && cookie_header=(-H "Cookie: $CF_COOKIES")

	local is_bundle=false
	echo "$download_url" | grep -qi 'xapk' && is_bundle=true

	if [ "$is_bundle" = true ]; then
		curl -L -s -S \
			-H "User-Agent: ${user_agent:-Mozilla/5.0}" \
			-H "Referer: $dl_page_url" \
			"${cookie_header[@]}" \
			--connect-timeout 30 --max-time 300 \
			"$download_url" -o "${output}.xapk" || return 1
		_apkpure_install_xapk "${output}.xapk" "${output}" || return 1
	else
		curl -L --fail -s -S \
			-H "User-Agent: ${user_agent:-Mozilla/5.0}" \
			-H "Referer: $dl_page_url" \
			"${cookie_header[@]}" \
			--connect-timeout 30 --max-time 300 \
			"$download_url" -o "${output}" || return 1
	fi
}

_apkpure_install_xapk() {
	local xapk=$1 output=$2
	if ! unzip -l "$xapk" >/dev/null 2>&1; then
		epr "Downloaded XAPK is not a valid zip (Cloudflare block?): $xapk"
		return 1
	fi
	get_apkeditor || return 1
	if unzip -l "$xapk" 2>/dev/null | grep -q '^[[:space:]]*[0-9].*base\.apk$'; then
		pr "Extracting base.apk from XAPK"
		unzip -p "$xapk" base.apk > "$output" || return 1
	else
		pr "Merging XAPK splits with APKEditor"
		local OP
		if ! OP=$(java -jar "$TEMP_DIR/apkeditor.jar" m -i "$xapk" -o "${output}-unsigned" 2>&1); then
			epr "APKEditor m error: $OP"
			return 1
		fi
		sign_apk "${output}-unsigned" "${output}"
	fi
}

# -------------------- apkcombo --------------------
get_apkcombo_resp() {
	local url="${1}"
	if [ -n "${__DL_RESP_CACHE__["apkcombo_resp_$url"]:-}" ]; then
		__APKCOMBO_RESP__="${__DL_RESP_CACHE__["apkcombo_resp_$url"]}"
		__APKCOMBO_PKG__="${__DL_RESP_CACHE__["apkcombo_pkg_$url"]}"
		__APKCOMBO_BASE_URL__="${__DL_RESP_CACHE__["apkcombo_base_$url"]}"
		return 0
	fi
	url="${url%/}"
	__APKCOMBO_PKG__="${url##*/}"
	__APKCOMBO_BASE_URL__="$url"
	local html=""
	_cf_get "https://apkcombo.com/search/${__APKCOMBO_PKG__}/download" || return 1
	__APKCOMBO_RESP__="$html"
	__DL_RESP_CACHE__["apkcombo_resp_$1"]="$__APKCOMBO_RESP__"
	__DL_RESP_CACHE__["apkcombo_pkg_$1"]="$__APKCOMBO_PKG__"
	__DL_RESP_CACHE__["apkcombo_base_$1"]="$__APKCOMBO_BASE_URL__"
}
get_apkcombo_vers() {
	echo "$__APKCOMBO_RESP__" | grep -oP 'phone-\K[0-9][^-]+-apk' | sed 's/-apk$//' | head -1
}
get_apkcombo_pkg_name() { echo "$__APKCOMBO_PKG__"; }
dl_apkcombo() {
	local _url=$1 version=$2 output=$3 _arch=$4 _dpi=$5
	local html="" dl_url final_url checkin page_url page compact_page

	if [ -n "$version" ]; then
		local sfxs=("apk" "xapk" "apks")
	else
		local sfxs=("apk")
	fi

	for sfx in "${sfxs[@]}"; do
		if [ -n "$version" ]; then
			local safe_version="${version// /-}"
			page_url="https://apkcombo.com/search/${__APKCOMBO_PKG__}/download/phone-${safe_version}-${sfx}"
		else
			page_url="https://apkcombo.com/search/${__APKCOMBO_PKG__}/download/apk"
		fi

		_cf_get "$page_url" "https://apkcombo.com/" || continue
		page="$html"
		compact_page=$(tr '\n' ' ' <<<"$page")

		dl_url=$(echo "$page" | grep -oP '(?<=a href=")https://download\.apkcombo\.com/[^"]+' | head -1) || true
		[ -z "$dl_url" ] && dl_url=$(echo "$page" | grep -oP '(?<=a href=")/r2[^"]+' | head -1) || true
		[ -z "$dl_url" ] && dl_url=$(echo "$compact_page" | grep -oP '"download_url"\s*:\s*"\K[^"]+' | head -1 | sed 's#\\/#/#g') || true
		[ -z "$dl_url" ] && dl_url=$(echo "$compact_page" | grep -oP '"url"\s*:\s*"\Khttps://download\.apkcombo\.com/[^"]+' | head -1 | sed 's#\\/#/#g') || true
		[ -z "$dl_url" ] && dl_url=$(echo "$compact_page" | grep -oP 'https://download\.apkcombo\.com/[^"'"'"' <>]+' | head -1 | sed 's#\\/#/#g') || true
		[ -z "$dl_url" ] && dl_url=$(echo "$compact_page" | grep -oP '/r2\?u=[^"'"'"' <>]+' | head -1 | sed 's#\\/#/#g') || true

		if [ -n "$dl_url" ]; then
			break
		fi
	done

	[ -z "$dl_url" ] && { epr "Could not find APK link on APKCombo"; return 1; }
	[[ "$dl_url" != http* ]] && dl_url="https://apkcombo.com${dl_url}"
	dl_url=$(echo "$dl_url" | sed 's/\\u0026/\&/g; s/&amp;/\&/g')

	if [[ "$dl_url" == https://apkcombo.com/r2\?u=* ]]; then
		final_url=$(python - "$dl_url" <<'PYC'
import sys, urllib.parse
u=sys.argv[1]
q=urllib.parse.urlparse(u).query
raw=urllib.parse.parse_qs(q).get('u',[''])[0]
decoded=urllib.parse.unquote(raw)
parts=urllib.parse.urlsplit(decoded)
query=urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
encoded=urllib.parse.urlunsplit((
	parts.scheme,
	parts.netloc,
	urllib.parse.quote(parts.path, safe='/'),
	urllib.parse.urlencode(query, doseq=True, safe='/:_-.'),
	parts.fragment,
))
print(encoded)
PYC
		) || return 1
	else
		checkin=$(req "https://apkcombo.com/checkin" -) || true
		if [ -n "$checkin" ] && [[ "$dl_url" != *fp=* ]]; then
			if [[ "$dl_url" == *\?* ]]; then
				dl_url="${dl_url}&${checkin}"
			else
				dl_url="${dl_url}?${checkin}"
			fi
		fi
		final_url=$(curl -s -o /dev/null -w "%{url_effective}" -L --max-redirs 10 \
			-H "User-Agent: ${user_agent:-Mozilla/5.0}" \
			-H "Referer: $page_url" "$dl_url") || return 1
	fi

	pr "Downloading from APKCombo: $final_url"
	curl -L --fail -s -S --connect-timeout 30 --max-time 300 \
		-H "User-Agent: ${user_agent:-Mozilla/5.0}" \
		-H "Referer: $page_url" "$final_url" -o "$output" || return 1
	if ! unzip -l "$output" >/dev/null 2>&1; then
		epr "Downloaded file from APKCombo is not a valid zip"
		return 1
	fi
	if echo "$final_url$dl_url" | grep -qi 'xapk\|\.apks'; then
		_apkpure_install_xapk "$output" "${output}.extracted" || return 1
		mv "${output}.extracted" "$output"
	fi
}

# -------------------- uptodown --------------------
get_uptodown_resp() {
	local url="${1}"
	if [ -n "${__DL_RESP_CACHE__["uptodown_resp_$url"]:-}" ]; then
		__UPTODOWN_RESP__="${__DL_RESP_CACHE__["uptodown_resp_$url"]}"
		__UPTODOWN_RESP_PKG__="${__DL_RESP_CACHE__["uptodown_resp_pkg_$url"]}"
		return 0
	fi
	__UPTODOWN_RESP__=$(req "${url}/versions" -) || return 1
	__UPTODOWN_RESP_PKG__=$(req "${url}/download" -) || return 1
	__DL_RESP_CACHE__["uptodown_resp_$url"]="$__UPTODOWN_RESP__"
	__DL_RESP_CACHE__["uptodown_resp_pkg_$url"]="$__UPTODOWN_RESP_PKG__"
}
get_uptodown_vers() { $HTMLQ --text ".version" <<<"$__UPTODOWN_RESP__"; }
dl_uptodown() {
	local uptodown_dlurl=$1 version=$2 output=$3 arch=$4 _dpi=$5
	if [ "$arch" = "arm-v7a" ]; then arch="armeabi-v7a"; fi

	local apparch=('arm64-v8a, armeabi-v7a, x86_64' 'arm64-v8a, armeabi-v7a, x86, x86_64' 'arm64-v8a, armeabi-v7a')
	if [ "$arch" != all ]; then
		apparch+=("$arch")
	fi

	local op resp data_code
	data_code=$($HTMLQ "#detail-app-name" --attribute data-code <<<"$__UPTODOWN_RESP__")
	local versionURL=""
	local is_bundle=false
	for i in {1..20}; do
		resp=$(req "${uptodown_dlurl}/apps/${data_code}/versions/${i}" -)
		if ! op=$(jq -e -r ".data | map(select(.version == \"${version}\")) | .[0]" <<<"$resp"); then
			continue
		fi
		if [ "$(jq -e -r ".kindFile" <<<"$op")" = "xapk" ]; then is_bundle=true; fi
		if versionURL=$(jq -e -r '.versionURL' <<<"$op"); then break; else return 1; fi
	done
	if [ -z "$versionURL" ]; then return 1; fi
	versionURL=$(jq -e -r '.url + "/" + .extraURL + "/" + (.versionID | tostring)' <<<"$versionURL")
	resp=$(req "$versionURL" -) || return 1

	local data_version files node_arch="" data_file_id node_class
	data_version=$($HTMLQ '.button.variants' --attribute data-version <<<"$resp") || return 1
	if [ "$data_version" ]; then
		files=$(req "${uptodown_dlurl%/*}/app/${data_code}/version/${data_version}/files" - | jq -e -r .content) || return 1
		local specific_arch_id="" specific_is_bundle=false
		for ((n = 1; n < 12; n += 1)); do
			node_class=$($HTMLQ -w -t ".content > :nth-child($n)" --attribute class <<<"$files") || return 1
			if [ "$node_class" != "variant" ]; then
				node_arch=$($HTMLQ -w -t ".content > :nth-child($n)" <<<"$files" | xargs) || return 1
				continue
			fi
			if [ -z "$node_arch" ]; then return 1; fi
			
			local file_type
			file_type=$($HTMLQ -w -t ".content > :nth-child($n) > .v-file > span" <<<"$files") || return 1
			data_file_id=$($HTMLQ ".content > :nth-child($n) > .v-report" --attribute data-file-id <<<"$files") || return 1
			
			# Pass 1 Logic: Return Universal/Fat Bundles immediately to optimize cache size
			if isoneof "$node_arch" 'arm64-v8a, armeabi-v7a, x86_64' 'arm64-v8a, armeabi-v7a, x86, x86_64' 'arm64-v8a, armeabi-v7a' 'universal'; then
				if [ "$file_type" = "xapk" ]; then is_bundle=true; else is_bundle=false; fi
				resp=$(req "${uptodown_dlurl}/download/${data_file_id}-x" -)
				break
			# Pass 2 Logic: Save specifically requested arch as fallback
			elif [ "$node_arch" = "$arch" ] && [ -z "$specific_arch_id" ]; then
				specific_arch_id="$data_file_id"
				if [ "$file_type" = "xapk" ]; then specific_is_bundle=true; else specific_is_bundle=false; fi
			fi
		done
		
		if [ $n -eq 12 ]; then
			if [ -n "$specific_arch_id" ]; then
				is_bundle=$specific_is_bundle
				resp=$(req "${uptodown_dlurl}/download/${specific_arch_id}-x" -)
			else
				return 1
			fi
		fi
	fi
	local data_url
	data_url=$($HTMLQ "#detail-download-button" --attribute data-url <<<"$resp") || return 1
	if [ $is_bundle = true ]; then
		req "https://dw.uptodown.com/dwn/${data_url}" "$output.apkm" || return 1
		merge_splits "${output%.apk}.apkm" "${output}"
	else
		req "https://dw.uptodown.com/dwn/${data_url}" "$output"
	fi
}
get_uptodown_pkg_name() { $HTMLQ --text "tr.full:nth-child(1) > td:nth-child(3)" <<<"$__UPTODOWN_RESP_PKG__"; }

# -------------------- archive --------------------
dl_archive() {
	local url=$1 version=$2 output=$3 arch=$4
	local path="" version_f=${version// /}
	for a in "${arch// /}" "common" "all"; do
		for ext in "apk" "apkm" "xapk" "apks" "apk.apkm" "apk.xapk" "apk.apks"; do
			while IFS= read -r p; do
				if [[ "$p" == *"${version_f#v}-${a}.${ext}" ]]; then
					path="$p"
					break 3
				fi
			done <<<"$__ARCHIVE_RESP__"
		done
	done
	if [ -z "$path" ]; then
		epr "Version ${version} with arch ${arch} not found in archive"
		return 1
	fi
	case "${path##*.}" in
		apk)
			req "${url}/${path}" "$output"
			;;
		apkm|xapk|apks)
			req "${url}/${path}" "${output}.${path##*.}" || return 1
			merge_splits "${output}.${path##*.}" "${output}"
			;;
		*)
			epr "Unsupported archive file type for ${path}"
			return 1
			;;
	esac
}
get_archive_resp() {
	local url="${1}"
	if [ -n "${__DL_RESP_CACHE__["archive_resp_$url"]:-}" ]; then
		__ARCHIVE_RESP__="${__DL_RESP_CACHE__["archive_resp_$url"]}"
		__ARCHIVE_PKG_NAME__="${__DL_RESP_CACHE__["archive_pkg_$url"]}"
		return 0
	fi
	local r
	r=$(req "$url" -)
	if [ -z "$r" ]; then return 1; else __ARCHIVE_RESP__=$(sed -n 's;^<a href="\(.*\)"[^"]*;\1;p' <<<"$r"); fi
	__ARCHIVE_PKG_NAME__=$(awk -F/ '{print $NF}' <<<"$url")
	__DL_RESP_CACHE__["archive_resp_$url"]="$__ARCHIVE_RESP__"
	__DL_RESP_CACHE__["archive_pkg_$url"]="$__ARCHIVE_PKG_NAME__"
}
get_archive_vers() { sed 's/^[^-]*-//;s/-\(all\|common\|arm64-v8a\|arm-v7a\|x86\|x86_64\)\.\(apk\|apkm\|xapk\|apks\)$//g' <<<"$__ARCHIVE_RESP__"; }
get_archive_pkg_name() { echo "$__ARCHIVE_PKG_NAME__"; }

# -------------------- github --------------------
dl_github() {
	local url=$1 version=$2 output=$3 arch=$4
	local path="" version_f=${version// /}
	local base_url=${__GITHUB_URL__:-$url}
	
	# Matches the exact file selection logic from dl_archive
	for a in "${arch// /}" "common" "all"; do
		for ext in "apk" "apkm" "xapk" "apks" "apk.apkm" "apk.xapk" "apk.apks"; do
			while IFS= read -r p; do
				if [[ "$p" == *"${version_f#v}-${a}.${ext}" ]]; then
					path="$p"
					break 3
				fi
			done <<<"$__ARCHIVE_RESP__"
		done
	done
	
	if [ -z "$path" ]; then
		epr "Version ${version} with arch ${arch} not found in github"
		return 1
	fi
	
	local ext="${path##*.}"
	case "$ext" in
		apk)
			req "${base_url}/${path}" "$output"
			;;
		apkm|xapk|apks)
			local bundle="${output}.${ext}"
			req "${base_url}/${path}" "$bundle" || return 1
			merge_splits "$bundle" "$output"
			;;
		*)
			epr "Unsupported github file type for ${path}"
			return 1
			;;
	esac
}

get_github_resp() {
	local url="${1}"
	if [ -n "${__DL_RESP_CACHE__["github_archive_resp_$url"]:-}" ]; then
		__ARCHIVE_RESP__="${__DL_RESP_CACHE__["github_archive_resp_$url"]}"
		__ARCHIVE_PKG_NAME__="${__DL_RESP_CACHE__["github_archive_pkg_$url"]}"
		__GITHUB_URL__="${__DL_RESP_CACHE__["github_url_$url"]}"
		return 0
	fi
	local repo tag resp
	
	repo=$(cut -d/ -f4-5 <<<"$url")
	tag=${url%/}
	tag=${tag##*/}
	
	resp=$(gh_req "https://api.github.com/repos/${repo}/releases/tags/${tag}" -) || return 1
	
	# Extract only supported file extensions
	__ARCHIVE_RESP__=$(jq -r '.assets[]? | select(.name | test("\\.(apk|apkm|xapk|apks)$")) | .name' <<<"$resp")
	if [ -z "$__ARCHIVE_RESP__" ]; then return 1; fi
	
	# Grab the package name exactly like how get_archive_vers isolates the version
	__ARCHIVE_PKG_NAME__=$(get_github_pkg_name)
	if [ -z "$__ARCHIVE_PKG_NAME__" ]; then return 1; fi
	
	__GITHUB_URL__="https://github.com/${repo}/releases/download/${tag}"
	
	__DL_RESP_CACHE__["github_archive_resp_$url"]="$__ARCHIVE_RESP__"
	__DL_RESP_CACHE__["github_archive_pkg_$url"]="$__ARCHIVE_PKG_NAME__"
	__DL_RESP_CACHE__["github_url_$url"]="$__GITHUB_URL__"
}

# Extracts version matching the archive logic: strips prefix (up to first '-') and suffix (arch/extension)
get_github_vers() {
	sed 's/^[^-]*-//;s/-\(all\|common\|arm64-v8a\|arm-v7a\|x86\|x86_64\)\.\(apk\|apkm\|xapk\|apks\)$//g' <<<"$__ARCHIVE_RESP__"
}

# Extracts package name by stripping everything from the first hyphen '-' onwards
get_github_pkg_name() {
	sed 's/-.*//' <<<"$__ARCHIVE_RESP__" | head -n 1
}

# -------------------- repo --------------------
get_repo_resp() {
	local url="${1%/}"
	local filter="${repo_dlurl_filter:-${args[repo_dlurl_filter]:-}}"
	local source_host="${repo_dlurl_source:-${args[repo_dlurl_source]:-github}}"
	[ -z "$source_host" ] && source_host="github"

	local cache_key="repo_${url}_${filter}_${source_host}"
	if [ -n "${__DL_RESP_CACHE__["$cache_key"]:-}" ]; then
		__REPO_RESP_JSON__="${__DL_RESP_CACHE__["$cache_key"]}"
		return 0
	fi

	local host="" host_instance=""
	if ! parse_host_spec "$source_host" host host_instance; then
		return 1
	fi
	if [[ "$url" =~ ^https?://[^/]+ ]]; then
		host_instance="${BASH_REMATCH[0]}"
	fi

	if [[ "$host" == "none" ]]; then
		local filename
		filename=$(basename "$url")
		local assets_json
		assets_json=$(jq -c -n --arg name "$filename" --arg url "$url" '[{name: $name, browser_download_url: $url, tag_name: "latest"}]')
		__REPO_RESP_JSON__="$assets_json"
		__DL_RESP_CACHE__["$cache_key"]="$assets_json"
		return 0
	fi

	local src="" tag=""
	src=$(echo "$url" | sed -E 's|https?://[^/]+/([^/]+/[^/]+).*|\1|')
	src="${src%.git}"
	src="${src%/releases}"
	if [[ "$url" == *"/releases/tag/"* ]]; then
		tag="${url##*/releases/tag/}"
	elif [[ "$url" == *"/tags/"* ]]; then
		tag="${url##*/tags/}"
	fi

	[ -z "$src" ] && return 1

	local api_url="" resp="" release=""
	api_url=$(source_release_api_base "$host" "$src" "$host_instance") || return 1

	if [ -n "$tag" ]; then
		local tag_api
		tag_api=$(source_release_tag_api "$host" "$src" "$tag" "$host_instance") || return 1
		resp=$({ if [ "$host" = github ]; then gh_req "$tag_api" -; else req "$tag_api" -; fi; }) || return 1
		release="[${resp}]"
	else
		resp=$({ if [ "$host" = github ]; then gh_req "${api_url}?per_page=100" -; else req "${api_url}?per_page=100" -; fi; }) || return 1
		release="$resp"
	fi

	if [ -z "$release" ] || [ "$release" = "[]" ]; then return 1; fi

	local mode="latest"
	if [ "${__AAV__:-false}" = true ] || [ "${version:-}" = "beta" ] || [ "${version:-}" = "dev" ] || [ "${version:-}" = "absolutelatest" ]; then
		mode="absolutelatest"
	fi

	local release_target
	release_target=$(source_release_pick_from_list "$host" "$mode" "$host_instance" <<<"$release" 2>/dev/null || true)
	if [ -n "$release_target" ] && [ "$release_target" != "null" ]; then
		release="[${release_target}]"
	fi

	local assets_json
	if [ -n "$filter" ]; then
		assets_json=$(jq -c --arg f "$filter" '
			(if type == "array" then . else [.] end) | map(
				. as $rel |
				(($rel.assets // []) + ($rel.assets_links // [])) | map(
					. as $asset |
					($asset.name // $asset.browser_download_url // "") as $name |
					select($name | test($f; "i")) |
					{
						name: $name,
						browser_download_url: ($asset.browser_download_url // $asset.url // ""),
						tag_name: ($rel.tag_name // "latest"),
						published_at: ($rel.published_at // $rel.created_at // $rel.released_at // "")
					}
				)
			) | flatten
		' <<<"$release") || return 1
	else
		assets_json=$(jq -c '
			(if type == "array" then . else [.] end) | map(
				. as $rel |
				(($rel.assets // []) + ($rel.assets_links // [])) | map(
					. as $asset |
					($asset.name // $asset.browser_download_url // "") as $name |
					select($name | test("\\.(apk|apkm|xapk|apks)$"; "i")) |
					{
						name: $name,
						browser_download_url: ($asset.browser_download_url // $asset.url // ""),
						tag_name: ($rel.tag_name // "latest"),
						published_at: ($rel.published_at // $rel.created_at // $rel.released_at // "")
					}
				)
			) | flatten
		' <<<"$release") || return 1
	fi

	if [ -z "$assets_json" ] || [ "$assets_json" = "[]" ]; then
		wpr "No matching APK assets found in repo releases for $url (filter: $filter)"
		return 1
	fi

	__REPO_RESP_JSON__="$assets_json"
	__DL_RESP_CACHE__["$cache_key"]="$assets_json"
}

get_repo_vers() {
	jq -r '.[].tag_name // empty' <<<"${__REPO_RESP_JSON__:-[]}" | sed 's/^v//i' | sort -u
}

get_repo_pkg_name() {
	local first_asset_name
	first_asset_name=$(jq -r '.[0].name // empty' <<<"${__REPO_RESP_JSON__:-[]}")
	if [ -n "$first_asset_name" ]; then
		sed 's/-.*//' <<<"$first_asset_name" | head -n 1
	else
		echo ""
	fi
}

dl_repo() {
	local url=$1 version=$2 output=$3 arch=$4 dpi=${5:-} get_latest_ver=${6:-false}
	local filter="${repo_dlurl_filter:-${args[repo_dlurl_filter]:-}}"
	local exclude_filter="${repo_dlurl_exclude_filter:-${args[repo_dlurl_exclude_filter]:-}}"

	local version_clean=${version#v}
	local matching_asset="" download_url="" asset_name=""

	matching_asset=$(jq -c --arg ver "$version" --arg ver_clean "$version_clean" --arg arch "${arch// /}" '
		map(
			select(
				(.tag_name == $ver or .tag_name == ("v" + $ver_clean) or .tag_name == $ver_clean)
			)
		) | .[0] // empty
	' <<<"${__REPO_RESP_JSON__:-[]}")

	if [ -z "$matching_asset" ]; then
		matching_asset=$(jq -c '.[0] // empty' <<<"${__REPO_RESP_JSON__:-[]}")
	fi

	if [ -z "$matching_asset" ]; then
		epr "Repo asset not found for version $version (arch $arch)"
		return 1
	fi

	download_url=$(jq -r '.browser_download_url // empty' <<<"$matching_asset")
	asset_name=$(jq -r '.name // empty' <<<"$matching_asset")

	[ -z "$download_url" ] && return 1

	pr "Downloading repo asset from ${url}: $asset_name ($download_url)"
	local ext="${asset_name##*.}"
	case "$ext" in
		apk)
			req "$download_url" "$output"
			;;
		apkm|xapk|apks)
			local bundle="${output}.${ext}"
			req "$download_url" "$bundle" || return 1
			merge_splits "$bundle" "$output"
			;;
		*)
			req "$download_url" "$output"
			;;
	esac
}


# -------------------- direct --------------------
dl_direct() {
	local url=$1 version=${2// /-} output=$3 arch=$4 _dpi=$5
	req "$url" "${output}" || return 1
}
get_direct_vers() { cut -d- -f2 <<<"$__DIRECT_APKNAME__" | sed 's/\.\(apk\|xapk\|apks\|apkm\)$//'; }
get_direct_pkg_name() { cut -d- -f1 <<<"$__DIRECT_APKNAME__" | sed 's/\.\(apk\|xapk\|apks\|apkm\)$//'; }
get_direct_resp() { __DIRECT_APKNAME__=$(awk -F/ '{print $NF}' <<<"$1"); }
# -------------------- local --------------------
dl_local() {
	local url=$1 version=${2// /-} output=$3 arch=$4 _dpi=$5
	cp "$url" "${output}" || return 1
}
get_local_vers() { cut -d- -f2 <<<"$__LOCAL_APKNAME__" | sed 's/\.\(apk\|xapk\|apks\|apkm\)$//'; }
get_local_pkg_name() { cut -d- -f1 <<<"$__LOCAL_APKNAME__" | sed 's/\.\(apk\|xapk\|apks\|apkm\)$//'; }
get_local_resp() { __LOCAL_APKNAME__=$(awk -F/ '{print $NF}' <<<"$1"); }
# --------------------------------------------------

patch_apk() {
	local stock_input=$1 patched_apk=$2 patcher_args=$3 cli_jar=$4 patches_jar=$5 cli_source=$6
	local per_bundle_ed="${7:-}"
	local tmp_dir="${CWD}/${patched_apk}-temporary-files"
	local IFS=$'\n'
	local p_jars=($(echo "$patches_jar" | tr ' ' '\n' | grep -v '^$'))
	unset IFS

	local cli_source_l="${cli_source,,}"
	if [[ "$cli_source_l" == "none" ]]; then
		pr "Passthrough mode (cli-source=none): Copying stock APK without patching"
		cp -f "$stock_input" "$patched_apk" || return 1
		return 0
	fi
	if [[ $cli_source_l == "apksigner" ]]; then
		PATCH_OUTPUT=$(sign_apk "${stock_input}" "${patched_apk}" verbose 2>&1)
		pr "Signed ${stock_input} to ${patched_apk}"
		return 0
	fi
	if [[ "$cli_source_l" == *"npatch"* ]] || [[ "$cli_source_l" == *"lspatch"* ]]; then
		local p_args_modules=""
		for j in "${p_jars[@]}"; do
			p_args_modules+=" -m '$j'"
		done
		mkdir -p "$tmp_dir"
		if [[ "$cli_source_l" == *"npatch"* ]]; then
			get_bcprov || return 1
			local cmd="java -cp 'temp/bcprov.jar$javapathsep$cli_jar' -Djava.security.properties=temp/bc.security top.nkbe.npatch.patch.NPatch -k $TEMP_DIR/ks.keystore  '$KEYSTORE_PASSWORD' '$KEYSTORE_ALIAS' '$KEYSTORE_KEY_PASSWORD' '$stock_input' -o '$tmp_dir' $p_args_modules $patcher_args"
		else
		local cmd="java -jar '$cli_jar' -o '$tmp_dir' $p_args_modules $patcher_args '$stock_input'"
		fi
		pr "$cmd"
		PATCH_OUTPUT=$(eval "$cmd" 2>&1)
		local ret=$?
		echo "$PATCH_OUTPUT"
		if [ $ret -eq 0 ]; then
			local npatch_out
			npatch_out=$(find "$tmp_dir" -type f -name "*.apk" | head -n 1)
			if [ -n "$npatch_out" ] && [ -f "$npatch_out" ]; then
				mv "$npatch_out" "$patched_apk"
				rm -rf "$tmp_dir"
				return 0
			fi
		fi
		rm "$patched_apk" 2>/dev/null || :
		rm -rf "$tmp_dir"
		return 1
	fi

	if [[ "$cli_source_l" == *"instafel"* ]]; then
		local rel_tmp_dir="${patched_apk}-temporary-files"
		mkdir -p "$rel_tmp_dir"
		local cli_dir
		cli_dir=$(dirname "$cli_jar")
		for j in "${p_jars[@]}"; do
			cp "$j" "$cli_dir/ifl-patcher-core-8e4756f.jar" 2>/dev/null || :
			cp "$j" "ifl-patcher-core-8e4756f.jar" 2>/dev/null || :
			cp "$j" "$rel_tmp_dir/ifl-patcher-core-8e4756f.jar" 2>/dev/null || :
		done

		local init_cmd="java -jar '$cli_jar' init '$stock_input'"
		pr "$init_cmd"
		local init_op
		init_op=$(eval "$init_cmd" 2>&1)
		pr "$init_op"

		local wdir=""
		local proj_file
		proj_file=$(find . "$rel_tmp_dir" -maxdepth 3 -type f -name "project.json" 2>/dev/null | head -n 1)
		if [ -n "$proj_file" ]; then
			wdir=$(dirname "$proj_file")
			wdir="${wdir#./}"
		fi

		if [ -z "$wdir" ] || [ ! -d "$wdir" ]; then
			epr "Instafel init failed to create project working directory for '$stock_input'."
			rm -rf "$rel_tmp_dir" 2>/dev/null || :
			return 1
		fi

		local patches_to_run=""
		if [ -n "$per_bundle_ed" ]; then
			patches_to_run=$(echo "$per_bundle_ed" | grep -oP "'\K[^']+" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
		fi
		if [ -z "$patches_to_run" ]; then
			patches_to_run="unlock_developer_options remove_snooze_warning remove_ads amoled_theme instafel"
		fi

		local run_cmd="java -jar '$cli_jar' run '$wdir' $patches_to_run"
		pr "$run_cmd"
		PATCH_OUTPUT=$(eval "$run_cmd" 2>&1)
		echo "$PATCH_OUTPUT"

		local build_cmd="java -jar '$cli_jar' build '$wdir'"
		pr "$build_cmd"
		local build_op
		build_op=$(eval "$build_cmd" 2>&1)
		echo "$build_op"
		PATCH_OUTPUT+=$'\n'"$build_op"

		local built_apk
		built_apk=$(find "$wdir/build" "$wdir" "$rel_tmp_dir" -maxdepth 5 -type f -name "*.apk" 2>/dev/null | grep -v "$stock_input" | head -n 1)
		if [ -n "$built_apk" ] && [ -f "$built_apk" ]; then
			sign_apk "$built_apk" "$patched_apk"
			rm -rf "$rel_tmp_dir" "$wdir" 2>/dev/null || :
			return 0
		else
			rm -f "$patched_apk" 2>/dev/null || :
			rm -rf "$rel_tmp_dir" "$wdir" 2>/dev/null || :
			return 1
		fi
	fi

	local base_cmd="java -jar '$cli_jar' patch '$stock_input' -t '$tmp_dir' -o '$patched_apk' --keystore=$TEMP_DIR/ks.keystore \
--keystore-entry-password=\"$KEYSTORE_KEY_PASSWORD\" --keystore-password=\"$KEYSTORE_PASSWORD\" --signer=\"$KEYSTORE_ALIAS\" --keystore-entry-alias=\"$KEYSTORE_ALIAS\""

	local -a ed_parts=()
	if [ -n "$per_bundle_ed" ]; then
		local IFS='|'
		read -ra ed_parts <<< "$per_bundle_ed"
		unset IFS
	fi

	local p_args_long="" p_args_short=""
	if [[ "$cli_source_l" == *"morphe-desktop"* ]]; then
		for ((i=0; i<${#p_jars[@]}; i++)); do
			local j="${p_jars[$i]}"
			local ed="${ed_parts[$i]:-}"
			p_args_long+=" --patches '$j'${ed}"
			p_args_short+=" -p '$j'${ed}"
		done
		local cmd_long="${base_cmd}${p_args_long} $patcher_args"
		local cmd_short="${base_cmd}${p_args_short} $patcher_args"
	else
		for j in "${p_jars[@]}"; do
			p_args_long+=" --patches '$j'"
			p_args_short+=" -p '$j'"
		done
		local all_ed="${ed_parts[*]}"
		local cmd_long="${base_cmd}${p_args_long} ${all_ed} $patcher_args"
		local cmd_short="${base_cmd}${p_args_short} ${all_ed} $patcher_args"
	fi

	# TODO: remove this later — revanced-cli needs -b to bypass build provenance checks
	local cli_name=$(basename "$cli_jar")
	if [ "${cli_name::8}" = revanced ]; then
		cmd_long+=" -b"
		cmd_short+=" -b"
	fi

	if [ "$OS" = Android ] && [ "${cli_name::8}" = revanced ]; then
		cmd_long+=" --custom-aapt2-binary='${AAPT2}'"
		cmd_short+=" --custom-aapt2-binary='${AAPT2}'"
	fi

	pr "$cmd_long"
	PATCH_OUTPUT=$(eval "$cmd_long" 2>&1)
	local ret=$?

	if [ $ret -ne 0 ] && echo "$PATCH_OUTPUT" | grep -Eq "Unknown option: '--patches'|Unmatched argument|Missing required argument"; then
		pr "Fallback to short syntax (-p)..."
		rm -rf "$tmp_dir" 2>/dev/null
		pr "$cmd_short"
		PATCH_OUTPUT=$(eval "$cmd_short" 2>&1)
		ret=$?
	fi

	echo "$PATCH_OUTPUT"
	if [ $ret -eq 0 ] && [ -f "$patched_apk" ]; then
		return 0
	else
		rm "$patched_apk" 2>/dev/null || :
		return 1
	fi
}


check_sig() {
	local file=$1 pkg_name=$2
	local sig
	if grep -q "$pkg_name" sig.txt; then
		sig=$(java -jar "$APKSIGNER" verify --print-certs "$file" | grep ^Signer | grep SHA-256 | tail -1 | awk '{print $NF}')
		echo "$pkg_name signature: ${sig}"
		grep -qFx "$sig $pkg_name" sig.txt
	fi
}

write_build_info() {
	local key=$1 arch=$2 ext=$3 name=$4 version=$5 patches=$6 changelog=$7
	if [ "$ext" = ".apk" ] || [ "$mode_arg" = module ]; then
		log "${key} (${arch}): ${version}"
	fi
	local arch_orig="${args[arch]// /}"
	if [ "$arch_orig" != "auto" ]; then ext="${arch}${ext}"; arch=""; fi
	# extract applied patches supporting revanced, morphe-desktop, and instafel output formats
	# revanced: INFO: "Patch Name" succeeded
	# morphe:   INFO: Applied: Patch Name
	# instafel: I: Patch 'Patch Name' loaded
	local applied_json
	applied_json=$(printf '%s\n' "$PATCH_OUTPUT" | grep -oP '(?<=INFO: ")[^"\n]+(?=" succeeded)|(?<=INFO: Applied: ).*|(?<=I: Patch \x27)[^\x27]+(?=\x27 loaded)' | jq -R -s -c 'split("\n") | map(select(length > 0))' 2>/dev/null || true)
	[[ "$applied_json" != \[* ]] && applied_json='[]'
	jq --arg key "$key" \
		--arg ext "$ext" \
		--arg arch "$arch" \
		--arg name "$name" \
		--arg version "$version" \
		--arg patches "$patches" \
		--arg changelog "$changelog" \
		--argjson applied "$applied_json" \
		'if has($key) then .[$key].exts = (.[$key].exts + [$ext] | unique) else .[$key] = {exts: [$ext], name: $name, arch: $arch, version: $version, patches: $patches, changlog: $changelog, applied_patches: $applied} end' \
		"$BUILD_JSON_FILE" > "${BUILD_JSON_FILE}.tmp" && mv "${BUILD_JSON_FILE}.tmp" "$BUILD_JSON_FILE"
}
verify_downloaded_apk() {
	local stock_apk=$1
	local pkg_name=$2
	local dl_p=$3
	local check_sig_val=${4:-false}

	if [ "$check_sig_val" != "true" ]; then
		return 0
	fi
	local sig_op
	
	if [ -f "${stock_apk%.apk}.apkm" ]; then
		rm -rf "${stock_apk}-zip" || :
		unzip -j "${stock_apk%.apk}.apkm" -d "${stock_apk}-zip" >/dev/null 2>&1
		if [ -f "${stock_apk}-zip/base.apk" ]; then
			if ! sig_op=$(check_sig "${stock_apk}-zip/base.apk" "$pkg_name" 2>&1); then
				epr "Signature mismatch on base.apk: $sig_op. Rejecting download from $dl_p..."
				rm -rf "${stock_apk}-zip" || :
				return 1
			fi
		else
			for a in "${stock_apk}"-zip/*.apk; do
				if ! sig_op=$(check_sig "$a" "$pkg_name" 2>&1); then
					epr "Signature mismatch on $a: $sig_op. Rejecting download from $dl_p..."
					rm -rf "${stock_apk}-zip" || :
					return 1
				fi
				break
			done
		fi
		rm -rf "${stock_apk}-zip" || :
	else
		if ! sig_op=$(check_sig "$stock_apk" "$pkg_name" 2>&1); then
			epr "Signature mismatch on $stock_apk: $sig_op. Rejecting download from $dl_p..."
			return 1
		fi
	fi
	return 0
}

get_apk_native_arch() {
	local apk_path="$1"
	[ -f "$apk_path" ] || { echo "all"; return 0; }

	local lib_entries=""
	if [ -n "${AAPT2:-}" ] && [ -x "$AAPT2" ]; then
		lib_entries=$("$AAPT2" dump badging "$apk_path" 2>/dev/null | grep -i "native-code:") || true
	fi

	if [ -z "$lib_entries" ]; then
		if [ -f "${apk_path%.apk}.apkm" ]; then
			lib_entries=$(unzip -l "${apk_path%.apk}.apkm" 2>/dev/null | grep -iE 'lib/|arm64|armeabi|x86') || true
		else
			lib_entries=$(unzip -l "$apk_path" 2>/dev/null | grep -iE 'lib/|arm64|armeabi|x86') || true
		fi
	fi

	if [ -z "$lib_entries" ] || (! grep -qi "native-code:" <<<"$lib_entries" && ! grep -qi "lib/" <<<"$lib_entries"); then
		echo "all"
		return 0
	fi

	local has_arm64=false has_armv7=false has_x86_64=false has_x86=false

	grep -qi "arm64-v8a\|arm64" <<<"$lib_entries" && has_arm64=true
	grep -qi "armeabi-v7a\|armeabi\|arm-v7a" <<<"$lib_entries" && has_armv7=true
	grep -qi "x86_64" <<<"$lib_entries" && has_x86_64=true
	grep -qi "x86" <<<"$lib_entries" && grep -vqi "x86_64" <<<"$lib_entries" && has_x86=true

	# 1. Output "all" if:
	# - Both x86_64 and arm64-v8a exist
	# - All 4 ABIs exist
	# - Both x86 and arm (v7a) exist
	# - x86, arm (v7a), and arm64-v8a exist
	if [ "$has_x86_64" = true ] && [ "$has_arm64" = true ]; then
		wpr "Assumed architecture 'all' based on native libraries (found x86_64 + arm64-v8a)" >&2
		echo "all"
		return 0
	elif [ "$has_x86" = true ] && [ "$has_armv7" = true ]; then
		wpr "Assumed architecture 'all' based on native libraries (found x86 + arm)" >&2
		echo "all"
		return 0
	fi

	# 2. Both arm64-v8a AND armeabi-v7a exist -> assume "arm64-v8a"
	if [ "$has_arm64" = true ] && [ "$has_armv7" = true ]; then
		wpr "Assumed architecture 'arm64-v8a' based on native libraries (found arm64-v8a + armeabi-v7a)" >&2
		echo "arm64-v8a"
		return 0
	fi

	# 3. x86_64 AND x86 exist -> considered "x86_64"
	if [ "$has_x86_64" = true ] && [ "$has_x86" = true ]; then
		wpr "Assumed architecture 'x86_64' based on native libraries (found x86_64 + x86)" >&2
		echo "x86_64"
		return 0
	fi

	# 4. Specific single ABI detection
	if [ "$has_arm64" = true ]; then
		echo "arm64-v8a"
	elif [ "$has_armv7" = true ]; then
		echo "arm-v7a"
	elif [ "$has_x86_64" = true ]; then
		echo "x86_64"
	elif [ "$has_x86" = true ]; then
		echo "x86"
	else
		echo "all"
	fi
}

check_is_universal() {
	local stock_apk=$1
	local detected_arch
	detected_arch=$(get_apk_native_arch "$stock_apk")
	if [ "$detected_arch" = "all" ] || [ "$detected_arch" = "universal" ]; then
		return 0
	fi
	return 1
}

build_rv() {
	eval "declare -A args=${1#*=}"
	local version="${args[version]:-}" pkg_name="${args[pkg_name]:-}"
	
	if [ -z "$pkg_name" ]; then
		if [ -n "${args[github_dlurl]}" ] && [[ "${args[github_dlurl]}" == *"releases/tag/"* ]]; then
			local tmp="${args[github_dlurl]%/}"
			pkg_name="${tmp##*/}"
		elif [ -n "${args[archive_dlurl]}" ] && [[ "${args[archive_dlurl]}" == *"apks/"* ]]; then
			local tmp="${args[archive_dlurl]%/}"
			pkg_name="${tmp##*/}"
		fi
	fi
	local prefer_dl_mode=${args[prefer_dl_mode]}
	local apkmirror_example_url=${args[apkmirror_example_url]}
	local cli_jar="${args[cli]}"
	local patches_jar="${args[ptjar]}"
	local mode_arg=${args[build_mode]} version_mode=${args[version]}
	local app_name=${args[app_name]}
	local app_name_l=${app_name,,}
	app_name_l=${app_name_l// /-}
	local table=${args[table]}
	local dl_from=${args[dl_from]}
	local arch=${args[arch]}
	local arch_f="${arch// /}"
	local arch_list=("$arch_f")
	[ "$arch_f" = "auto" ] && arch_list=("all" "arm64-v8a" "arm-v7a")

	local IFS=$'\n'
	local p_jars_arr=($(echo "${args[ptjar]}" | tr ' ' '\n' | grep -v '^$'))
	unset IFS
	local n_bundles=${#p_jars_arr[@]}
	local -a p_srcs_arr=(${args[patches_sources_all]:-})

	local -a per_bundle_ed_args=()
	local exc_str="${args[excluded_patches]}"
	local inc_str="${args[included_patches]}"

	if [[ "$exc_str" == *"|"* ]] || [[ "$inc_str" == *"|"* ]]; then
		local -a exc_parts=() inc_parts=()
		IFS='|' read -ra exc_parts <<< "$exc_str"
		IFS='|' read -ra inc_parts <<< "$inc_str"
		
		for ((bi=0; bi<n_bundles; bi++)); do
			local bundle_ed=""
			local bp_exc="${exc_parts[$bi]:-}"
			local bp_inc="${inc_parts[$bi]:-}"
			bp_exc=$(echo "$bp_exc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
			bp_inc=$(echo "$bp_inc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
			if [ -n "$bp_exc" ]; then bundle_ed+=" $(join_args "$bp_exc" -d)"; fi
			if [ -n "$bp_inc" ]; then bundle_ed+=" $(join_args "$bp_inc" -e)"; fi

			local is_exclusive=false
			if [ "${args[exclusive_patches]}" = "true" ]; then
				is_exclusive=true
			elif [ "${args[exclusive_patches]}" != "false" ] && [ -n "${args[exclusive_patches]}" ]; then
				local current_src="${p_srcs_arr[$bi]:-}"
				local -a exc_srcs=($(list_args "${args[exclusive_patches]}" | tr -d \"\'))
				[ ${#exc_srcs[@]} -eq 0 ] && exc_srcs=("${args[exclusive_patches]}")
				for esrc in "${exc_srcs[@]}"; do
					if [ "$esrc" = "$current_src" ]; then
						is_exclusive=true
						break
					fi
				done
			fi
			if [ "$is_exclusive" = true ]; then
				local all_patches_op
				if all_patches_op=$(patches_list "$cli_jar" "${p_jars_arr[$bi]}" "$pkg_name" "${args[cli_source]}"); then
					local all_patches=()
					mapfile -t all_patches < <(echo "$all_patches_op" | grep -iE '^[[:space:]]*Name:' | sed -E 's/^[[:space:]]*Name:[[:space:]]*//I' | sed 's/[[:space:]]*$//')
					
					local new_bp_exc="$bp_exc"
					local -a current_bp_inc=()
					bp_inc=$(echo "$bp_inc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
					if [ -n "$bp_inc" ]; then
						while IFS= read -r p; do
							[ -n "$p" ] && current_bp_inc+=("$p")
						done <<< "$(list_args "$bp_inc" | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')"
					fi
					
					local new_bp_exc="$bp_exc"
					for p_name in "${all_patches[@]}"; do
						local found=false
						for inc_p in "${current_bp_inc[@]}"; do
							if [ "$p_name" = "$inc_p" ]; then
								found=true
								break
							fi
						done
						if [ "$found" = false ]; then
							new_bp_exc+=" '$p_name'"
						fi
					done
					bp_exc="$new_bp_exc"
					
					bundle_ed=""
					bp_exc=$(echo "$bp_exc" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
					if [ -n "$bp_exc" ]; then bundle_ed+=" $(join_args "$bp_exc" -d)"; fi
					if [ -n "$bp_inc" ]; then bundle_ed+=" $(join_args "$bp_inc" -e)"; fi
				else
					epr "FATAL: Failed to fetch patch list for exclusive bundle '${p_jars_arr[$bi]}'. Cannot safely apply per-bundle exclusivity."
					return 1
				fi
			fi
			per_bundle_ed_args+=("$bundle_ed")
		done
	else
		local global_ed=""
		if [ -n "$exc_str" ]; then global_ed+=" $(join_args "$exc_str" -d)"; fi
		if [ -n "$inc_str" ]; then global_ed+=" $(join_args "$inc_str" -e)"; fi
		
		for ((bi=0; bi<n_bundles; bi++)); do
			local bundle_ed="$global_ed"
			local is_exclusive=false
			if [ "${args[exclusive_patches]}" = "true" ]; then
				is_exclusive=true
			elif [ "${args[exclusive_patches]}" != "false" ] && [ -n "${args[exclusive_patches]}" ]; then
				local current_src="${p_srcs_arr[$bi]:-}"
				local -a exc_srcs=($(list_args "${args[exclusive_patches]}" | tr -d \"\'))
				[ ${#exc_srcs[@]} -eq 0 ] && exc_srcs=("${args[exclusive_patches]}")
				for esrc in "${exc_srcs[@]}"; do
					if [ "$esrc" = "$current_src" ]; then
						is_exclusive=true
						break
					fi
				done
			fi
			[ "$is_exclusive" = true ] && bundle_ed+=" --exclusive"
			per_bundle_ed_args+=("$bundle_ed")
		done
	fi

	local p_patcher_args=()
	if isoneof "$version_mode" latest beta || [ "$version_mode" != "auto" -a "$version_mode" != "exp" ]; then
		p_patcher_args+=("-f")
	fi

	local tried_dl=()
	local list_patches=""
	local apk_cache_dir="${APK_CACHE_DIR:-${TEMP_DIR}/apks}"
	local apk_dl_dir="${TEMP_DIR}/apks_dl"
	mkdir -p "$apk_cache_dir" "$apk_dl_dir"

	local skip_dl_source_check=false
	local resolved_version=""
	local get_latest_ver=false

	# 1. Resolve pkg_name early if possible and check cache
	if [ -n "$pkg_name" ]; then
		# Check app_versions.json for exact version
		local app_versions_file=".github/configs/app_versions.json"
		if [ -f "$app_versions_file" ]; then
			local json_ver=$(jq -r --arg t "$table" 'to_entries | map(select(.key | startswith("_") | not)) | map(select(.value.keys != null and (.value.keys | index($t)))) | .[0].value.version // empty' "$app_versions_file")
			if [ -n "$json_ver" ]; then
				resolved_version="$json_ver"
			fi
		fi

		list_patches=$(patches_list "$cli_jar" "$patches_jar" "$pkg_name" "${args[cli_source]}") || return 1
		local cli_source_l="${args[cli_source],,}"
		if [[ "$cli_source_l" == *"revanced"* ]] || [[ "$cli_source_l" == *"morphe"* ]]; then
			if ! grep -Fq "$pkg_name" <<<"$list_patches"; then
				epr "No app-specific patches found for '$pkg_name'. Skipping completely."
				return 0
			fi
		fi

		if [ -z "$resolved_version" ]; then
			if [ "$version_mode" = auto ]; then
				if ! resolved_version=$(get_patch_last_supported_ver "$list_patches" "$pkg_name" \
					"${args[included_patches]:-}" "${args[excluded_patches]:-}" "${args[exclusive_patches]:-}" "${args[cli_source]:-}"); then
					epr "get_patch_last_supported_ver failed for '$pkg_name'"
					return 0
				fi
			elif [ "$version_mode" = exp ]; then
				if [[ "$cli_source_l" == *"revanced/revanced-cli"* ]]; then
					wpr "ReVanced CLI does not support experimental versions."
					return 0
				fi
				if ! resolved_version=$(get_patch_exp_ver "$cli_jar" "$patches_jar" "$pkg_name" "${args[cli_source]}"); then
					epr "get_patch_exp_ver failed"
				fi
				if [ -z "$resolved_version" ]; then
					epr "No exp version found for '$pkg_name', skipping."
					return 0
				fi
			elif isoneof "$version_mode" latest beta; then
				: # Needs latest
			else
				resolved_version=$version_mode
			fi
		fi

		# Cache Check
		if [ -n "$resolved_version" ]; then
			local version_f=${resolved_version// /}
			version_f=${version_f#v}
			local all_archs_found=true
			for arch in "${arch_list[@]}"; do
				arch_f="${arch// /}"
				local stock_apk="${apk_cache_dir}/${pkg_name}-${version_f}-${arch_f}.apk"
				local all_apk="${apk_cache_dir}/${pkg_name}-${version_f}-all.apk"

				if [ ! -f "$stock_apk" ] && [ ! -f "$all_apk" ]; then
					all_archs_found=false
					break
				fi
			done
			if [ "$all_archs_found" = true ]; then
				for arch in "${arch_list[@]}"; do
					arch_f="${arch// /}"
					local stock_apk="${apk_cache_dir}/${pkg_name}-${version_f}-${arch_f}.apk"
					local all_apk="${apk_cache_dir}/${pkg_name}-${version_f}-all.apk"
					[ -f "$stock_apk" ] && touch "$stock_apk" 2>/dev/null || true
					[ -f "$all_apk" ] && touch "$all_apk" 2>/dev/null || true
				done
				pr "Found all required architectures for '$pkg_name' (v$version_f) in cache. Skipping download!"
				skip_dl_source_check=true
				version="$resolved_version"
			fi
		else
			# Dynamic Cache Discovery for "latest" or empty version
			local cached_apks=($(find "$apk_cache_dir" -name "${pkg_name}-*.apk" -type f 2>/dev/null || true))
			if [ ${#cached_apks[@]} -gt 0 ]; then
				local cached_versions=""
				for capk in "${cached_apks[@]}"; do
					local bname=$(basename "$capk")
					# extract version from format: pkg_name-version-arch.apk
					local v=${bname#${pkg_name}-}
					v=${v%-*}
					cached_versions+="$v"$'\n'
				done
				local dyn_ver
				if dyn_ver=$(echo "$cached_versions" | get_highest_ver) && [ -n "$dyn_ver" ]; then
					local all_archs_found=true
					for arch in "${arch_list[@]}"; do
						arch_f="${arch// /}"
						local stock_apk="${apk_cache_dir}/${pkg_name}-${dyn_ver}-${arch_f}.apk"
						local all_apk="${apk_cache_dir}/${pkg_name}-${dyn_ver}-all.apk"
						if [ ! -f "$stock_apk" ] && [ ! -f "$all_apk" ]; then
							all_archs_found=false
							break
						fi
					done
					if [ "$all_archs_found" = true ]; then
						for arch in "${arch_list[@]}"; do
							arch_f="${arch// /}"
							local stock_apk="${apk_cache_dir}/${pkg_name}-${dyn_ver}-${arch_f}.apk"
							local all_apk="${apk_cache_dir}/${pkg_name}-${dyn_ver}-all.apk"
							[ -f "$stock_apk" ] && touch "$stock_apk" 2>/dev/null || true
							[ -f "$all_apk" ] && touch "$all_apk" 2>/dev/null || true
						done
						pr "Discovered highest version (v$dyn_ver) for '$pkg_name' in cache. Skipping download!"
						skip_dl_source_check=true
						version="$dyn_ver"
						resolved_version="$dyn_ver"
					fi
				fi
			fi
		fi
	fi

	if [ "$skip_dl_source_check" = false ]; then
		# 2. Establish dl_from and fetch required HTML responses
		for dl_p in "${DL_SRCS[@]}"; do
			if [ -z "${args[${dl_p}_dlurl]}" ]; then continue; fi
			
			# If we need to find the latest version, do not use cache repositories as the source of truth
			if [ -z "$resolved_version" ]; then
				if [ "$dl_p" = "archive" ] || [ "$dl_p" = "github" ]; then
					continue
				fi
			fi

			if ! get_${dl_p}_resp "${args[${dl_p}_dlurl]}"; then
				args[${dl_p}_dlurl]=""
				epr "ERROR: Could not get response for ${table} in ${dl_p}"
				continue
			fi
			
			# If pkg_name is still empty, try to scrape it from the response
			if [ -z "$pkg_name" ]; then
				if ! pkg_name=$(get_"${dl_p}"_pkg_name) || [ -z "$pkg_name" ]; then
					args[${dl_p}_dlurl]=""
					epr "ERROR: Could not scrape pkg_name for ${table} in ${dl_p}"
					continue
				fi
			fi
			
			tried_dl+=("$dl_p")
			dl_from=$dl_p
			break
		done

		if [ -z "$dl_from" ]; then
			epr "ERROR: No valid download source found for ${table}."
			return 0
		fi

		if [ -z "$pkg_name" ]; then
			epr "ERROR: Could not determine pkg_name for ${table}."
			return 0
		fi
		
		# If we didn't run patches_list earlier because pkg_name was empty
		if [ -z "$list_patches" ]; then
			pr "Package name of '${table}' is '$pkg_name'"
			list_patches=$(patches_list "$cli_jar" "$patches_jar" "$pkg_name" "${args[cli_source]}") || return 1
			
			local cli_source_l="${args[cli_source],,}"
			if [[ "$cli_source_l" == *"revanced"* ]] || [[ "$cli_source_l" == *"morphe"* ]]; then
				if ! grep -Fq "$pkg_name" <<<"$list_patches"; then
					epr "No app-specific patches found for '$pkg_name'. Skipping completely."
					return 0
				fi
			fi
		fi

		if [ -z "$resolved_version" ]; then
			if [ "$version_mode" = auto ]; then
				if ! resolved_version=$(get_patch_last_supported_ver "$list_patches" "$pkg_name" \
					"${args[included_patches]:-}" "${args[excluded_patches]:-}" "${args[exclusive_patches]:-}" "${args[cli_source]:-}"); then
					epr "get_patch_last_supported_ver failed for '$pkg_name'"
					return 0
				fi
			elif [ "$version_mode" = exp ]; then
				local cli_source_l="${args[cli_source],,}"
				if [[ "$cli_source_l" == *"revanced/revanced-cli"* ]]; then
					wpr "ReVanced CLI does not support experimental versions."
					return 0
				fi
				if ! resolved_version=$(get_patch_exp_ver "$cli_jar" "$patches_jar" "$pkg_name" "${args[cli_source]}"); then
					epr "get_patch_exp_ver failed"
				fi
				if [ -z "$resolved_version" ]; then
					epr "No exp version found for '$pkg_name', skipping."
					return 0
				fi
			elif isoneof "$version_mode" latest beta; then
				:
			else
				resolved_version=$version_mode
			fi
		fi
		
		version="$resolved_version"
		[ -z "$version" ] && get_latest_ver=true
		if [ $get_latest_ver = true ]; then
			if [ "$version_mode" = beta ]; then __AAV__="true"; else __AAV__="false"; fi
			local vers_cache_key="${dl_from}_${args[${dl_from}_dlurl]}_${__AAV__}"
			if [ -n "${__PKG_VERS_CACHE__["$vers_cache_key"]:-}" ]; then
				pkgvers="${__PKG_VERS_CACHE__["$vers_cache_key"]}"
			else
				pkgvers=$(get_"${dl_from}"_vers)
				__PKG_VERS_CACHE__["$vers_cache_key"]="$pkgvers"
			fi
			version=$(get_highest_ver <<<"$pkgvers") || version=$(head -1 <<<"$pkgvers")
		fi
	else
		pr "Package name of '${table}' is '$pkg_name'"
		pr "Skipping download source check, APKs for version '$version' found in cache."
	fi
	if [ -z "$version" ]; then
		epr "empty version, not building ${table}."
		return 0
	fi

	if [ "$mode_arg" = module ]; then
		build_mode_arr=(module)
	elif [ "$mode_arg" = apk ]; then
		build_mode_arr=(apk)
	elif [ "$mode_arg" = both ]; then
		build_mode_arr=(apk module)
	fi

	pr "Choosing version '${version}' for ${table}"
	local version_f=${version// /}
	version_f=${version_f#v}
	for arch in "${arch_list[@]}"; do
		arch_f="${arch// /}"
		local cached_stock_apk="${apk_cache_dir}/${pkg_name}-${version_f}-${arch_f}.apk"
		local cached_all_apk="${apk_cache_dir}/${pkg_name}-${version_f}-all.apk"
		local stock_apk="$cached_stock_apk"
		local all_apk="$cached_all_apk"
		if [ -f "$all_apk" ]; then
			local missing_arch=false
			if [ "$arch_f" = "arm64-v8a" ] && ! unzip -l "$all_apk" 2>/dev/null | grep -q "lib/arm64-v8a/"; then
				unzip -l "$all_apk" 2>/dev/null | grep -q "lib/" && missing_arch=true
			elif [ "$arch_f" = "arm-v7a" ] && ! unzip -l "$all_apk" 2>/dev/null | grep -q "lib/armeabi-v7a/"; then
				unzip -l "$all_apk" 2>/dev/null | grep -q "lib/" && missing_arch=true
			elif [ "$arch_f" = "x86" ] && ! unzip -l "$all_apk" 2>/dev/null | grep -q "lib/x86/"; then
				unzip -l "$all_apk" 2>/dev/null | grep -q "lib/" && missing_arch=true
			elif [ "$arch_f" = "x86_64" ] && ! unzip -l "$all_apk" 2>/dev/null | grep -q "lib/x86_64/"; then
				unzip -l "$all_apk" 2>/dev/null | grep -q "lib/" && missing_arch=true
			fi
			if [ "$missing_arch" = false ]; then
				stock_apk="$all_apk"
			fi
		fi
		if [ ! -f "$stock_apk" ]; then
			# Redirect to staging directory for safe downloading and processing
			stock_apk="${apk_dl_dir}/${pkg_name}-${version_f}-${arch_f}.apk"
			all_apk="${apk_dl_dir}/${pkg_name}-${version_f}-all.apk"

			for dl_p in "${DL_SRCS[@]}"; do
				if [ -z "${args[${dl_p}_dlurl]}" ]; then continue; fi
				pr "Downloading '${table}' from '${dl_p}'"
				if ! isoneof $dl_p "${tried_dl[@]}"; then
					if ! get_${dl_p}_resp "${args[${dl_p}_dlurl]}"; then
						epr "ERROR: Could not get '${table}' from '${dl_p}'"
						continue
					fi
				fi
				if ! dl_${dl_p} "${args[${dl_p}_dlurl]}" "$version" "$stock_apk" "$arch" "${args[dpi]}" "$get_latest_ver"; then
					pr "ERROR: Could not download '${table}' from '${dl_p}' with version '${version}', arch '${arch}', dpi '${args[dpi]}'"
					continue
				fi
				if ! unzip -l "$stock_apk" >/dev/null 2>&1; then
					epr "ERROR: Downloaded file from ${dl_p} is not a valid zip archive (Cloudflare block or bad file)!"
					rm -f "$stock_apk"
					continue
				fi
				if ! unzip -l "$stock_apk" 2>/dev/null | grep '^[[:space:]]*[0-9].*AndroidManifest\.xml$'; then
					pr "WARNING: ${stock_apk} does not contain AndroidManifest.xml at root. Attempting to extract as XAPK/APKS..."
					mv "$stock_apk" "${stock_apk}.xapk"
					if ! _apkpure_install_xapk "${stock_apk}.xapk" "$stock_apk"; then
						epr "ERROR: Failed to extract XAPK/APKS"
						rm -f "${stock_apk}.xapk" "$stock_apk"
						continue
					fi
					rm -f "${stock_apk}.xapk"
				fi

					local downloaded_pkg downloaded_ver
				downloaded_pkg=$("$AAPT2" dump badging "$stock_apk" 2>/dev/null | grep -oP "package: name='\K[^']+" | head -1) || true
				downloaded_ver=$("$AAPT2" dump badging "$stock_apk" 2>/dev/null | grep -oP "versionName='\K[^']+" | head -1) || true
					
					if [ -z "$downloaded_pkg" ]; then
					epr "ERROR: Downloaded file is not a valid APK or aapt2 failed to parse it. Rejecting..."
						rm -f "$stock_apk"
						continue
					fi

					if [ -n "$downloaded_pkg" ] && [ "$downloaded_pkg" != "$pkg_name" ] && [[ "$pkg_name" == *.* ]]; then
						epr "ERROR: Downloaded APK package name ($downloaded_pkg) does not match expected ($pkg_name). Rejecting..."
						rm -f "$stock_apk"
						continue
					fi

				if [ -n "$downloaded_ver" ] && { [[ "$dl_p" == "direct" ]] || [[ "$dl_p" == "local" ]] || [[ "$dl_p" == "repo" ]]; }; then
						if [ "$version" != "$downloaded_ver" ]; then
							pr "Updating version from '${version}' to '${downloaded_ver}' based on APK info"
							version="$downloaded_ver"
							version_f=${version// /}
							version_f=${version_f#v}
							
							local new_stock_apk="${TEMP_DIR}/${pkg_name}-${version_f}-${arch_f}.apk"
							mv "$stock_apk" "$new_stock_apk"
							stock_apk="$new_stock_apk"
						fi
					fi
				if ! verify_downloaded_apk "$stock_apk" "$pkg_name" "$dl_p" "${args[check_sig]:-false}"; then
					rm -f "$stock_apk" "${stock_apk%.apk}.apkm"
					continue
				fi
				break
			done
			if [ -f "$stock_apk" ] && [ ! -f "$all_apk" ] && [[ "$arch" != "all" && "$arch" != "universal" && "$arch" != "common" ]]; then
				if check_is_universal "$stock_apk"; then
					mv -f "$stock_apk" "$all_apk"
					if [ -f "${stock_apk%.apk}.apkm" ]; then
						mv -f "${stock_apk%.apk}.apkm" "${all_apk%.apk}.apkm"
					fi
					stock_apk="$all_apk"
				fi
			fi
			
			# Sync pristine files from staging to cache
			if [ -f "$stock_apk" ]; then
				if [ "$stock_apk" = "$all_apk" ]; then
					cp -f "$all_apk" "$cached_all_apk"
					stock_apk="$cached_all_apk"
				else
					cp -f "$stock_apk" "$cached_stock_apk"
					stock_apk="$cached_stock_apk"
				fi
				all_apk="$cached_all_apk"
			fi

			if [ -f "$stock_apk" ] && [ -n "${UPLOAD_APKS_REPO:-}" ] && [ "$dl_p" != "github" ] && [ "$dl_p" != "archive" ]; then
				pr "Uploading newly downloaded APKs to ${UPLOAD_APKS_REPO}..."
				if gh release view "$pkg_name" --repo "$UPLOAD_APKS_REPO" >/dev/null 2>&1 || gh release create "$pkg_name" --repo "$UPLOAD_APKS_REPO" --title "$pkg_name" --notes ""; then
					if [ -f "$all_apk" ]; then
						gh release upload "$pkg_name" "$all_apk" --repo "$UPLOAD_APKS_REPO" --clobber || true
					else
						gh release upload "$pkg_name" "$stock_apk" --repo "$UPLOAD_APKS_REPO" --clobber || true
					fi
				else
					wpr "Failed to view/create release $pkg_name on $UPLOAD_APKS_REPO"
				fi
			fi
		else
			pr "Found APK in cache: ${stock_apk}. Skipping download!"
		fi
		if [ -f "$stock_apk" ]; then break; fi
	done
	if [ ! -f "$stock_apk" ]; then
		epr "ERROR: Could not download '${table}'"
		return 0
	fi

	# Ensure the mtime is set to now so newly downloaded APKs with old server timestamps aren't purged
	touch "$stock_apk" 2>/dev/null || true
	[ -f "${stock_apk%.apk}.apkm" ] && touch "${stock_apk%.apk}.apkm" 2>/dev/null || true
	[ -n "${all_apk:-}" ] && [ -f "$all_apk" ] && touch "$all_apk" 2>/dev/null || true

	# Log usage for apks repo cache sync
	echo "${pkg_name}-${version_f}" >> "$TEMP_DIR/used_versions.txt"

	local sig_op
	if [[ "${args[check_sig]:-false}" == "true" ]]; then
		if [ -f "${stock_apk%.apk}.apkm" ]; then
			rm -rf "${stock_apk}-zip" || :
			unzip -j "${stock_apk%.apk}.apkm" -d "${stock_apk}-zip" >/dev/null 2>&1
			if [ -f "${stock_apk}-zip/base.apk" ]; then
				if ! sig_op=$(check_sig "${stock_apk}-zip/base.apk" "$pkg_name" 2>&1); then
					epr "Not building $table, apk signature mismatch 'base.apk': $sig_op"
					rm -rf "${stock_apk}-zip" || :
					return 0
				fi
			else
				for a in "${stock_apk}"-zip/*.apk; do
					if ! sig_op=$(check_sig "$a" "$pkg_name" 2>&1); then
						epr "Not building $table, apk signature mismatch '$a': $sig_op"
						rm -rf "${stock_apk}-zip" || :
						return 0
					fi
					break # Only check one APK if no base.apk
				done
			fi
			rm -rf "${stock_apk}-zip" || :
		else
		if ! sig_op=$(check_sig "$stock_apk" "$pkg_name" 2>&1); then
			epr "Not building $table, apk signature mismatch '$stock_apk': $sig_op"
			return 0
		fi
	fi
	fi

	local microg_patches=()
	local IFS='|'
	if [[ -n ${args[custom_microg_patches]:-} ]]; then
		local listpatches=$(join_args "${args[custom_microg_patches]}" "|")
		for p in $listpatches; do
			microg_patches+=("$p")
		done
	else
	local IFS=$'
'
	for p in $(grep "^Name: " <<<"$list_patches" | grep -i "gmscore\|microg" | sed 's/^Name: //' || :); do
		microg_patches+=("$p")
	done
	unset IFS
	fi
	if [ ${#microg_patches[@]} -gt 0 ]; then
		local found=false
		for p in "${microg_patches[@]}"; do
			if [[ "${p_patcher_args[*]}" == *"$p"* ]]; then
				found=true
				p_patcher_args=("${p_patcher_args[@]//-[ei] \'$p\'/}")
				p_patcher_args=("${p_patcher_args[@]//-[ei] \"$p\"/}")
				p_patcher_args=("${p_patcher_args[@]//-[ei] $p/}")
			fi
		done
		if [ "$found" = true ]; then
			wpr "You cant include/exclude microg patch as that's done by rvmm builder automatically."
		fi
	fi

	local patcher_args patched_apk build_mode
	local rv_brand_f=${args[rv_brand],,}
	rv_brand_f=${rv_brand_f// /-}
	local patches_ref="${args[patches_ref]}"
	local changelog_url="${args[changelog_url]}"
	if [ "${args[patcher_args]}" ]; then p_patcher_args+=("${args[patcher_args]}"); fi
	for build_mode in "${build_mode_arr[@]}"; do
		patcher_args=("${p_patcher_args[@]}")
		local -a cur_per_bundle_ed_args=("${per_bundle_ed_args[@]}")
		pr "Building '${table}' in '$build_mode' mode"
		if [ ${#microg_patches[@]} -gt 0 ]; then
			patched_apk="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${version_f}-${arch_f}-${build_mode}.apk"
		else
			patched_apk="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${version_f}-${arch_f}.apk"
		fi
		if [ ${#microg_patches[@]} -gt 0 ]; then
			for p in "${microg_patches[@]}"; do
				local mg_arg=""
				if [ "$build_mode" = apk ]; then
					mg_arg=" -e \"$p\""
				elif [ "$build_mode" = module ]; then
					mg_arg=" -d \"$p\""
				fi
				for ((bi=0; bi<n_bundles; bi++)); do
					cur_per_bundle_ed_args[$bi]+="$mg_arg"
				done
			done
		fi
		if [ "$build_mode" = module ]; then
			local cli_src_lower="${args[cli_source],,}"
			if [[ "$cli_src_lower" != *"revanced-cli"* ]] && [[ "$cli_src_lower" != *"npatch"* ]] && [[ "$cli_src_lower" != *"lspatch"* ]] && [[ "$cli_src_lower" != *"instafel"* ]] && [[ "$cli_src_lower" != "apksigner" ]]; then
				patcher_args+=("--mount")
			fi
		fi

		local stock_apk_to_patch="${TEMP_DIR}/${app_name_l}-${rv_brand_f}-${version_f}-${arch_f}.stripped.apk"
		if [ ! -f "$stock_apk_to_patch" ]; then
			cp -f "$stock_apk" "$stock_apk_to_patch"
			if [ "$arch" = "arm64-v8a" ]; then
				zip -d "$stock_apk_to_patch" "lib/armeabi-v7a/*" "lib/x86_64/*" "lib/x86/*" >/dev/null 2>&1 || :
			elif [ "$arch" = "arm-v7a" ]; then
				zip -d "$stock_apk_to_patch" "lib/arm64-v8a/*" "lib/x86_64/*" "lib/x86/*" >/dev/null 2>&1 || :
			elif [ "$arch" = "x86" ]; then
				zip -d "$stock_apk_to_patch" "lib/arm64-v8a/*" "lib/x86_64/*" "lib/armeabi-v7a/*" >/dev/null 2>&1 || :
			elif [ "$arch" = "x86_64" ]; then
				zip -d "$stock_apk_to_patch" "lib/arm64-v8a/*" "lib/armeabi-v7a/*" "lib/x86/*" >/dev/null 2>&1 || :
			fi
		fi

		local per_bundle_ed_joined=""
		for ((bi=0; bi<n_bundles; bi++)); do
			[ $bi -gt 0 ] && per_bundle_ed_joined+="|"
			per_bundle_ed_joined+="${cur_per_bundle_ed_args[$bi]}"
		done

		local apk_output="${BUILD_DIR}/${app_name_l}-${rv_brand_f}-v${version_f}-${arch_f}.apk"
		if [ "${NORB:-}" != true ] || { [ ! -f "$patched_apk" ] && [ ! -f "$apk_output" ]; }; then
			if ! patch_apk "$stock_apk_to_patch" "$patched_apk" "${patcher_args[*]}" "${args[cli]}" "${args[ptjar]}" "${args[cli_source]}" "$per_bundle_ed_joined"; then
				epr "Building '${table}' failed!"
				return 0
			fi
		fi

		if [ "$build_mode" = apk ]; then
			if [ "${NORB:-}" != true ] || { [ ! -f "$patched_apk" ] && [ ! -f "$apk_output" ]; }; then
				mv -f "$patched_apk" "$apk_output"
			else
				cp -f "$patched_apk" "$apk_output"
			fi
			pr "Built ${table} (non-root): '${apk_output}'"
			write_build_info "${table% (*}" "${arch_f}" ".apk" "${app_name_l}-${rv_brand_f}" "$version_f" "$patches_ref" "$changelog_url"
			continue
		fi
		local base_template
		base_template=$(mktemp -d -p "$TEMP_DIR")
		cp -a $MODULE_TEMPLATE_DIR/. "$base_template"
		local upj="${table,,}-update.json"

		module_config "$base_template" "$pkg_name" "$version_f" "$arch"

		local patches_ver
		patches_ver="${patches_jar%% *}"; patches_ver="${patches_ver##*-}"
		module_prop \
			"${args[module_prop_name]}" \
			"${app_name} ${args[rv_brand]}" \
			"${version_f} (patches ${patches_ver})" \
			"${app_name} ${args[rv_brand]} module" \
			"https://raw.githubusercontent.com/${GITHUB_REPOSITORY-}/update/${upj}" \
			"$base_template"

		local module_output="${app_name_l}-${rv_brand_f}-module-v${version_f}-${arch_f}.zip"
		pr "Packing module ${table}"
		cp -f "$patched_apk" "${base_template}/base.apk"

		if [ "${args[include_stock]}" != "disable" ]; then
			mkdir -p "${base_template}/stock/"
			if [ "${args[include_stock]}" = "merged" ]; then
				cp -f "$stock_apk" "${base_template}/stock/base.apk"
			elif [ "${args[include_stock]}" = "split" ]; then
				if [ ! -f "${stock_apk%.apk}.apkm" ]; then
					epr "Cannot include as 'split' because stock apk of $table_name is not a bundle"
					return 0
				fi
				if [ "$arch" = "arm64-v8a" ]; then
					unzip -j "${stock_apk%.apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*x86.apk' -x '*armeabi_v7a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				elif [ "$arch" = "arm-v7a" ]; then
					unzip -j "${stock_apk%.apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*x86.apk' -x '*arm64_v8a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				elif [ "$arch" = "x86" ]; then
					unzip -j "${stock_apk%.apk}.apkm" '*.apk' -x '*x86_64.apk' -x '*arm64_v8a.apk' -x '*armeabi_v7a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				elif [ "$arch" = "x86_64" ]; then
					unzip -j "${stock_apk%.apk}.apkm" '*.apk' -x '*x86.apk' -x '*arm64_v8a.apk' -x '*armeabi_v7a.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				else
					unzip -j "${stock_apk%.apk}.apkm" '*.apk' -d "${base_template}/stock/" >/dev/null 2>&1
				fi
			fi
		fi

		pushd >/dev/null "$base_template" || abort "Module template dir not found"
		zip -"$COMPRESSION_LEVEL" -FSqr "${CWD}/${BUILD_DIR}/${module_output}" .
		popd >/dev/null || :
		pr "Built ${table} (root): '${BUILD_DIR}/${module_output}'"
		write_build_info "${table% (*}" "${arch_f}" ".zip" "${app_name_l}-${rv_brand_f}" "$version_f" "$patches_ref" "$changelog_url"
	done
}

list_args() { tr -d '\t\r' <<<"$1" | tr -s ' ' | sed "s/' '/'\\n'/g" | sed 's/" "/"\n"/g' | sed 's/\([^"]\)"\([^"]\)/\1'\''\2/g' | grep -v '^$' || :; }
join_args() { list_args "$1" | sed "s/^/${2} /" | paste -sd " " - || :; }

module_config() {
	local ma=""
	if [ "$4" = "arm64-v8a" ]; then
		ma="arm64"
	elif [ "$4" = "arm-v7a" ]; then
		ma="arm"
	fi
	echo "PKG_NAME=$2
PKG_VER=$3
MODULE_ARCH=$ma" >"$1/config"
}
module_prop() {
	echo "id=${1}
name=${2}
version=v${3}
versionCode=${NEXT_VER_CODE}
author=j-hc
description=${4}" >"${6}/module.prop"

	if [ "$ENABLE_MODULE_UPDATE" = true ]; then echo "updateJson=${5}" >>"${6}/module.prop"; fi
}
