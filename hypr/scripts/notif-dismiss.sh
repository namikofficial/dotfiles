#!/usr/bin/env bash
set -euo pipefail

mode="${1:-selected}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"
events_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/events.jsonl"

command -v jq >/dev/null 2>&1 || exit 0
[ -s "$state_file" ] || exit 0
jq . "$state_file" >/dev/null 2>&1 || exit 0

if [ "$mode" != "selected" ]; then
  echo "usage: $0 [selected]" >&2
  exit 1
fi

tmp_state="$(mktemp)"

target_id="$(jq -r '.events[(.selected_index // 0)].id // empty' "$state_file")"
[ -n "$target_id" ] || exit 0

jq --arg id "$target_id" '
  .events = ((.events // []) | map(select(.id != $id)))
  | .selected_index = (if ((.events|length)==0) then 0 else ((.selected_index // 0) % (.events|length)) end)
  | .selected_id = ((.events[.selected_index].id) // "")
  | .updated_at = (now|todateiso8601)
' "$state_file" > "$tmp_state"
mv "$tmp_state" "$state_file"

if [ -f "$events_file" ]; then
  tmp_events="$(mktemp)"
  jq -c --arg id "$target_id" 'select(.id != $id)' "$events_file" > "$tmp_events" || true
  mv "$tmp_events" "$events_file"
fi
