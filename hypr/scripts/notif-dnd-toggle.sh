#!/usr/bin/env bash
set -euo pipefail

state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"
mkdir -p "$(dirname "$state_file")"

if command -v swaync-client >/dev/null 2>&1; then
  state="$(swaync-client -sw -d 2>/dev/null || echo false)"
  if command -v notify-send >/dev/null 2>&1; then
    case "$state" in
      true|1|on|enabled) notify-send -a Noxflow "Notifications" "DND enabled" ;;
      *) notify-send -a Noxflow "Notifications" "DND disabled" ;;
    esac
  fi
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if [ ! -s "$state_file" ] || ! jq . "$state_file" >/dev/null 2>&1; then
  printf '{"mode":"custom","dnd":false,"last_id":"","updated_at":"","selected_index":0,"selected_id":"","events":[]}' > "$state_file"
fi

tmp="$(mktemp)"
jq '.dnd = (if (.dnd // false) then false else true end) | .updated_at=(now|todateiso8601)' "$state_file" > "$tmp"
mv "$tmp" "$state_file"

if command -v notify-send >/dev/null 2>&1; then
  state="$(jq -r '.dnd' "$state_file")"
  [ "$state" = "true" ] && notify-send -a Noxflow "Notifications" "DND enabled" || notify-send -a Noxflow "Notifications" "DND disabled"
fi
