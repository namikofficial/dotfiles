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

alt_panel_enabled() {
  [ "${NOXFLOW_ENABLE_HYPRPANEL:-0}" = "1" ]
}

read_engine() {
  if [ -f "$engine_file" ]; then
    saved="$(cat "$engine_file" 2>/dev/null || true)"
    case "$saved" in
      waybar)
        printf '%s\n' "$saved"
        return 0
        ;;
      hyprpanel)
        if alt_panel_enabled; then
          printf '%s\n' "$saved"
          return 0
        fi
        ;;
    esac
  fi

  if alt_panel_enabled && pgrep -x hyprpanel >/dev/null 2>&1; then
    printf 'hyprpanel\n'
    return 0
  fi

  printf 'waybar\n'
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
  if ! alt_panel_enabled; then
    notify "Alt panel disabled" "Waybar remains the default panel."
    exit 1
  fi
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
    if alt_panel_enabled && command -v hyprpanel >/dev/null 2>&1; then
      if [ "$(read_engine)" = "hyprpanel" ]; then
        start_waybar
      else
        start_hyprpanel
      fi
    else
      if is_visible; then
        hide_panel
      else
        start_waybar
      fi
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
