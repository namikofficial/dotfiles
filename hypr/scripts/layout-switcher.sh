#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
state_file="${state_dir}/layout-mode"
log_helper="$HOME/.config/hypr/scripts/lib/log.sh"
mkdir -p "$state_dir"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Hyprland "$1" "${2:-}"
}

emit_event() {
  [ -x "$log_helper" ] || return 0
  "$log_helper" --emit "$1" layout "${2:-Layout}" "${3:-}" >/dev/null 2>&1 || true
}

active_layout() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  hyprctl -j activeworkspace 2>/dev/null | jq -r '.tiledLayout // empty' 2>/dev/null
}

set_layout() {
  layout="$1"
  hyprctl keyword general:layout "$layout" >/dev/null 2>&1
}

set_workspace_opt() {
  opt="$1"
  hyprctl dispatch workspaceopt "$opt" >/dev/null 2>&1
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
  layout_now="$(active_layout 2>/dev/null || true)"
  case "$layout_now" in
    dwindle|master|allfloat|allpseudo)
      printf '%s\n' "$layout_now"
      ;;
    *)
      printf '%s\n' "dwindle"
      ;;
  esac
}

apply_layout() {
  target="$1"
  label="$2"
  if set_layout "$target"; then
    remember_mode "$target"
    emit_event info "Layout switched" "$label"
    notify "Layout" "$label"
    return 0
  fi

  emit_event error "Layout switch failed" "Could not switch to $label"
  notify "Layout switch failed" "Could not switch to $label"
  return 1
}

apply_workspace_opt() {
  opt="$1"
  label="$2"
  if set_workspace_opt "$opt"; then
    remember_mode "$opt"
    emit_event info "Layout toggled" "$label"
    notify "Layout" "$label"
    return 0
  fi

  emit_event error "Layout toggle failed" "Could not toggle $label"
  notify "Layout toggle failed" "Could not toggle $label"
  return 1
}

case "$mode" in
  toggle)
    current_layout="$(active_layout 2>/dev/null || last_mode)"
    if [ "$current_layout" = "master" ]; then
      apply_layout dwindle "Switched to Dwindle"
    else
      apply_layout master "Switched to Master"
    fi
    ;;
  master)
    apply_layout master "Switched to Master"
    ;;
  dwindle)
    apply_layout dwindle "Switched to Dwindle"
    ;;
  allfloat)
    apply_workspace_opt allfloat "Toggled workspace floating grid"
    ;;
  allpseudo)
    apply_workspace_opt allpseudo "Toggled workspace pseudotile mode"
    ;;
  cycle)
    case "$(last_mode)" in
      dwindle)
        apply_layout master "Cycle layout: Master"
        ;;
      master)
        apply_workspace_opt allfloat "Cycle layout: Floating grid"
        ;;
      allfloat)
        apply_workspace_opt allpseudo "Cycle layout: Pseudotile grid"
        ;;
      *)
        apply_layout dwindle "Cycle layout: Dwindle"
        ;;
    esac
    ;;
  *)
    echo "usage: $0 [toggle|master|dwindle|allfloat|allpseudo|cycle]" >&2
    exit 1
    ;;
esac
