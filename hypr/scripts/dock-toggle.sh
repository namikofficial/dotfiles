#!/usr/bin/env sh
set -eu

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Dock "$1" "${2:-}"
}

if ! command -v nwg-dock-hyprland >/dev/null 2>&1; then
  notify "Dock not installed" "Install package: nwg-dock-hyprland"
  exit 1
fi

if pgrep -x nwg-dock-hyprland >/dev/null 2>&1; then
  pkill -x nwg-dock-hyprland
  exit 0
fi

nwg-dock-hyprland >/dev/null 2>&1 &
