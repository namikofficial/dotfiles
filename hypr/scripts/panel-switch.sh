#!/usr/bin/env bash
set -euo pipefail

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
      wayle)
        printf '%s\n' "$saved"
        return 0
        ;;
    esac
  fi

  printf 'wayle\n'
}

is_visible() {
  systemctl --user is-active --quiet wayle.service 2>/dev/null
}

stop_stale_wayle_shells() {
  if systemctl --user is-active --quiet wayle.service 2>/dev/null; then
    return 0
  fi

  pkill -x wayle >/dev/null 2>&1 || true
  sleep 0.2
}

start_wayle() {
  if ! command -v wayle >/dev/null 2>&1; then
    notify "Wayle unavailable" "Install wayle-bin"
    return 1
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    notify "Wayle failed" "systemctl --user is required"
    return 1
  fi

  # Service-only ownership: clean stale service state, then start only via user unit.
  systemctl --user stop wayle.service >/dev/null 2>&1 || true
  systemctl --user reset-failed wayle.service >/dev/null 2>&1 || true
  stop_stale_wayle_shells
  systemctl --user start wayle.service >/dev/null 2>&1 || true
  sleep 0.5

  if ! systemctl --user is-active --quiet wayle.service 2>/dev/null; then
    notify "Wayle failed" "Unable to start service-owned shell"
    return 1
  fi

  write_engine wayle
  notify "Panel mode" "Wayle"
}

hide_panel() {
  systemctl --user stop wayle.service >/dev/null 2>&1 || true
  stop_stale_wayle_shells
  notify "Panel view" "Hidden"
}

show_panel() {
  start_wayle
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
  wayle) start_wayle ;;
  toggle)
    if is_visible; then
      hide_panel
    else
      show_panel
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
    echo "usage: $0 [toggle|wayle|toggle-view|show|hide|status]" >&2
    exit 1
    ;;
esac
