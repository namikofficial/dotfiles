#!/usr/bin/env bash
# Idempotent ChatGPT desktop activation.
set -euo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/noxflow"
lock_file="$state_dir/chatgpt-launcher.lock"
mkdir -p "$state_dir"

find_chatgpt_address() {
  command -v hyprctl >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || return 1
  hyprctl clients -j 2>/dev/null |
    jq -r '.[] | select(((.class // "") | ascii_downcase) == "chatgpt") | .address' |
    sed -n '/^0x[0-9a-fA-F]\+$/p' |
    head -n 1
}

find_chatgpt_main_pids() {
  command -v ps >/dev/null 2>&1 || return 1
  ps -eo pid=,args= 2>/dev/null |
    awk -v bin="$chatgpt_binary" \
      '$2 == bin && $0 !~ / --type=/ {print $1}'
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

exec 9>"$lock_file"
if ! flock -n 9; then
  # Another activation is already focusing, recovering, or launching ChatGPT.
  exit 0
fi

existing_main_pids="$(find_chatgpt_main_pids || true)"
existing_address="$(find_chatgpt_address || true)"

if [ -n "$existing_address" ]; then
  hyprctl dispatch focuswindow "address:$existing_address" >/dev/null 2>&1 || true
  if [ "$#" -gt 0 ]; then
    notify_status "ChatGPT callback received" "The existing ChatGPT window was focused; its profile is already active, so the callback was not replayed."
  fi
  exit 0
fi

if [ -n "$existing_main_pids" ]; then
  # A main process without a Hyprland client is stale or failed during startup.
  # Reclaim the profile so desktop activation recovers instead of dead-ending
  # with an "already running" notification forever.
  while IFS= read -r pid; do
    [ -n "$pid" ] && kill -TERM "$pid" 2>/dev/null || true
  done <<<"$existing_main_pids"
  for _ in $(seq 1 "${CHATGPT_RECOVERY_ATTEMPTS:-20}"); do
    [ -z "$(find_chatgpt_main_pids || true)" ] && break
    sleep 0.1
  done
  remaining_pids="$(find_chatgpt_main_pids || true)"
  while IFS= read -r pid; do
    [ -n "$pid" ] && kill -KILL "$pid" 2>/dev/null || true
  done <<<"$remaining_pids"
fi

if [ -z "$chatgpt_binary" ] || [ ! -x "$chatgpt_binary" ]; then
  printf 'ChatGPT binary not found; set CHATGPT_BINARY to its path\n' >&2
  exit 127
fi

# Detach the long-lived Electron process so gtk-launch and the desktop shell do
# not remain blocked as its parent. The activation lock stays in this short-lived
# wrapper only; the application cannot inherit it and block future activations.
nohup "$chatgpt_binary" --ozone-platform=wayland "$@" 9>&- >/dev/null 2>&1 &
launch_pid=$!
for _ in $(seq 1 "${CHATGPT_STARTUP_ATTEMPTS:-50}"); do
  sleep 0.1
  focus_existing && exit 0
  if ! kill -0 "$launch_pid" 2>/dev/null; then
    notify_status "ChatGPT failed to open" "The ChatGPT process exited before creating a window."
    exit 1
  fi
done
exit 0
