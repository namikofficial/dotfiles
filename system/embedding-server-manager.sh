#!/usr/bin/env bash
set -euo pipefail

MODEL_ROOT="${LLAMA_MODEL_ROOT:-/home/namik/llama-models}"
MODEL_DIR="${LLAMA_EMBED_MODEL_DIR:-$MODEL_ROOT/embed/nomic-embed-text-v2-moe}"
PORT="${LLAMA_EMBED_PORT:-8081}"
SESSION="${LLAMA_EMBED_TMUX_SESSION:-llama-embed}"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kage/llm-logs"
LOG_FILE="$LOG_DIR/embedding-server.log"
SERVER="${LLAMA_SERVER_BIN:-$(command -v llama-server || true)}"

find_model() {
  find "$MODEL_DIR" -type f -name '*.gguf' -size +0c -print -quit 2>/dev/null
}

start() {
  [ -x "$SERVER" ] || { echo "llama-server not found; install llama.cpp first" >&2; exit 1; }
  local model
  model="$(find_model)"
  [ -n "$model" ] || {
    echo "embedding GGUF not found under $MODEL_DIR" >&2
    echo "Download nomic-embed-text-v2-moe into $MODEL_DIR first." >&2
    exit 1
  }
  mkdir -p "$LOG_DIR"
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "embedding server already running"
    return 0
  fi
  tmux new-session -d -s "$SESSION" +    "exec '$SERVER' -m '$model' --host 127.0.0.1 --port $PORT --embeddings --n-gpu-layers ${LLAMA_N_GPU_LAYERS:-999} 2>&1 | tee -a '$LOG_FILE'"
  sleep 2
  status
}

stop() {
  tmux has-session -t "$SESSION" 2>/dev/null && tmux kill-session -t "$SESSION" || true
}

status() {
  if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
    echo "embedding: running (http://127.0.0.1:$PORT/v1)"
  else
    echo "embedding: stopped (http://127.0.0.1:$PORT/v1)"
  fi
}

case "${1:-status}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  logs) tail -n 80 "$LOG_FILE" ;;
  *) echo "usage: $(basename "$0") <start|stop|restart|status|logs>" >&2; exit 2 ;;
esac
