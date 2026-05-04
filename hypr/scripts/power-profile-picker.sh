#!/usr/bin/env bash
set -euo pipefail

theme="$HOME/.config/rofi/actions.rasi"

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  notify-send -a Power "powerprofilesctl missing" "Install power-profiles-daemon"
  exit 1
fi

choices=$'performance\nbalanced\npower-saver'
selected="$(printf '%s\n' "$choices" | rofi -dmenu -i -p 'Power Profile' -theme "$theme" || true)"
[ -n "$selected" ] || exit 0

powerprofilesctl set "$selected"
notify-send -a Power "Power profile" "$selected"
