#!/usr/bin/env sh
set -eu

cfg="$HOME/.config/eww"
err_file="${XDG_RUNTIME_DIR:-/tmp}/eww-desktop-toggle.err"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Widgets "$1" "${2:-}"
}

run_eww() {
  tries=0
  while [ "$tries" -lt 5 ]; do
    if eww --config "$cfg" "$@" >/dev/null 2>"$err_file"; then
      return 0
    fi
    if grep -qi "Resource temporarily unavailable" "$err_file" 2>/dev/null; then
      tries=$((tries + 1))
      sleep 0.2
      continue
    fi
    return 1
  done
  return 1
}

ensure_eww() {
  if ! run_eww ping; then
    eww --config "$cfg" daemon >/dev/null 2>&1 &
    sleep 1
  fi

  if ! run_eww ping; then
    notify "Eww daemon unavailable" "Unable to start desktop widgets."
    exit 1
  fi

  if ! run_eww reload; then
    first_line="$(sed -n '1p' "$err_file" 2>/dev/null || true)"
    [ -n "$first_line" ] || first_line="Check ~/.config/eww/eww.scss and eww.yuck"
    notify "Eww config error" "$first_line"
    exit 1
  fi
}

if ! command -v eww >/dev/null 2>&1; then
  notify "eww is not installed" "Install with: yay -S eww"
  exit 1
fi

if [ ! -f "$cfg/eww.yuck" ]; then
  notify "eww config missing" "$cfg/eww.yuck not found"
  exit 1
fi

ensure_eww
run_eww open-many --toggle "desktoppanel:desktop-left" "desktoppanel_right:desktop-right"
notify "Desktop widgets toggled"
