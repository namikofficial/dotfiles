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
LOCAL_AI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/local-ai"
CURRENT_MODEL_ENV="$LOCAL_AI_DIR/current-model.env"
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
  if ! LLAMA_SERVER_BIN="$(pick_executable "$LLAMA_SERVER_BIN" "$HOME/.local/bin/llama-server" /usr/local/bin/llama-server /usr/bin/llama-server)"; then
    echo "unable to locate llama-server binary" >&2
    exit 1
  fi
  if ! LLAMA_SWAP_BIN="$(pick_executable "$LLAMA_SWAP_BIN" "$HOME/.local/bin/llama-swap" /usr/local/bin/llama-swap /usr/bin/llama-swap)"; then
    echo "unable to locate llama-swap binary" >&2
    exit 1
  fi
}

render_config() {
  [ -f "$TEMPLATE" ] || {
    echo "missing template: $TEMPLATE" >&2
    exit 1
  }
  resolve_bins
  python - "$TEMPLATE" "$CONFIG_FILE" "$MODEL_ROOT" "$LLAMA_SERVER_BIN" <<'PY'
from pathlib import Path
import datetime
import os
import re
import shutil
import sys

template = Path(sys.argv[1])
config = Path(sys.argv[2])
model_root = Path(sys.argv[3])
llama_server = sys.argv[4]
specs = {
    'qwen3-8b': 'Qwen3-8B-Q4_K_M.gguf',
    'qwen-coder-7b': 'qwen2.5-coder-7b-instruct-q4_k_m.gguf',
    'gemma-3-4b': 'google_gemma-3-4b-it-Q4_K_M.gguf',
    'phi-4-mini': 'Phi-4-Mini-Instruct-Q4_K_M.gguf',
    'deepseek-r1-7b': 'DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf',
    'llama-3b': 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
    'qwen3-4b': 'Qwen_Qwen3-4B-Q4_K_M.gguf',
    'qwen3-router': 'Qwen_Qwen3-1.7B-Q5_K_M.gguf',
}

def valid_gguf(path: Path) -> bool:
    try:
        return path.is_file() and path.stat().st_size > 0 and path.open('rb').read(4) == b'GGUF'
    except OSError:
        return False

available = {name for name, filename in specs.items() if valid_gguf(model_root / filename)}
rendered = template.read_text().replace('__MODEL_ROOT__', str(model_root)).replace('__LLAMA_SERVER__', llama_server)
lines = rendered.splitlines()
out = []
i = 0
while i < len(lines):
    out.append(lines[i])
    if lines[i].strip() == 'models:':
        i += 1
        break
    i += 1
while i < len(lines):
    if lines[i].strip() == 'groups:':
        break
    match = re.match(r'^  ([A-Za-z0-9._-]+):\s*$', lines[i])
    if not match:
        i += 1
        continue
    name = match.group(1)
    block = [lines[i]]
    i += 1
    while i < len(lines) and lines[i].strip() != 'groups:' and not re.match(r'^  [A-Za-z0-9._-]+:\s*$', lines[i]):
        block.append(lines[i])
        i += 1
    if name in available:
        out.extend(block)
        out.append('')
if i < len(lines) and lines[i].strip() == 'groups:':
    groups = []
    for line in lines[i + 1:]:
        match = re.match(r'^  (/[^:]+): \[(.*)\]$', line)
        if not match:
            continue
        members = [item.strip() for item in match.group(2).split(',') if item.strip()]
        members = [item for item in members if item in available]
        if members:
            groups.append(f"  {match.group(1)}: [{', '.join(members)}]")
    if groups:
        out.append('groups:')
        out.extend(groups)
content = '\n'.join(out).rstrip() + '\n'
config.parent.mkdir(parents=True, exist_ok=True)
if config.exists():
    stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
    shutil.copy2(config, config.with_name(f'{config.name}.bak.{stamp}'))
tmp = config.with_name(f'{config.name}.new')
tmp.write_text(content)
os.replace(tmp, config)
PY
}

start() {
  resolve_bins
  render_config
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "llama-swap already running in tmux session '$TMUX_SESSION'"
    exit 0
  fi
  tmux new-session -d -s "$TMUX_SESSION" \
    "PORT=$PORT '$LLAMA_SWAP_BIN' --config '$CONFIG_FILE' 2>&1 | tee -a '$LOG_FILE'"
  sleep 3
  status
}

stop() {
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux kill-session -t "$TMUX_SESSION"
    echo "stopped $TMUX_SESSION"
  else
    echo "llama-swap not running"
  fi
}

status() {
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "status: running"
    echo "session: $TMUX_SESSION"
    echo "endpoint: http://127.0.0.1:$PORT/v1"
    if [ -f "$LOG_FILE" ]; then
      echo "log: $LOG_FILE"
      echo "recent log:"
      tail -n 5 "$LOG_FILE"
    fi
  else
    echo "status: stopped"
  fi
}

logs() {
  [ -f "$LOG_FILE" ] || {
    echo "no log file yet"
    exit 1
  }
  tail -n 50 "$LOG_FILE"
}

test_chat() {
  ensure_cmd curl
  curl -sS -X POST "http://127.0.0.1:$PORT/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d '{"model":"local","messages":[{"role":"user","content":"Reply with: local ai ok"}],"temperature":0}'
  echo
}

switch_model() {
  local requested="${2:-}"
  local model alias
  [ -n "$requested" ] || {
    echo "usage: $(basename "$0") switch <model>" >&2
    exit 1
  }
  case "$requested" in
    local | qwen3 | qwen3-8b)
      model="qwen3-8b"
      alias="local"
      ;;
    qwen-coder | qwen-coder-7b)
      model="qwen-coder-7b"
      alias="qwen-coder-7b"
      ;;
    gemma | gemma4 | gemma-3-4b)
      model="gemma-3-4b"
      alias="gemma-3-4b"
      ;;
    phi4 | phi-4-mini)
      model="phi-4-mini"
      alias="phi-4-mini"
      ;;
    deepseek | deepseek-r1 | r1-7b | deepseek-r1-7b)
      model="deepseek-r1-7b"
      alias="deepseek-r1"
      ;;
    llama3b | llama-3b)
      model="llama-3b"
      alias="llama3b"
      ;;
    qwen3-4b | qwen4)
      model="qwen3-4b"
      alias="qwen3-4b"
      ;;
    router | qwen3-router | qwen3-1b)
      model="qwen3-router"
      alias="router"
      ;;
    *)
      echo "unknown model alias: $requested" >&2
      exit 1
      ;;
  esac
  render_config
  mkdir -p "$LOCAL_AI_DIR"
  cat >"$CURRENT_MODEL_ENV" <<EOF2
CURRENT_MODEL=$model
CURRENT_ALIAS=$alias
LOCAL_AI_ENDPOINT=http://127.0.0.1:$PORT/v1
MODEL_ROOT=$MODEL_ROOT
EOF2
  echo "current model set to $model (alias: $alias)"
}

usage() {
  cat <<EOF2
Usage: $(basename "$0") <start|stop|restart|status|logs|render-config|switch|test>
EOF2
}

cmd="${1:-status}"
case "$cmd" in
  start) start ;;
  stop) stop ;;
  restart)
    stop
    start
    ;;
  status) status ;;
  logs) logs ;;
  render-config) render_config ;;
  switch) switch_model "$@" ;;
  test) test_chat ;;
  *)
    usage
    exit 1
    ;;
esac
