#!/usr/bin/env bash
set -euo pipefail

mode="${1:-toggle}"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
engine_file="${state_dir}/panel.engine"

mkdir -p "$state_dir"

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a Panel "$1" "${2:-}" >/dev/null 2>&1 || true
}

write_engine() {
  printf '%s\n' "$1" >"$engine_file"
}

read_engine() {
  if [ -f "$engine_file" ]; then
    saved="$(cat "$engine_file" 2>/dev/null || true)"
    case "$saved" in
      noxflow|wayle)
        printf '%s\n' "$saved"
        return 0
        ;;
    esac
  fi

  printf 'wayle\n'
}

is_visible() {
  case "$(read_engine)" in
    noxflow) systemctl --user is-active --quiet noxflow-shell.service 2>/dev/null ;;
    *) systemctl --user is-active --quiet wayle.service 2>/dev/null ;;
  esac
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

  # Service-only ownership: stop the alternate shell before starting Wayle.
  systemctl --user stop noxflow-shell.service >/dev/null 2>&1 || true
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

start_noxflow() {
  if ! command -v quickshell >/dev/null 2>&1; then
    notify "NoxFlow unavailable" "Quickshell is not installed; keeping Wayle"
    start_wayle
    return 1
  fi

  systemctl --user stop wayle.service >/dev/null 2>&1 || true
  systemctl --user reset-failed noxflow-shell.service >/dev/null 2>&1 || true
  systemctl --user start noxflow-shell.service >/dev/null 2>&1 || true
  sleep 0.5

  if ! systemctl --user is-active --quiet noxflow-shell.service 2>/dev/null; then
    notify "NoxFlow failed" "Falling back to Wayle"
    start_wayle
    return 1
  fi

  write_engine noxflow
  notify "Panel mode" "NoxFlow"
}

hide_panel() {
  systemctl --user stop wayle.service >/dev/null 2>&1 || true
  systemctl --user stop noxflow-shell.service >/dev/null 2>&1 || true
  stop_stale_wayle_shells
  notify "Panel view" "Hidden"
}

show_panel() {
  case "$(read_engine)" in
    noxflow) start_noxflow ;;
    *) start_wayle ;;
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
  noxflow) start_noxflow ;;
  wayle) start_wayle ;;
  fallback) start_wayle ;;
  restart)
    case "$(read_engine)" in
      noxflow) systemctl --user restart noxflow-shell.service ;;
      *) start_wayle ;;
    esac
    ;;
  safe-mode)
    write_engine wayle
    systemctl --user stop noxflow-shell.service >/dev/null 2>&1 || true
    start_wayle
    ;;
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
    echo "usage: $0 [noxflow|wayle|fallback|restart|safe-mode|toggle|toggle-view|show|hide|status]" >&2
    exit 1
    ;;
esac
