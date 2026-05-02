#!/bin/bash
# LLM Manager - Control llama.cpp server with tmux

set -e

MODEL_DIR="${HOME}/llama-models"
STATE_DIR="${HOME}/.cache/kage"
LOG_DIR="${STATE_DIR}/llm-logs"
TMUX_SESSION="llm-server"

# Create required directories
mkdir -p "$LOG_DIR" "$STATE_DIR"

# Default model
DEFAULT_MODEL="llama"  # Llama 3 8B

# Model configurations
declare -A MODELS=(
  ["llama"]="Meta-Llama-3-8B-Instruct-Q4_K_M.gguf"
  ["mistral"]="Mistral-7B-Instruct-v0.2-Q4_K_M.gguf"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}✗ $1${NC}" >&2; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
info() { echo -e "${BLUE}ℹ $1${NC}"; }

# Get model path
get_model_path() {
  local model="${1:-$DEFAULT_MODEL}"
  local file="${MODELS[$model]}"
  
  if [ -z "$file" ]; then
    echo "Meta-Llama-3-8B-Instruct-Q4_K_M.gguf"
  else
    echo "$file"
  fi
}

# Check if server is running
is_running() {
  tmux list-sessions 2>/dev/null | grep -q "^${TMUX_SESSION}:" && return 0
  return 1
}

# Get server PID
get_server_pid() {
  tmux list-panes -t "$TMUX_SESSION" -F "#{pane_pid}" 2>/dev/null | head -1
}

# Get running model name from processes
get_running_model() {
  local model_file
  model_file=$(ps aux | grep "[l]lama-server" | grep -oE '\S+\.gguf' | head -1 | xargs basename 2>/dev/null)
  [ -n "$model_file" ] && echo "$model_file" || echo "unknown"
}

# Command: start
cmd_start() {
  local model="${1:-$DEFAULT_MODEL}"
  local model_file
  model_file=$(get_model_path "$model")
  local model_path="$MODEL_DIR/$model_file"
  
  # Check if model exists
  if [ ! -f "$model_path" ]; then
    error "Model not found: $model_path"
    warn "Available models:"
    ls -1 "$MODEL_DIR" | sed 's/^/  • /'
    return 1
  fi
  
  # Stop existing session
  if is_running; then
    log "Stopping existing LLM server..."
    tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
    sleep 1
  fi
  
  # Create new session
  log "Starting $model model: $model_file"
  
  tmux new-session -d -s "$TMUX_SESSION" \
    "llama-server -m '$model_path' -n 256 -ngl 32 -t 8 --host 127.0.0.1 --port 8000 2>&1 | tee -a '$LOG_DIR/llm.log'"

  sleep 2

  if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    error "Server process exited immediately"
    warn "Check logs: $LOG_DIR/llm.log"
    return 1
  fi

  if ! pgrep -af "llama-server.*${model_file}" >/dev/null 2>&1; then
    warn "tmux session exists but llama-server is not visible yet"
  fi

  if is_running; then
    log "✓ Server started successfully (PID: $(get_server_pid))"
    echo "{\"status\":\"running\",\"model\":\"$model_file\",\"pid\":$(get_server_pid)}" > "$STATE_DIR/llm-status.json"
  else
    error "Failed to start server"
    warn "Check logs: $LOG_DIR/llm.log"
    return 1
  fi
}

# Command: stop
cmd_stop() {
  if is_running; then
    log "Stopping LLM server..."
    tmux kill-session -t "$TMUX_SESSION"
    log "✓ Server stopped"
    echo '{"status":"stopped"}' > "$STATE_DIR/llm-status.json"
  else
    warn "Server is not running"
  fi
}

# Command: status
cmd_status() {
  if is_running; then
    local pid
    pid=$(get_server_pid)
    local model
    model=$(get_running_model)
    
    info "Server Status: RUNNING"
    echo "  PID: $pid"
    echo "  Model: $model"
    echo "  Port: 8000"
    echo "  Logs: $LOG_DIR/llm.log"
    
    # Test connectivity
    if curl -s http://127.0.0.1:8000/health >/dev/null 2>&1; then
      echo "  Health: ✓ Responsive"
    else
      echo "  Health: ⚠ Not responding"
    fi
  else
    warn "Server Status: STOPPED"
    echo "  Start with: llm-manager start"
  fi
}

# Command: logs
cmd_logs() {
  if [ -f "$LOG_DIR/llm.log" ]; then
    tail -f "$LOG_DIR/llm.log"
  else
    warn "No logs yet"
  fi
}

# Command: attach
cmd_attach() {
  if is_running; then
    tmux attach-session -t "$TMUX_SESSION"
  else
    error "Server is not running"
    return 1
  fi
}

# Command: test
cmd_test() {
  if ! is_running; then
    error "Server is not running. Start with: llm-manager start"
    return 1
  fi
  
  info "Testing server..."
  
  local response
  response=$(curl -s http://127.0.0.1:8000/v1/completions \
    -H "Content-Type: application/json" \
    -d '{
      "model": "gpt-3.5-turbo",
      "prompt": "Hello, how are you?",
      "max_tokens": 10
    }' 2>/dev/null || echo "")
  
  if [ -n "$response" ]; then
    echo "✓ Server is responding"
    echo "$response" | head -c 200
  else
    error "Server not responding on port 8000"
  fi
}

# Command: list
cmd_list() {
  info "Available models:"
  for model in "${!MODELS[@]}"; do
    local file="${MODELS[$model]}"
    if [ -f "$MODEL_DIR/$file" ]; then
      local size
      size=$(du -h "$MODEL_DIR/$file" | cut -f1)
      echo "  ✓ $model ($file, $size)"
    else
      echo "  ✗ $model ($file - missing)"
    fi
  done
  
  echo ""
  info "All files in $MODEL_DIR:"
  if [ -d "$MODEL_DIR" ]; then
    ls -lh "$MODEL_DIR" | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
  else
    echo "  (Directory empty)"
  fi
}

# Command: help
cmd_help() {
  cat << 'EOF'
LLM Manager - Control local LLM server with tmux

USAGE:
  llm-manager <command> [args]

COMMANDS:
  start [model]   - Start LLM server with model (default: llama)
  stop            - Stop running server
  status          - Show server status
  logs            - Tail server logs
  list            - List available models
  attach          - Attach to tmux session
  test            - Test server response
  help            - Show this help

MODELS:
  llama           - Meta-Llama-3 8B (general tasks, Q4 quant)
  mistral         - Mistral 7B (if downloaded)

EXAMPLES:
  llm-manager start              # Start with default model
  llm-manager start llama        # Start Llama 3
  llm-manager status             # Check status
  llm-manager logs               # View logs
  llm-manager test               # Test server

PORTS:
  8000            - OpenAI-compatible API (http://127.0.0.1:8000)
  
ENVIRONMENT:
  Models dir: $MODEL_DIR
  Logs dir: $LOG_DIR
  State dir: $STATE_DIR
EOF
}

# Main dispatcher
main() {
  local cmd="${1:-help}"
  shift || true
  
  case "$cmd" in
    start)  cmd_start "$@" ;;
    stop)   cmd_stop "$@" ;;
    status) cmd_status "$@" ;;
    logs)   cmd_logs "$@" ;;
    list)   cmd_list "$@" ;;
    attach) cmd_attach "$@" ;;
    test)   cmd_test "$@" ;;
    help)   cmd_help ;;
    *)
      error "Unknown command: $cmd"
      echo ""
      cmd_help
      return 1
      ;;
  esac
}

main "$@"
