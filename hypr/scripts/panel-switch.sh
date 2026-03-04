#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Panel "$1" "${2:-}"
}

start_waybar() {
  pkill -x hyprpanel >/dev/null 2>&1 || true
  pkill -x ags >/dev/null 2>&1 || true
  if ! pgrep -x waybar >/dev/null 2>&1; then
    waybar >/dev/null 2>&1 &
  fi
  notify "Panel mode" "Waybar"
}

start_hyprpanel() {
  if ! command -v hyprpanel >/dev/null 2>&1; then
    notify "HyprPanel not installed" "Run: yay -S hyprpanel"
    exit 1
  fi
  pkill -x waybar >/dev/null 2>&1 || true
  if ! pgrep -x hyprpanel >/dev/null 2>&1; then
    hyprpanel >/dev/null 2>&1 &
  fi
  notify "Panel mode" "HyprPanel"
}

case "$mode" in
  waybar) start_waybar ;;
  hyprpanel) start_hyprpanel ;;
  toggle)
    if pgrep -x hyprpanel >/dev/null 2>&1; then
      start_waybar
    else
      start_hyprpanel
    fi
    ;;
  *)
    echo "usage: $0 [toggle|waybar|hyprpanel]" >&2
    exit 1
    ;;
esac
