#!/usr/bin/env sh
set -eu

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Network Applet" "$1" "${2:-}"
}

if ! command -v nm-applet >/dev/null 2>&1; then
  notify "nm-applet missing" "Install network-manager-applet"
  exit 1
fi

if pgrep -x nm-applet >/dev/null 2>&1; then
  pkill -x nm-applet
  notify "Stopped" "nm-applet"
  exit 0
fi

nm-applet >/dev/null 2>&1 &
notify "Started" "nm-applet"
