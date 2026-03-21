#!/usr/bin/env sh
set -eu

if ! command -v tlp-stat >/dev/null 2>&1; then
  jq -cn --arg text "TLP ?" --arg tooltip "tlp-stat not found" '{text:$text, tooltip:$tooltip}'
  exit 0
fi

status="$(tlp-stat -s 2>/dev/null || true)"
if [ -z "$status" ]; then
  jq -cn --arg text "TLP ?" --arg tooltip "TLP status unavailable" '{text:$text, tooltip:$tooltip}'
  exit 0
fi

profile="$(printf '%s\n' "$status" | awk -F'= ' '/Power profile/ {print $2; exit}')"
source="$(printf '%s\n' "$status" | awk -F'= ' '/Power source/ {print $2; exit}')"

if [ -z "$profile" ]; then
  profile="unknown"
fi
if [ -z "$source" ]; then
  source="unknown"
fi

case "$source" in
  AC) tag="AC" ;;
  battery|BAT) tag="BAT" ;;
  *) tag="$source" ;;
esac

text="TLP ${tag}"
tooltip="$(printf 'Power source: %s\nProfile: %s\n\nClick: open tlp-stat' "$source" "$profile")"
jq -cn --arg text "$text" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip}'
