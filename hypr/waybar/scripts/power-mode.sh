#!/usr/bin/env sh
set -eu

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  jq -cn --arg text "PWR off" --arg tooltip "Power profile control unavailable" '{text:$text, tooltip:$tooltip}'
  exit 0
fi

mode="$(powerprofilesctl get 2>/dev/null || true)"
if [ -z "$mode" ]; then
  jq -cn --arg text "PWR off" --arg tooltip "Power profile service is disabled" '{text:$text, tooltip:$tooltip}'
  exit 0
fi
case "$mode" in
  performance)
    text="PWR perf"
    label="Performance"
    ;;
  power-saver)
    text="PWR save"
    label="Power Saver"
    ;;
  balanced|*)
    text="PWR bal"
    label="Balanced"
    ;;
esac

tooltip="$(printf 'Power: %s\nClick: cycle profile' "$label")"
jq -cn --arg text "$text" --arg tooltip "$tooltip" '{text:$text, tooltip:$tooltip}'
