#!/usr/bin/env sh
set -eu

cfg="$HOME/.config/eww"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Eww "$1" "${2:-}"
}

if ! command -v eww >/dev/null 2>&1; then
  notify "eww is not installed" "Install it with: yay -S eww"
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

if eww --config "$cfg" active-windows 2>/dev/null | grep -q '^quickpanel'; then
  eww --config "$cfg" close quickpanel
else
  eww --config "$cfg" open quickpanel
fi
