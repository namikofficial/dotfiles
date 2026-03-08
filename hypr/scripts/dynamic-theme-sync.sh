#!/usr/bin/env sh
set -eu

mode="${1:-apply}"
night_from="${NOXFLOW_NIGHT_START_HOUR:-20}"
day_from="${NOXFLOW_DAY_START_HOUR:-7}"
night_temp="${HYPRSUNSET_NIGHT_TEMP:-4200}"
auto_night_light="${HYPRSUNSET_AUTO:-false}"
sync_script="$HOME/.config/hypr/scripts/theme-sync.sh"
wall_cache="$HOME/.cache/current-wallpaper"

is_night_now() {
  hour="$(date +%H)"
  if [ "$hour" -ge "$night_from" ] || [ "$hour" -lt "$day_from" ]; then
    return 0
  fi
  return 1
}

sync_accent() {
  if [ -x "$sync_script" ] && [ -f "$wall_cache" ]; then
    wall="$(cat "$wall_cache" 2>/dev/null || true)"
    [ -n "$wall" ] && "$sync_script" "$wall" >/dev/null 2>&1 || true
  fi
}

apply_once() {
  sync_accent
  case "$auto_night_light" in
    1|true|yes|on)
      ;;
    *)
      return 0
      ;;
  esac
  if is_night_now; then
    if ! pgrep -x hyprsunset >/dev/null 2>&1; then
      hyprsunset -t "$night_temp" >/dev/null 2>&1 &
    fi
  else
    pkill -x hyprsunset >/dev/null 2>&1 || true
  fi
}

case "$mode" in
  apply)
    apply_once
    ;;
  watch)
    while true; do
      apply_once
      sleep 1800
    done
    ;;
  *)
    echo "usage: $0 [apply|watch]" >&2
    exit 1
    ;;
esac
