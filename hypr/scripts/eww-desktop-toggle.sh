#!/usr/bin/env sh
set -eu

cfg="$HOME/.config/eww"
window_name="desktoppanel"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Widgets "$1" "${2:-}"
}

if ! command -v eww >/dev/null 2>&1; then
  notify "eww is not installed" "Install with: yay -S eww"
  exit 1
fi

if [ ! -f "$cfg/eww.yuck" ]; then
  notify "eww config missing" "$cfg/eww.yuck not found"
  exit 1
fi

if ! eww --config "$cfg" ping >/dev/null 2>&1; then
  eww --config "$cfg" daemon >/dev/null 2>&1 &
  sleep 1
fi

if eww --config "$cfg" active-windows 2>/dev/null | grep -q "^${window_name}"; then
  eww --config "$cfg" close "$window_name"
  notify "Desktop widgets hidden"
else
  eww --config "$cfg" open "$window_name"
  notify "Desktop widgets shown" "They render above wallpaper and below app windows."
fi
