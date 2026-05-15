#!/usr/bin/env bash
set -euo pipefail

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/noxflow"
cache_file="${cache_dir}/status-updates.json"
timeout_secs="${NOXFLOW_UPDATE_STATUS_TIMEOUT:-8}"
count=0

cached_or_unknown() {
  if [[ -s "$cache_file" ]]; then
    cat "$cache_file"
  else
    printf '{"count":0,"text":"?","tooltip":"Update status unavailable"}\n'
  fi
}

count_lines_with_timeout() {
  local command_name="$1"
  shift

  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf '0\n'
    return 0
  fi

  timeout "$timeout_secs" "$command_name" "$@" 2>/dev/null | wc -l | tr -d ' '
}

if command -v checkupdates >/dev/null 2>&1; then
  pac_count="$(count_lines_with_timeout checkupdates || true)"
  [[ "$pac_count" =~ ^[0-9]+$ ]] || pac_count=0
  count=$((count + pac_count))
fi

if command -v paru >/dev/null 2>&1; then
  aur_count="$(count_lines_with_timeout paru -Qua || true)"
  [[ "$aur_count" =~ ^[0-9]+$ ]] || aur_count=0
  count=$((count + aur_count))
elif command -v yay >/dev/null 2>&1; then
  aur_count="$(count_lines_with_timeout yay -Qua || true)"
  [[ "$aur_count" =~ ^[0-9]+$ ]] || aur_count=0
  count=$((count + aur_count))
fi

if [[ "${pac_count:-0}" = 0 && "${aur_count:-0}" = 0 ]]; then
  if ! command -v checkupdates >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1 && ! command -v yay >/dev/null 2>&1; then
    cached_or_unknown
    exit 0
  fi
fi

if (( count > 0 )); then
  text="$count"
  tooltip="$count updates available"
else
  text="0"
  tooltip="System up to date"
fi

mkdir -p "$cache_dir"
payload="$(printf '{"count":%d,"text":"%s","tooltip":"%s"}\n' "$count" "$text" "$tooltip")"
printf '%s\n' "$payload" >"$cache_file"
printf '%s\n' "$payload"
