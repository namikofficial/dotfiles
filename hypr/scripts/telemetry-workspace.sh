#!/usr/bin/env sh
set -eu

mode="${1:-open}"
workspace_id="${NOXFLOW_TELEMETRY_WORKSPACE:-10}"
session_name="${NOXFLOW_TELEMETRY_SESSION:-noxflow-telemetry}"
window_class="${NOXFLOW_TELEMETRY_CLASS:-noxflow-telemetry}"
window_title="${NOXFLOW_TELEMETRY_TITLE:-System Telemetry Dashboard}"
script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
network_script="$script_dir/telemetry-network.sh"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

goto_workspace() {
  hyprctl dispatch workspace "$workspace_id" >/dev/null 2>&1 || true
}

find_client_address() {
  hyprctl -j clients 2>/dev/null \
    | jq -r --arg class "$window_class" '.[] | select(.class == $class) | .address' \
    | head -n 1
}

focus_existing_client() {
  address="$(find_client_address || true)"
  if [ -n "${address:-}" ] && [ "$address" != "null" ]; then
    goto_workspace
    hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

new_pane_cmd() {
  command="$1"
  tmux split-window "$2" -t "$session_name:1" -c "$HOME" "$command" >/dev/null
}

ensure_session() {
  if tmux has-session -t "$session_name" >/dev/null 2>&1; then
    return 0
  fi

  tmux new-session -d -s "$session_name" -n telemetry -c "$HOME" "nvtop"
  tmux rename-window -t "$session_name:1" "telemetry"
  new_pane_cmd "btop" "-h"
  tmux select-pane -t "$session_name:1.1" >/dev/null
  new_pane_cmd "$network_script" "-v"
  tmux select-pane -t "$session_name:1.2" >/dev/null
  new_pane_cmd "journalctl -b -f -n 120 --no-hostname --no-pager" "-v"

  tmux select-pane -t "$session_name:1.1" -T "GPU" >/dev/null
  tmux select-pane -t "$session_name:1.2" -T "CPU" >/dev/null
  tmux select-pane -t "$session_name:1.3" -T "Network" >/dev/null
  tmux select-pane -t "$session_name:1.4" -T "Logs" >/dev/null
  tmux select-pane -t "$session_name:1.1" >/dev/null
}

launch_terminal() {
  goto_workspace
  kitty --class "$window_class" --title "$window_title" -e tmux attach-session -t "$session_name" >/dev/null 2>&1 &
}

reset_session() {
  tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
}

print_status() {
  if tmux has-session -t "$session_name" >/dev/null 2>&1; then
    printf 'tmux session: present\n'
  else
    printf 'tmux session: missing\n'
  fi

  address="$(find_client_address || true)"
  if [ -n "${address:-}" ] && [ "$address" != "null" ]; then
    printf 'hyprland client: %s\n' "$address"
  else
    printf 'hyprland client: missing\n'
  fi
}

require_cmd hyprctl
require_cmd jq
require_cmd kitty
require_cmd tmux
require_cmd btop
require_cmd nvtop
require_cmd journalctl
require_cmd ip
require_cmd ss

case "$mode" in
  open)
    if focus_existing_client; then
      exit 0
    fi
    ensure_session
    launch_terminal
    ;;
  reset)
    reset_session
    ensure_session
    launch_terminal
    ;;
  status)
    print_status
    ;;
  *)
    printf 'usage: %s [open|reset|status]\n' "$0" >&2
    exit 1
    ;;
esac
