#!/usr/bin/env sh
set -eu

mode="${1:-toggle}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
engine_file="${state_dir}/panel.engine"

mkdir -p "$state_dir"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Panel "$1" "${2:-}"
}

write_engine() {
  printf '%s\n' "$1" >"$engine_file"
}

read_engine() {
  if [ -f "$engine_file" ]; then
    saved="$(cat "$engine_file" 2>/dev/null || true)"
    case "$saved" in
      waybar|hyprpanel)
        printf '%s\n' "$saved"
        return 0
        ;;
    esac
  fi

  if pgrep -x hyprpanel >/dev/null 2>&1; then
    printf 'hyprpanel\n'
  else
    printf 'waybar\n'
  fi
}

is_visible() {
  pgrep -x waybar >/dev/null 2>&1 || pgrep -x hyprpanel >/dev/null 2>&1 || pgrep -x ags >/dev/null 2>&1
}

start_waybar() {
  pkill -x hyprpanel >/dev/null 2>&1 || true
  pkill -x ags >/dev/null 2>&1 || true
  "$HOME/.config/hypr/scripts/restart-waybar.sh"
  write_engine waybar
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
  write_engine hyprpanel
  notify "Panel mode" "HyprPanel"
}

hide_panel() {
  pkill -x waybar >/dev/null 2>&1 || true
  pkill -x hyprpanel >/dev/null 2>&1 || true
  pkill -x ags >/dev/null 2>&1 || true
  notify "Panel view" "Hidden"
}

show_panel() {
  engine="$(read_engine)"
  case "$engine" in
    hyprpanel)
      start_hyprpanel || start_waybar
      ;;
    *)
      start_waybar
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
  hyprpanel) start_hyprpanel ;;
  toggle)
    if [ "$(read_engine)" = "hyprpanel" ]; then
      start_waybar
    else
      start_hyprpanel
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
    echo "usage: $0 [toggle|waybar|hyprpanel|toggle-view|show|hide|status]" >&2
    exit 1
    ;;
esac
