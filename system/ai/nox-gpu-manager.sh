#!/usr/bin/env bash
set -euo pipefail

# Coordinates the 6 GB GPU between llama.cpp and transformer helpers.
# `acquire` stops GPU chat/embedding servers; `release` restores chat.
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}/noxflow/ai-gpu"
MARKER="$STATE_DIR/chat-was-running"
EMBED_MARKER="$STATE_DIR/embed-was-running"
LLAMA_MANAGER="${NOX_LLAMA_MANAGER:-$HOME/Documents/code/dotfiles/system/llama-swap-manager.sh}"
EMBED_MANAGER="${NOX_EMBED_MANAGER:-$HOME/Documents/code/dotfiles/system/embedding-server-manager.sh}"

mkdir -p "$STATE_DIR"

is_running() {
  tmux has-session -t "$1" 2>/dev/null
}

acquire() {
  local owner="${2:-transformer}"
  if is_running llama-swap; then
    printf 'stopping llama-swap for %s\n' "$owner"
    "$LLAMA_MANAGER" stop
    printf '1\n' >"$MARKER"
  else
    : >"$MARKER"
  fi
  if is_running llama-embed; then
    printf 'stopping llama-embed for %s\n' "$owner"
    "$EMBED_MANAGER" stop
    printf '1\n' >"$EMBED_MARKER"
  else
    : >"$EMBED_MARKER"
  fi
}

release() {
  if [ -s "$MARKER" ]; then
    printf 'restoring llama-swap\n'
    "$LLAMA_MANAGER" start
  elif [ -s "$EMBED_MARKER" ]; then
    printf 'restoring llama-embed\n'
    "$EMBED_MANAGER" start
  fi
  rm -f "$MARKER" "$EMBED_MARKER"
}

with_gpu() {
  [ "$#" -gt 0 ] || { echo "usage: $0 with <command> [args...]" >&2; exit 2; }
  acquire "${1:-command}"
  trap release EXIT INT TERM
  "$@"
}

case "${1:-status}" in
  acquire) acquire "${2:-transformer}" ;;
  release) release ;;
  with) shift; with_gpu "$@" ;;
  status)
    is_running llama-swap && echo 'chat: running' || echo 'chat: stopped'
    is_running llama-embed && echo 'embedding-server: running' || echo 'embedding-server: stopped'
    ;;
  *) echo "usage: $(basename "$0") <acquire|release|with|status>" >&2; exit 2 ;;
esac
