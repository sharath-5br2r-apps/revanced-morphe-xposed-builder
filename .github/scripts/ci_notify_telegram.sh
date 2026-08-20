#!/bin/bash
set -euo pipefail

[ -f tags_old.json ] && TAGS_OLD=$(cat tags_old.json) || TAGS_OLD='{}'
[ -f tags_new.json ] && TAGS_NEW=$(cat tags_new.json) || TAGS_NEW='{}'

PATCH_SOURCES_JSON=$(cat configs/patch_sources.json || echo '{}')
MSG_BODY=$(jq -rn --argjson new "$TAGS_NEW" --argjson old "$TAGS_OLD" --argjson patches "$PATCH_SOURCES_JSON" '
  [ $new | to_entries[] | . as $e
    | ($old[$e.key] // {}) as $o
    | select(($e.value.stable != "" and $e.value.stable != ($o.stable // "")) or ($e.value.prerelease != "" and $e.value.prerelease != ($o.prerelease // "")) or ($e.value.blocked == true and $o.blocked != true))
    | ($patches[$e.key].host // "github") as $host
    | ($patches[$e.key].host_instance // (if $host == "gitlab" then "https://gitlab.com" elif $host == "codeberg" then "https://codeberg.org" else "https://github.com" end)) as $inst_raw
    | (if ($inst_raw | startswith("http://") or startswith("https://")) then $inst_raw else ("https://" + $inst_raw) end) as $host_base
    | ($host_base + (if ($host_base | endswith("/")) then "" else "/" end)) as $base
    | "📦 [\($e.value.repo)](\($base)\($e.value.repo))" +
      (if ($e.value.blocked == true and $o.blocked != true) then "\n  ╰ 🚫 Repository access blocked." else "" end) +
      (if ($e.value.blocked != true and $e.value.stable != "" and $e.value.stable != ($o.stable // "")) then
        (if $host == "gitlab" then "\n  ╰ Stable: [\($e.value.stable)](\($base)\($e.value.repo)/-/releases/\($e.value.stable))" else "\n  ╰ Stable: [\($e.value.stable)](\($base)\($e.value.repo)/releases/tag/\($e.value.stable))" end)
      else "" end) +
      (if ($e.value.blocked != true and $e.value.prerelease != "" and $e.value.prerelease != ($o.prerelease // "")) then
        (if $host == "gitlab" then "\n  ╰ Pre-release: [\($e.value.prerelease)](\($base)\($e.value.repo)/-/releases/\($e.value.prerelease))" else "\n  ╰ Pre-release: [\($e.value.prerelease)](\($base)\($e.value.repo)/releases/tag/\($e.value.prerelease))" end)
      else "" end)
  ] | join("\n\n")
')

APP_UPDATES_JSON=$(cat app_updates.json 2>/dev/null || echo '{}')
APP_UPDATES_MSG=$(jq -r --argjson updates "$APP_UPDATES_JSON" '
  [ $updates | to_entries[] | . as $e | "📱 \($e.key)\n  ╰ Version: \($e.value.new)" ] | join("\n\n")
' <<<"{}")

if [ -z "$MSG_BODY" ] && [ -z "$APP_UPDATES_MSG" ]; then
  echo "::notice::No actual updates to format for Telegram."
  exit 0
fi

NL=$'\n'
FULL_MSG=""

if [ -n "$MSG_BODY" ]; then
  if [ "${TRIGGER_STABLE:-0}" = "1" ] || [ "${TRIGGER_PRERELEASE:-0}" = "1" ]; then
    FULL_MSG="*🚨 New Patch(es) Detected!*${NL}${NL}${MSG_BODY}"
  else
    FULL_MSG="*⚠️ Repository Status Update!*${NL}${NL}${MSG_BODY}"
  fi
fi

if [ -n "$APP_UPDATES_MSG" ]; then
  if [ -n "$FULL_MSG" ]; then
    FULL_MSG="${FULL_MSG}${NL}${NL}"
  fi
  FULL_MSG="${FULL_MSG}*🚨 New Version(s) Detected!*${NL}${NL}${APP_UPDATES_MSG}"
fi

if [ "${EFFECTIVE_STABLE:-0}" = "1" ] || [ "${EFFECTIVE_PRERELEASE:-0}" = "1" ]; then
  if [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
    ACTION_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    FULL_MSG="${FULL_MSG}${NL}${NL}⚙️ [View Build in Action](${ACTION_URL})"
  fi
else
  FULL_MSG="${FULL_MSG}${NL}${NL}ℹ️ _No apps are enabled. Build skipped._"
fi

curl -s -X POST \
  --data-urlencode "parse_mode=Markdown" \
  --data-urlencode "disable_web_page_preview=true" \
  --data-urlencode "text=${FULL_MSG}" \
  --data-urlencode "chat_id=@rvb27" \
  --data-urlencode "message_thread_id=2747" \
  "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" > /dev/null
