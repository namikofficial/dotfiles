#!/usr/bin/env bash
set -euo pipefail

state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"

command -v jq >/dev/null 2>&1 || exit 0
[ -s "$state_file" ] || exit 0

payload="$(jq -r '.events[(.selected_index // 0)].copiable_payload // empty' "$state_file")"
if [ -z "$payload" ]; then
  payload="$(jq -r '
    if (.events|length)>0 then
      (.events[(.selected_index // 0)] | "[" + .severity + "] " + .title + "\n" + (.body // "") + "\nID: " + .id)
    else "" end
  ' "$state_file")"
fi

[ -n "$payload" ] || exit 0

if command -v wl-copy >/dev/null 2>&1; then
  printf '%s\n' "$payload" | wl-copy
fi

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a Noxflow "Notification copied" "Latest notification copied to clipboard."
fi
