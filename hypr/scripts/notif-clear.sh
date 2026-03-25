#!/usr/bin/env bash
set -euo pipefail

dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif"
state_file="$dir/state.json"
events_file="$dir/events.jsonl"

mkdir -p "$dir"
: > "$events_file"

if command -v jq >/dev/null 2>&1 && [ -s "$state_file" ] && jq . "$state_file" >/dev/null 2>&1; then
  tmp="$(mktemp)"
  jq '.events=[] | .selected_index=0 | .selected_id="" | .last_id="" | .updated_at=(now|todateiso8601)' "$state_file" > "$tmp"
  mv "$tmp" "$state_file"
else
  cat > "$state_file" <<JSON
{"mode":"custom","dnd":false,"last_id":"","updated_at":"","selected_index":0,"selected_id":"","events":[]}
JSON
fi
