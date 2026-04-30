#!/usr/bin/env bash
set -euo pipefail

mode="${1:-toggle}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
engine_file="${state_dir}/panel.engine"
waybar_restart="$HOME/.config/hypr/scripts/restart-waybar.sh"

mkdir -p "$state_dir"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Panel "$1" "${2:-}"
}

write_engine() {
  printf '%s\n' "$1" >"$engine_file"
}

read_engine() {
  if pgrep -x wayle >/dev/null 2>&1; then
    printf 'wayle\n'
    return 0
  fi

  if pgrep -x waybar >/dev/null 2>&1; then
    printf 'waybar\n'
    return 0
  fi

  if [ -f "$engine_file" ]; then
    saved="$(cat "$engine_file" 2>/dev/null || true)"
    case "$saved" in
      wayle|waybar)
        printf '%s\n' "$saved"
        return 0
        ;;
    esac
  fi

  printf 'wayle\n'
}

is_visible() {
  pgrep -x wayle >/dev/null 2>&1 || pgrep -x waybar >/dev/null 2>&1
}

start_waybar() {
  pkill -x wayle >/dev/null 2>&1 || true
  "$waybar_restart"
  write_engine waybar
  notify "Panel mode" "Waybar"
}

start_wayle() {
  pkill -x waybar >/dev/null 2>&1 || true
  if ! command -v wayle >/dev/null 2>&1; then
    write_engine wayle
    notify "Wayle unavailable" "Falling back to Waybar"
    start_waybar
    return 0
  fi
  if ! pgrep -x wayle >/dev/null 2>&1; then
    wayle >/dev/null 2>&1 &
  fi
  write_engine wayle
  notify "Panel mode" "Wayle"
}

hide_panel() {
  pkill -x wayle >/dev/null 2>&1 || true
  pkill -x waybar >/dev/null 2>&1 || true
  notify "Panel view" "Hidden"
}

show_panel() {
  engine="$(read_engine)"
  case "$engine" in
    wayle)
      start_wayle || start_waybar
      ;;
    waybar)
      start_waybar
      ;;
    *)
      start_wayle || start_waybar
      ;;
  esac
}

status_line() {
  engine="$(read_engine)"
  if is_visible; then
    printf '%s:visible\n' "$engine"
  else
    printf '%s:hidden\n' "$engine"
  fi
}

case "$mode" in
  waybar) start_waybar ;;
  wayle) start_wayle ;;
  toggle)
    if [ "$(read_engine)" = "wayle" ]; then
      start_waybar
    else
      start_wayle || start_waybar
    fi
    ;;
  toggle-view)
    if is_visible; then
      hide_panel
    else
      show_panel
    fi
    ;;
  show) show_panel ;;
  hide) hide_panel ;;
  status)
    status_line
    ;;
  *)
    echo "usage: $0 [toggle|wayle|waybar|toggle-view|show|hide|status]" >&2
    exit 1
    ;;
esac
