#!/usr/bin/env sh
# telemetry-workspace.sh — Super+Ctrl+0
# Opens workspace 10 with btop (left) + live system logs (right).
# Uses a dedicated tmux socket (-L telemetry) so it is isolated from
# the main tmux server and its continuum sessions.
set -eu

mode="${1:-open}"
workspace_id="10"
session_name="noxflow-telemetry"
window_class="noxflow-telemetry"
window_title="󰍛  System Monitor"
socket_name="telemetry"

goto_workspace() {
  hyprctl dispatch workspace "$workspace_id" >/dev/null 2>&1 || true
}

find_client_address() {
  hyprctl -j clients 2>/dev/null \
    | python3 -c "
import json,sys
clients = json.load(sys.stdin)
for c in clients:
    if c.get('class') == '${window_class}':
        print(c['address']); break
" 2>/dev/null || true
}

focus_existing_client() {
  address="$(find_client_address)"
  if [ -n "${address:-}" ]; then
    goto_workspace
    hyprctl dispatch focuswindow "address:${address}" >/dev/null 2>&1 || true
    return 0
  fi
  return 1
}

ensure_session() {
  if tmux -L "$socket_name" has-session -t "$session_name" >/dev/null 2>&1; then
    return 0
  fi

  # Left pane: btop
  tmux -L "$socket_name" new-session -d -s "$session_name" -n monitor -c "$HOME" btop

  # Right pane (50% width): live journal logs
  tmux -L "$socket_name" split-window -h -t "${session_name}:1" \
    "journalctl -b -f -n 200 --no-hostname --no-pager -p 0..6" >/dev/null

  # Label panes and focus btop
  tmux -L "$socket_name" select-pane -t "${session_name}:1.1" -T "CPU/RAM" >/dev/null
  tmux -L "$socket_name" select-pane -t "${session_name}:1.2" -T "Logs" >/dev/null
  tmux -L "$socket_name" select-pane -t "${session_name}:1.1" >/dev/null
}

launch_terminal() {
  goto_workspace
  kitty --class "$window_class" --title "$window_title" \
    -e tmux -L "$socket_name" attach-session -t "$session_name" >/dev/null 2>&1 &
}

reset_session() {
  tmux -L "$socket_name" kill-session -t "$session_name" >/dev/null 2>&1 || true
}

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
  *)
    printf 'usage: %s [open|reset]\n' "$0" >&2
    exit 1
    ;;
esac
