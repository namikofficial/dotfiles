#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
state_file="${state_dir}/layout-mode"
mkdir -p "$state_dir"

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

set_workspace_opt() {
  opt="$1"
  hyprctl dispatch workspaceopt "$opt" >/dev/null 2>&1 || true
}

remember_mode() {
  printf '%s\n' "$1" >"$state_file"
}

last_mode() {
  if [ -f "$state_file" ]; then
    mode_saved="$(cat "$state_file" 2>/dev/null || true)"
    case "$mode_saved" in
      dwindle|master|allfloat|allpseudo)
        printf '%s\n' "$mode_saved"
        return 0
        ;;
    esac
  fi
  printf '%s\n' "$(active_layout)"
}

case "$mode" in
  toggle)
    if [ "$(active_layout)" = "master" ]; then
      set_layout dwindle
      remember_mode dwindle
      notify "Switched to Dwindle"
    else
      set_layout master
      remember_mode master
      notify "Switched to Master"
    fi
    ;;
  master)
    set_layout master
    remember_mode master
    notify "Switched to Master"
    ;;
  dwindle)
    set_layout dwindle
    remember_mode dwindle
    notify "Switched to Dwindle"
    ;;
  allfloat)
    set_workspace_opt allfloat
    remember_mode allfloat
    notify "Toggled workspace floating grid"
    ;;
  allpseudo)
    set_workspace_opt allpseudo
    remember_mode allpseudo
    notify "Toggled workspace pseudotile mode"
    ;;
  cycle)
    case "$(last_mode)" in
      dwindle)
        set_layout master
        remember_mode master
        notify "Cycle layout: Master"
        ;;
      master)
        set_workspace_opt allfloat
        remember_mode allfloat
        notify "Cycle layout: Floating grid"
        ;;
      allfloat)
        set_workspace_opt allpseudo
        remember_mode allpseudo
        notify "Cycle layout: Pseudotile grid"
        ;;
      *)
        set_layout dwindle
        remember_mode dwindle
        notify "Cycle layout: Dwindle"
        ;;
    esac
    ;;
  *)
    echo "usage: $0 [toggle|master|dwindle|allfloat|allpseudo|cycle]" >&2
    exit 1
    ;;
esac
