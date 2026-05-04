#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kage"
LOG_DIR="$STATE_DIR/llm-logs"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/noxflow"
TMUX_SESSION="llama-swap"
PORT="${LLAMA_SWAP_PORT:-8080}"
MODEL_ROOT="${LLAMA_MODEL_ROOT:-$HOME/models}"
TEMPLATE="${LLAMA_SWAP_TEMPLATE:-$HOME/Documents/code/dotfiles/system/llama-swap/config.template.yaml}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/llama-swap"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
LOG_FILE="$LOG_DIR/llama-swap.log"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$RUNTIME_DIR" "$CONFIG_DIR"

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

render_config() {
  [ -f "$TEMPLATE" ] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
  sed "s#__MODEL_ROOT__#${MODEL_ROOT}#g" "$TEMPLATE" > "$CONFIG_FILE"
}

check_cuda_backend() {
  ensure_cmd llama-server
  local devices
  devices="$(llama-server --list-devices 2>&1 || true)"
  if ! grep -Eqi 'cuda|nvidia' <<<"$devices"; then
    echo "llama-server does not report CUDA/NVIDIA device support" >&2
    echo "Install a CUDA-enabled llama.cpp package (example: llama.cpp-cuda-git)" >&2
    return 1
  fi
}

start() {
  ensure_cmd tmux
  ensure_cmd llama-swap
  render_config
  check_cuda_backend

  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION" || true
    sleep 0.2
  fi

  tmux new-session -d -s "$TMUX_SESSION" \
    "llama-swap -config '$CONFIG_FILE' -listen 127.0.0.1:${PORT} -watch-config 2>&1 | tee -a '$LOG_FILE'"
  sleep 1

  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "failed to start llama-swap" >&2
    exit 1
  fi

  echo "llama-swap running at http://127.0.0.1:${PORT}/v1"
}

stop() {
  tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
}

status() {
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "status: running"
    echo "endpoint: http://127.0.0.1:${PORT}/v1"
    curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/v1/models" | jq '.' 2>/dev/null || true
  else
    echo "status: stopped"
  fi
}

logs() {
  tail -f "$LOG_FILE"
}

test_chat() {
  curl -sS --max-time 90 "http://127.0.0.1:${PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d '{"model":"local","messages":[{"role":"user","content":"Say hello from llama-swap."}],"max_tokens":48,"temperature":0.2}' | jq '.'
}

case "${1:-status}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  logs) logs ;;
  test) test_chat ;;
  render-config) render_config; echo "$CONFIG_FILE" ;;
  *) echo "usage: $0 {start|stop|restart|status|logs|test|render-config}"; exit 1 ;;
esac
