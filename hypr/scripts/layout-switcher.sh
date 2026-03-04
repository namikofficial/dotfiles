#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland "Layout" "$1"
}

active_layout() {
  if command -v jq >/dev/null 2>&1; then
    hyprctl -j activeworkspace 2>/dev/null | jq -r '.tiledLayout // "dwindle"' 2>/dev/null || printf 'dwindle'
  else
    printf 'dwindle'
  fi
}

set_layout() {
  layout="$1"
  hyprctl keyword general:layout "$layout" >/dev/null 2>&1 || true
}

case "$mode" in
  toggle)
    if [ "$(active_layout)" = "master" ]; then
      set_layout dwindle
      notify "Switched to Dwindle"
    else
      set_layout master
      notify "Switched to Master"
    fi
    ;;
  master)
    set_layout master
    notify "Switched to Master"
    ;;
  dwindle)
    set_layout dwindle
    notify "Switched to Dwindle"
    ;;
  allfloat)
    hyprctl dispatch workspaceopt allfloat >/dev/null 2>&1 || true
    notify "Toggled workspace floating grid"
    ;;
  *)
    echo "usage: $0 [toggle|master|dwindle|allfloat]" >&2
    exit 1
    ;;
esac
