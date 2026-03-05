#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
special_ws="scratch_term"
class_name="noxflow-scratch-term"

launch_term() {
  if hyprctl clients 2>/dev/null | rg -q "class: ${class_name}"; then
    return 0
  fi

  kitty --class "$class_name" --title "Scratch Terminal" >/dev/null 2>&1 &
  sleep 0.12
}

case "$mode" in
  toggle)
    launch_term
    hyprctl dispatch togglespecialworkspace "$special_ws" >/dev/null 2>&1 || true
    ;;
  send)
    hyprctl dispatch movetoworkspacesilent "special:${special_ws}" >/dev/null 2>&1 || true
    hyprctl dispatch togglespecialworkspace "$special_ws" >/dev/null 2>&1 || true
    ;;
  stash)
    hyprctl dispatch movetoworkspacesilent "special:${special_ws}" >/dev/null 2>&1 || true
    ;;
  *)
    echo "usage: $0 [toggle|send|stash]" >&2
    exit 1
    ;;
esac
