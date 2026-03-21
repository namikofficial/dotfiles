#!/usr/bin/env sh
set -eu

emit_json() {
  text="$1"
  tooltip="$2"
  class="$3"
  jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" '{text:$text, tooltip:$tooltip, class:$class}'
}

if ! command -v playerctl >/dev/null 2>&1; then
  emit_json "" "" "hidden"
  exit 0
fi

status="$(playerctl status 2>/dev/null || true)"
if [ -z "$status" ] || [ "$status" = "Stopped" ]; then
  emit_json "" "" "hidden"
  exit 0
fi

artist="$(playerctl metadata artist 2>/dev/null || true)"
title="$(playerctl metadata title 2>/dev/null || true)"

if [ -z "$title" ]; then
  emit_json "" "" "hidden"
  exit 0
fi

short_title="$(printf '%s' "$title" | cut -c1-20)"
[ "${#title}" -gt 20 ] && short_title="${short_title}..."

if [ -n "$artist" ]; then
  short="${artist} - ${short_title}"
else
  short="$short_title"
fi

short="$(printf '%s' "$short" | cut -c1-28)"
full_tooltip="$(printf '%s\n%s\n%s' "$status" "${artist:+$artist - }$title" "Click: play/pause")"
emit_json "󰎈 $short" "$full_tooltip" "media-active"
