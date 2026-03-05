#!/usr/bin/env sh
set -eu

mode="${1:-open}"
workspace_id="${NOXFLOW_LOGS_WORKSPACE:-9}"

open_logs_terminal() {
  kitty --class noxflow-logs --title "Noxflow Logs" -e sh -lc '
    printf "Workspace logs view\n\n"
    printf "1) journalctl -b -f\n2) waybar log\n3) hyprland runtime log tail\n\n"
    journalctl -b -f -n 150 --no-hostname --no-pager
  ' >/dev/null 2>&1 &
}

open_tail_terminal() {
  # shellcheck disable=SC2016
  kitty --class noxflow-logs --title "Noxflow Waybar Log" -e sh -lc '
    log_file="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow/waybar.log"
    mkdir -p "$(dirname "$log_file")"
    touch "$log_file"
    tail -n 200 -f "$log_file"
  ' >/dev/null 2>&1 &
}

goto_workspace() {
  hyprctl dispatch workspace "$workspace_id" >/dev/null 2>&1 || true
}

case "$mode" in
  open)
    goto_workspace
    open_logs_terminal
    ;;
  stack)
    goto_workspace
    open_logs_terminal
    open_tail_terminal
    ;;
  tail)
    goto_workspace
    open_tail_terminal
    ;;
  *)
    echo "usage: $0 [open|stack|tail]" >&2
    exit 1
    ;;
esac
