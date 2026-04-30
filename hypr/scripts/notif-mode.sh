#!/usr/bin/env bash
set -euo pipefail

mode="${1:-swaync}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"

mkdir -p "$(dirname "$state_file")"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

if [ ! -s "$state_file" ] || ! jq . "$state_file" >/dev/null 2>&1; then
  printf '{"mode":"swaync","dnd":false,"last_id":"","updated_at":"","selected_index":0,"selected_id":"","events":[]}' > "$state_file"
fi

[ "$mode" = "toggle" ] && mode="swaync"

case "$mode" in
  swaync)
    if command -v swaync >/dev/null 2>&1 && ! pgrep -x swaync >/dev/null 2>&1; then
      swaync >/dev/null 2>&1 &
    fi
    ;;
  *)
    echo "usage: $0 [swaync|toggle]" >&2
    exit 1
    ;;
esac

tmp="$(mktemp)"
jq --arg mode "$mode" '.mode=$mode | .updated_at=(now|todateiso8601)' "$state_file" > "$tmp"
mv "$tmp" "$state_file"
