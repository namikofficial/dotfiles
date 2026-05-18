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

active_fullscreen_state() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  hyprctl -j activewindow 2>/dev/null | jq -r '.fullscreen // 0' 2>/dev/null
}

active_is_floating() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  hyprctl -j activewindow 2>/dev/null | jq -r '.floating // false' 2>/dev/null
}

hypr_eval() {
  output="$(hyprctl eval "$1" 2>&1)" || {
    printf '%s\n' "$output" >&2
    return 1
  }
  [ "$output" = "ok" ] || {
    printf '%s\n' "$output" >&2
    return 1
  }
}

set_layout() {
  layout="$1"
  hypr_eval "hl.config({ general = { layout = \"$layout\" } })"
}

set_monocle() {
  set_layout master || return 1
  hypr_eval 'hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set" }))'
}

unset_monocle_if_active() {
  [ "$(cat "$state_file" 2>/dev/null || true)" = "monocle" ] || return 0
  hypr_eval 'hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))' || true
}

toggle_current_float() {
  hypr_eval 'hl.dispatch(hl.dsp.window.float({ state = "toggle" }))'
}

toggle_current_pseudo() {
  hypr_eval 'hl.dispatch(hl.dsp.window.pseudo())'
}

remember_mode() {
  printf '%s\n' "$1" >"$state_file"
}

last_mode() {
  if [ -f "$state_file" ]; then
    mode_saved="$(cat "$state_file" 2>/dev/null || true)"
    case "$mode_saved" in
      dwindle|master|monocle|floating|pseudo)
        printf '%s\n' "$mode_saved"
        return 0
        ;;
    esac
  fi
  layout_now="$(active_layout 2>/dev/null || true)"
  case "$layout_now" in
    dwindle|master)
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
  unset_monocle_if_active
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

apply_monocle() {
  label="$1"
  if set_monocle; then
    remember_mode monocle
    emit_event info "Layout switched" "$label"
    notify "Layout" "$label"
    return 0
  fi

  emit_event error "Layout switch failed" "Could not switch to $label"
  notify "Layout switch failed" "Could not switch to $label"
  return 1
}

apply_current_window_mode() {
  target="$1"
  label="$2"
  if case "$target" in
    floating) toggle_current_float ;;
    pseudo) toggle_current_pseudo ;;
    *) false ;;
  esac; then
    remember_mode "$target"
    emit_event info "Layout toggled" "$label"
    notify "Layout" "$label"
    return 0
  fi

  emit_event error "Layout toggle failed" "Could not toggle $label"
  notify "Layout toggle failed" "Could not toggle $label"
  return 1
}

status_text() {
  saved="$(cat "$state_file" 2>/dev/null || true)"
  if [ "$saved" = "monocle" ] && [ "$(active_fullscreen_state 2>/dev/null || printf '0')" = "1" ]; then
    printf '%s\n' "monocle"
    return 0
  fi
  if [ "$saved" = "floating" ] && [ "$(active_is_floating 2>/dev/null || printf 'false')" = "true" ]; then
    printf '%s\n' "floating"
    return 0
  fi

  layout_now="$(active_layout 2>/dev/null || true)"
  case "$layout_now" in
    dwindle|master)
      printf '%s\n' "$layout_now"
      ;;
    *)
      printf '%s\n' "dwindle"
      ;;
  esac
}

status_json() {
  mode_now="$(status_text)"
  case "$mode_now" in
    dwindle) label="Dwindle" ;;
    master) label="Master" ;;
    monocle) label="Monocle" ;;
    floating) label="Floating" ;;
    pseudo) label="Pseudo" ;;
    *) label="$mode_now" ;;
  esac
  jq -n --arg text "$label" --arg class "$mode_now" '{text: $text, class: $class}'
}

case "$mode" in
  status)
    status_json
    ;;
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
  scroll)
    notify "Layout unavailable" "Scroll needs a Hyprland layout plugin; using Master"
    apply_layout master "Switched to Master"
    ;;
  monocle)
    apply_monocle "Switched to Monocle"
    ;;
  dwindle)
    apply_layout dwindle "Switched to Dwindle"
    ;;
  allfloat)
    apply_current_window_mode floating "Toggled focused window floating"
    ;;
  allpseudo)
    apply_current_window_mode pseudo "Toggled focused window pseudotile"
    ;;
  cycle)
    case "$(last_mode)" in
      dwindle)
        apply_layout master "Cycle layout: Master"
        ;;
      master)
        apply_monocle "Cycle layout: Monocle"
        ;;
      monocle)
        apply_layout dwindle "Cycle layout: Dwindle"
        ;;
      *)
        apply_layout dwindle "Cycle layout: Dwindle"
        ;;
    esac
    ;;
  *)
    echo "usage: $0 [status|toggle|master|dwindle|scroll|monocle|allfloat|allpseudo|cycle]" >&2
    exit 1
    ;;
esac
