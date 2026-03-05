#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
side_ws="sidepanel"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland "Side Panel" "$1"
}

case "$mode" in
  toggle)
    hyprctl dispatch togglespecialworkspace "$side_ws" >/dev/null 2>&1 || true
    ;;
  send)
    hyprctl dispatch movetoworkspacesilent "special:${side_ws}" >/dev/null 2>&1 || true
    hyprctl dispatch togglespecialworkspace "$side_ws" >/dev/null 2>&1 || true
    notify "Moved window to side panel and opened it"
    ;;
  stash)
    hyprctl dispatch movetoworkspacesilent "special:${side_ws}" >/dev/null 2>&1 || true
    notify "Moved window to side panel"
    ;;
  *)
    echo "usage: $0 [toggle|send|stash]" >&2
    exit 1
    ;;
esac
