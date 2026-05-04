#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kage"
LOG_DIR="$STATE_DIR/llm-logs"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/noxflow"
TMUX_SESSION="llama-swap"
PORT="${LLAMA_SWAP_PORT:-8080}"
MODEL_ROOT="${LLAMA_MODEL_ROOT:-$HOME/llama-models}"
TEMPLATE="${LLAMA_SWAP_TEMPLATE:-$HOME/Documents/code/dotfiles/system/llama-swap/config.template.yaml}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/llama-swap"
CONFIG_FILE="$CONFIG_DIR/config.yaml"
LOG_FILE="$LOG_DIR/llama-swap.log"
LLAMA_SERVER_BIN="${LLAMA_SERVER_BIN:-}"
LLAMA_SWAP_BIN="${LLAMA_SWAP_BIN:-}"

mkdir -p "$STATE_DIR" "$LOG_DIR" "$RUNTIME_DIR" "$CONFIG_DIR"

ensure_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

pick_executable() {
  local explicit="$1"
  shift
  if [ -n "$explicit" ] && [ -x "$explicit" ]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  local candidate
  for candidate in "$@"; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

resolve_bins() {
  LLAMA_SERVER_BIN="$(pick_executable "$LLAMA_SERVER_BIN" /usr/bin/llama-server "$HOME/.local/bin/llama-server" "$(command -v llama-server 2>/dev/null || true)")" || {
    echo "missing command: llama-server" >&2
    exit 1
  }
  LLAMA_SWAP_BIN="$(pick_executable "$LLAMA_SWAP_BIN" /usr/bin/llama-swap "$HOME/.local/bin/llama-swap" "$(command -v llama-swap 2>/dev/null || true)")" || {
    echo "missing command: llama-swap" >&2
    exit 1
  }
}

is_valid_gguf_file() {
  local file="$1"
  [ -s "$file" ] || return 1
  [ "$(head -c 4 "$file" 2>/dev/null)" = "GGUF" ]
}

remove_model_from_rendered_config() {
  local model="$1" tmp_file
  tmp_file="${CONFIG_FILE}.tmp"
  awk -v model="$model" '
    BEGIN { skip = 0 }
    /^  [A-Za-z0-9._-]+:$/ {
      if ($0 == "  " model ":") {
        skip = 1
        next
      }
      if (skip) {
        skip = 0
      }
    }
    !skip { print }
  ' "$CONFIG_FILE" > "$tmp_file"
  mv "$tmp_file" "$CONFIG_FILE"
}

prune_unavailable_models() {
  local model file
  while IFS='|' read -r model file; do
    [ -n "$model" ] || continue
    if ! is_valid_gguf_file "$file"; then
      echo "skipping model '$model': missing or invalid GGUF file at $file" >&2
      remove_model_from_rendered_config "$model"
    fi
  done <<EOF
llama-3-8b|$MODEL_ROOT/Meta-Llama-3-8B-Instruct-Q4_K_M.gguf
llama-3.2-3b|$MODEL_ROOT/llama-3.2-3b-instruct.gguf
mistral-7b|$MODEL_ROOT/mistral-7b-instruct.gguf
gemma-2-2b|$MODEL_ROOT/gemma-2-2b-instruct-q4_k_m.gguf
EOF
}

render_config() {
  [ -f "$TEMPLATE" ] || { echo "missing template: $TEMPLATE" >&2; exit 1; }
  resolve_bins
  sed \
    -e "s#__MODEL_ROOT__#${MODEL_ROOT}#g" \
    -e "s#__LLAMA_SERVER__#${LLAMA_SERVER_BIN}#g" \
    "$TEMPLATE" > "$CONFIG_FILE"
  prune_unavailable_models
}

check_cuda_backend() {
  resolve_bins
  local devices
  devices="$("$LLAMA_SERVER_BIN" --list-devices 2>&1 || true)"
  if ! grep -Eqi 'cuda|nvidia' <<<"$devices"; then
    echo "$LLAMA_SERVER_BIN does not report CUDA/NVIDIA device support" >&2
    echo "Install a CUDA-enabled llama.cpp package, then rerun llama-swap-manager start" >&2
    return 1
  fi
}

start() {
  ensure_cmd tmux
  render_config
  check_cuda_backend

  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION" || true
    sleep 0.2
  fi

  tmux new-session -d -s "$TMUX_SESSION" \
    "'$LLAMA_SWAP_BIN' -config '$CONFIG_FILE' -listen 127.0.0.1:${PORT} -watch-config 2>&1 | tee -a '$LOG_FILE'"
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
