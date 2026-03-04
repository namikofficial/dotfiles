#!/usr/bin/env sh
set -eu

interval="${WALLPAPER_ROTATE_INTERVAL:-1800}"
if [ -n "${1:-}" ]; then
  interval="$1"
fi

case "$interval" in
  ''|*[!0-9]*)
    interval=1800
    ;;
esac

if [ "$interval" -lt 60 ]; then
  interval=60
fi

while :; do
  sleep "$interval"
  "$HOME/.config/hypr/scripts/set-wallpaper.sh" --next >/dev/null 2>&1 || true
done
