#!/usr/bin/env bash
set -euo pipefail

action="${1:-next}"
arg="${2:-}"
state_file="${XDG_CACHE_HOME:-$HOME/.cache}/hypr/notif/state.json"

command -v jq >/dev/null 2>&1 || exit 0
[ -s "$state_file" ] || exit 0
jq . "$state_file" >/dev/null 2>&1 || exit 0

tmp="$(mktemp)"
case "$action" in
  index)
    idx="${arg:-0}"
    [[ "$idx" =~ ^[0-9]+$ ]] || exit 0
    jq --argjson idx "$idx" '
      .events = (.events // [])
      | .selected_index = (if ((.events|length) == 0) then 0 else (if $idx >= (.events|length) then ((.events|length)-1) else $idx end) end)
      | .selected_id = ((.events[.selected_index].id) // "")
      | .updated_at = (now|todateiso8601)
    ' "$state_file" > "$tmp"
    ;;
  next)
    jq '
      .events = (.events // [])
      | .selected_index =
          (if ((.events|length) == 0) then 0
           else (((.selected_index // 0) + 1) % (.events|length)) end)
      | .selected_id = ((.events[.selected_index].id) // "")
      | .updated_at = (now|todateiso8601)
    ' "$state_file" > "$tmp"
    ;;
  prev)
    jq '
      .events = (.events // [])
      | .selected_index =
          (if ((.events|length) == 0) then 0
           else (((.selected_index // 0) - 1 + (.events|length)) % (.events|length)) end)
      | .selected_id = ((.events[.selected_index].id) // "")
      | .updated_at = (now|todateiso8601)
    ' "$state_file" > "$tmp"
    ;;
  first)
    jq '.selected_index=0 | .selected_id=((.events[0].id)//"") | .updated_at=(now|todateiso8601)' "$state_file" > "$tmp"
    ;;
  *)
    rm -f "$tmp"
    echo "usage: $0 [next|prev|first]" >&2
    exit 1
    ;;
esac
mv "$tmp" "$state_file"
