#!/usr/bin/env bash
# Idempotent ChatGPT desktop activation.
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
lock_file="$state_dir/chatgpt-launcher.lock"
mkdir -p "$state_dir"

find_chatgpt_address() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  hyprctl clients -j 2>/dev/null \
    | jq -r '.[] | select((.class // "") | ascii_downcase == "chatgpt") | .address' \
    | sed -n '/^0x[0-9a-fA-F]\+$/p' \
    | head -n 1
}

find_chatgpt_main_pid() {
  command -v ps >/dev/null 2>&1 || return 1
  ps -eo pid=,args= 2>/dev/null \
    | awk -v bin="$chatgpt_binary" \
      '$2 == bin && $0 !~ / --type=/ {print $1; exit}'
}

notify_status() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a ChatGPT "$1" "$2" >/dev/null 2>&1 || true
}

focus_existing() {
  local address
  address="$(find_chatgpt_address || true)"
  [ -n "$address" ] || return 1
  hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1
}

chatgpt_binary="${CHATGPT_BINARY:-$HOME/.local/opt/chatgpt/ChatGPT}"
if [ ! -x "$chatgpt_binary" ]; then
  chatgpt_binary="$(command -v ChatGPT 2>/dev/null || true)"
fi

existing_main_pid="$(find_chatgpt_main_pid || true)"
existing_address="$(find_chatgpt_address || true)"

if [ -n "$existing_address" ]; then
  hyprctl dispatch focuswindow "address:$existing_address" >/dev/null 2>&1 || true
  if [ "$#" -gt 0 ]; then
    notify_status "ChatGPT callback received" "The existing ChatGPT window was focused; its profile is already active, so the callback was not replayed."
  fi
  exit 0
fi

if [ -n "$existing_main_pid" ]; then
  notify_status "ChatGPT is already running" "A headless ChatGPT process (PID $existing_main_pid) owns the profile; no second window was started."
  exit 1
fi

if [ "$#" -eq 0 ]; then
  # Fast path avoids contending with a lock inherited by a pre-existing
  # ChatGPT process from an older wrapper version.
  exec 9>"$lock_file"
  if ! flock -n 9; then
    # Another activation is handing off a new client; do not start a second
    # process while that handoff is in flight.
    exit 0
  fi
  if [ -n "$(find_chatgpt_address || true)" ]; then
    focus_existing
    exit 0
  fi
  if [ -z "$chatgpt_binary" ] || [ ! -x "$chatgpt_binary" ]; then
    printf 'ChatGPT binary not found; set CHATGPT_BINARY to its path\n' >&2
    exit 127
  fi

  # Keep the lock only until Hyprland sees the new client. This prevents two
  # rapid key presses from spawning two windows without pinning the lock to
  # the long-lived ChatGPT process.
  nohup "$chatgpt_binary" --ozone-platform=wayland >/dev/null 2>&1 &
  for _ in $(seq 1 20); do
    sleep 0.1
    focus_existing && exit 0
  done
  exit 0
fi

if [ -z "$chatgpt_binary" ] || [ ! -x "$chatgpt_binary" ]; then
  printf 'ChatGPT binary not found; set CHATGPT_BINARY to its path\n' >&2
  exit 127
fi

# Preserve every caller argument, especially codex:// OAuth callback URLs.
exec "$chatgpt_binary" --ozone-platform=wayland "$@"
