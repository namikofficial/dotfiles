#!/usr/bin/env bash
# Complete LLM Setup with Tmux + Logging + Wayle Integration
# For: i7-13 + GTX 4050 6GB (Gemma + DeepSeek-Coder)
# Location: ~/Documents/code/dotfiles/system/llm-manager.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${HOME}/llama-models"
LOGS_DIR="${HOME}/.cache/kage/llm-logs"
TMUX_SESSION="llm-server"
CONFIG_FILE="${HOME}/.config/kage/llama.conf"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

notify_send() {
  notify-send -a "llm-manager" "$1" "${2:-}" 2>/dev/null || true
}

log_msg() {
  local level="$1"
  shift
  local msg="$@"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${BLUE}[${timestamp}]${NC} ${level}: ${msg}"
  echo "[${timestamp}] ${level}: ${msg}" >> "${LOGS_DIR}/llm.log"
}

# ── Initialization ─────────────────────────────────────────────────

mkdir -p "$MODELS_DIR" "$LOGS_DIR"

# Load config if exists
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  log_msg "WARN" "Config not found at $CONFIG_FILE, using defaults"
fi

# ── COMMANDS ───────────────────────────────────────────────────────

cmd_status() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "LLM Server Status"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Check if tmux session exists
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo -e "${GREEN}✓ Tmux session running: $TMUX_SESSION${NC}"
    
    # Get running model
    if curl -s http://127.0.0.1:8000/v1/models >/dev/null 2>&1; then
      MODEL=$(curl -s http://127.0.0.1:8000/v1/models | jq -r '.data[0].id // "unknown"' 2>/dev/null || echo "unknown")
      echo -e "${GREEN}✓ Server responding on port 8000${NC}"
      echo "  Model: $MODEL"
      
      # Show recent logs
      echo
      echo "Recent logs:"
      tail -5 "${LOGS_DIR}/llm.log" 2>/dev/null || echo "  (no logs yet)"
    else
      echo -e "${YELLOW}⚠ Server not responding on port 8000${NC}"
      echo "  Check logs: tail -f ${LOGS_DIR}/llm.log"
    fi
  else
    echo -e "${RED}✗ No running session${NC}"
    echo "  Start with: llm-manager start [gemma|code]"
  fi
  
  echo
  echo "Available models:"
  ls -lh "$MODELS_DIR"/*.gguf 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}' || echo "  (no models found)"
  
  echo
  echo "Logs: $LOGS_DIR"
  echo "Config: $CONFIG_FILE"
}

cmd_start() {
  local model="${1:-gemma}"
  
  # Kill existing session
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    log_msg "INFO" "Stopping existing session..."
    tmux kill-session -t "$TMUX_SESSION"
    sleep 1
  fi
  
  # Select model file
  local model_file
  case "$model" in
    gemma)
      model_file="$MODELS_DIR/gemma-7b-it-Q4_K_M.gguf"
      ;;
    code|deepseek|coder)
      model_file="$MODELS_DIR/deepseek-coder-6.7b-instruct-Q4_K_M.gguf"
      ;;
    *)
      echo "Usage: llm-manager start [gemma|code]"
      exit 1
      ;;
  esac
  
  # Check model exists
  if [ ! -f "$model_file" ]; then
    echo -e "${RED}✗ Model not found: $model_file${NC}"
    echo "  Download: llm-manager download"
    exit 1
  fi
  
  log_msg "INFO" "Starting $model model..."
  log_msg "INFO" "Model: $model_file"
  
  # Create new tmux session with logging
  tmux new-session -d -s "$TMUX_SESSION" -c "$MODELS_DIR" \
    "llama-server \
      -m '$model_file' \
      -ngl 32 \
      --port 8000 \
      -c 4096 \
      -t 8 \
      2>&1 | tee -a '${LOGS_DIR}/llm.log'"
  
  sleep 2
  
  # Verify it started
  if curl -s http://127.0.0.1:8000/v1/models >/dev/null 2>&1; then
    log_msg "INFO" "✓ Server started successfully"
    notify_send "LLM Server" "✓ $model started on port 8000"
    echo -e "${GREEN}✓ Server running!${NC}"
    echo "  View logs: llm-manager logs"
    echo "  Test it: curl -X POST http://localhost:8000/v1/completions ..."
  else
    log_msg "ERROR" "Server failed to start"
    notify_send "LLM Server" "❌ Failed to start server"
    echo -e "${RED}✗ Server failed to start${NC}"
    echo "  Check logs: llm-manager logs"
    exit 1
  fi
}

cmd_stop() {
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    log_msg "INFO" "Stopping LLM server..."
    tmux kill-session -t "$TMUX_SESSION"
    log_msg "INFO" "✓ Server stopped"
    notify_send "LLM Server" "Stopped"
    echo -e "${GREEN}✓ Server stopped${NC}"
  else
    echo "No running session"
  fi
}

cmd_logs() {
  if [ ! -f "${LOGS_DIR}/llm.log" ]; then
    echo "No logs yet"
    exit 0
  fi
  
  echo "=== LLM Server Logs ==="
  echo "(Press Ctrl+C to exit)"
  echo
  tail -f "${LOGS_DIR}/llm.log"
}

cmd_download() {
  echo "╔════════════════════════════════════════════════════════════╗"
  echo "║            Downloading LLM Models                          ║"
  echo "╚════════════════════════════════════════════════════════════╝"
  echo
  
  mkdir -p "$MODELS_DIR"
  cd "$MODELS_DIR"
  
  # Gemma
  if [ ! -f gemma-7b-it-Q4_K_M.gguf ]; then
    echo "Downloading Gemma 7B (~4.5 GB)..."
    wget -q --show-progress \
      "https://huggingface.co/TheBloke/Gemma-7B-Instruct-GGUF/resolve/main/gemma-7b-it-Q4_K_M.gguf" \
      || { log_msg "ERROR" "Gemma download failed"; exit 1; }
    log_msg "INFO" "✓ Gemma downloaded"
  else
    echo "✓ Gemma already exists"
  fi
  
  # DeepSeek-Coder
  if [ ! -f deepseek-coder-6.7b-instruct-Q4_K_M.gguf ]; then
    echo "Downloading DeepSeek-Coder 6.7B (~4.0 GB)..."
    wget -q --show-progress \
      "https://huggingface.co/TheBloke/deepseek-coder-6.7B-instruct-GGUF/resolve/main/deepseek-coder-6.7b-instruct-Q4_K_M.gguf" \
      || { log_msg "ERROR" "DeepSeek download failed"; exit 1; }
    log_msg "INFO" "✓ DeepSeek-Coder downloaded"
  else
    echo "✓ DeepSeek-Coder already exists"
  fi
  
  echo
  echo -e "${GREEN}✓ All models ready!${NC}"
}

cmd_attach() {
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    tmux attach-session -t "$TMUX_SESSION"
  else
    echo "No running session. Start with: llm-manager start"
  fi
}

cmd_test() {
  echo "Testing LLM server..."
  
  if ! curl -s http://127.0.0.1:8000/v1/models >/dev/null 2>&1; then
    echo -e "${RED}✗ Server not responding${NC}"
    exit 1
  fi
  
  echo -e "${GREEN}✓ Server responding${NC}"
  
  echo "Sending test prompt..."
  response=$(curl -s -X POST http://127.0.0.1:8000/v1/completions \
    -H "Content-Type: application/json" \
    -d '{"prompt":"Hello world in Python:","max_tokens":50}')
  
  if echo "$response" | jq . >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Response received:${NC}"
    echo "$response" | jq '.choices[0].text' 2>/dev/null || echo "$response"
  else
    echo -e "${RED}✗ Invalid response${NC}"
  fi
}

# ── MAIN ───────────────────────────────────────────────────────────

cmd="${1:-help}"

case "$cmd" in
  start)   cmd_start "${2:-gemma}" ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  download) cmd_download ;;
  attach)  cmd_attach ;;
  test)    cmd_test ;;
  *)
    cat << 'HELP'
LLM Manager - Control local LLM server with tmux

USAGE:
  llm-manager <command> [args]

COMMANDS:
  start [gemma|code]  - Start LLM server with model (default: gemma)
  stop                - Stop running server
  status              - Show server status
  logs                - Tail server logs
  download            - Download models
  attach              - Attach to tmux session
  test                - Test server response

EXAMPLES:
  llm-manager download           # Download models first
  llm-manager start gemma        # Start with Gemma
  llm-manager status             # Check status
  llm-manager logs               # View logs
  llm-manager test               # Test it works

HELP
    ;;
esac
