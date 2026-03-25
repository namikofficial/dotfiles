#!/usr/bin/env bash
set -euo pipefail

mode="${1:-count}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"

if ! command -v jq >/dev/null 2>&1 || [ ! -s "$state_file" ] || ! jq . "$state_file" >/dev/null 2>&1; then
  case "$mode" in
    count) echo 0 ;;
    dnd) echo OFF ;;
    *) echo "n/a" ;;
  esac
  exit 0
fi

case "$mode" in
  count) jq -r '(.events // []) | length' "$state_file" ;;
  dnd) jq -r 'if (.dnd // false) then "ON" else "OFF" end' "$state_file" ;;
  mode) jq -r '.mode // "custom"' "$state_file" ;;
  severity) jq -r '.events[(.selected_index // 0)].severity // "info"' "$state_file" ;;
  title) jq -r '.events[(.selected_index // 0)].title // "No notifications"' "$state_file" ;;
  body) jq -r '.events[(.selected_index // 0)].body // "All clear."' "$state_file" ;;
  time) jq -r '.events[(.selected_index // 0)].time // ""' "$state_file" ;;
  recent)
    jq -r '(.events // [])[:12] | if length==0 then "No events" else .[] | "[" + .severity + "] " + .title end' "$state_file"
    ;;
  *) echo "n/a" ;;
esac
