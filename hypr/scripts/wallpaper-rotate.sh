#!/usr/bin/env sh
set -eu

mode="${WALLPAPER_ROTATE_MODE:-daily}"
check_interval="${WALLPAPER_ROTATE_CHECK_INTERVAL:-600}"
state_file="${WALLPAPER_ROTATE_STATE_FILE:-$HOME/.cache/hypr/wallpaper-last-rotate-date}"
mkdir -p "$(dirname "$state_file")"

if [ -n "${1:-}" ]; then
  mode="$1"
fi

sanitize_interval() {
  val="$1"
  fallback="$2"
  case "$val" in
    ''|*[!0-9]*)
      printf '%s\n' "$fallback"
      return 0
      ;;
  esac
  printf '%s\n' "$val"
}

rotate_next() {
  "$HOME/.config/hypr/scripts/set-wallpaper.sh" --next >/dev/null 2>&1 || true
}

run_daily_mode() {
  check_interval="$(sanitize_interval "$check_interval" 600)"
  if [ "$check_interval" -lt 60 ]; then
    check_interval=60
  fi

  while :; do
    today="$(date +%F)"
    last=""
    if [ -f "$state_file" ]; then
      last="$(cat "$state_file" 2>/dev/null || true)"
    fi

    if [ -z "$last" ]; then
      # First run: initialize state without forcing an immediate rotation.
      printf '%s\n' "$today" > "$state_file"
    elif [ "$last" != "$today" ]; then
      rotate_next
      printf '%s\n' "$today" > "$state_file"
    fi

    sleep "$check_interval"
  done
}

run_interval_mode() {
  interval="${WALLPAPER_ROTATE_INTERVAL:-1800}"
  interval="$(sanitize_interval "$interval" 1800)"
  if [ "$interval" -lt 60 ]; then
    interval=60
  fi

  while :; do
    sleep "$interval"
    rotate_next
  done
}

case "$mode" in
  daily)
    run_daily_mode
    ;;
  interval)
    run_interval_mode
    ;;
  *)
    # Backward-compatible: numeric arg means interval mode seconds.
    interval="$(sanitize_interval "$mode" 1800)"
    if [ "$interval" -lt 60 ]; then
      interval=60
    fi
    while :; do
      sleep "$interval"
      rotate_next
    done
    ;;
esac
