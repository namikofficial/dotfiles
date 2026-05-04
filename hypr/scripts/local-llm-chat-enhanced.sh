#!/usr/bin/env bash
# local-llm-chat-enhanced.sh
# Improved AI scratchpad with project context, better formatting, and command support

set -euo pipefail

# Colors
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_GREEN='\033[32m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_RESET='\033[0m'

endpoint="${LLM_CHAT_ENDPOINT:-http://127.0.0.1:8080/v1/chat/completions}"
health="${LLM_HEALTH_ENDPOINT:-http://127.0.0.1:8080/v1/models}"
model="${LLM_CHAT_MODEL:-local}"
context_script="${HOME}/.config/hypr/scripts/get-project-context.sh"
msg_count=0

if [ -n "${LLAMA_LIBRARY_PATH:-}" ]; then
  export LD_LIBRARY_PATH="${LLAMA_LIBRARY_PATH}:${LD_LIBRARY_PATH:-}"
fi
if [ -n "${LLAMA_BACKEND_PATH:-}" ]; then
  export GGML_BACKEND_PATH="$LLAMA_BACKEND_PATH"
fi

# Cleanup on exit (Ctrl+C or window close)
cleanup() {
  printf '\n%s✓ Session closed. Messages: %d%s\n' "$C_GREEN" "$msg_count" "$C_RESET"
  exit 0
}
trap cleanup EXIT INT TERM

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1"
    exec zsh -l
  }
}

need_cmd curl
need_cmd jq

start_server() {
  if command -v llama-swap-manager >/dev/null 2>&1; then
    printf 'Starting local llama-swap endpoint...\n'
    llama-swap-manager start || true
  elif command -v llm-manager >/dev/null 2>&1; then
    printf 'Starting local llama.cpp server...\n'
    llm-manager start llama || true
  else
    printf 'llama-swap-manager and llm-manager are unavailable. Start local server manually, then reopen this pane.\n'
  fi
}

diagnose_server() {
  local server_bin
  server_bin="${LLAMA_SERVER_BIN:-/usr/bin/llama-server}"
  if [ ! -x "$server_bin" ]; then
    server_bin="$(command -v llama-server 2>/dev/null || true)"
  fi
  if [ -n "$server_bin" ]; then
    missing="$(ldd "$server_bin" 2>/dev/null | awk '/not found/ {print "  " $1}' || true)"
    if [ -n "$missing" ]; then
      printf '\nllama-server is installed but cannot load these libraries:\n%s\n' "$missing"
      printf 'Reinstall/fix the llama.cpp package before the AI scratchpad can answer.\n'
    fi
    printf '\nllama-server devices:\n'
    "$server_bin" --list-devices 2>&1 | sed -n '1,10p' || true
  fi
  if [ -f "$HOME/.cache/kage/llm-logs/llama-swap.log" ]; then
    printf '\nLast llama-swap log lines:\n'
    tail -n 12 "$HOME/.cache/kage/llm-logs/llama-swap.log" 2>/dev/null || true
  fi
}

get_project_context() {
  if [ -x "$context_script" ]; then
    "$context_script" 2>/dev/null || echo '{}'
  else
    echo '{}'
  fi
}

format_context_system_prompt() {
  local ctx_json="$1"
  local dir branch file uncommitted
  
  dir=$(echo "$ctx_json" | jq -r '.directory // "."' 2>/dev/null || echo ".")
  branch=$(echo "$ctx_json" | jq -r '.git.branch // ""' 2>/dev/null || echo "")
  file=$(echo "$ctx_json" | jq -r '.file // ""' 2>/dev/null || echo "")
  uncommitted=$(echo "$ctx_json" | jq -r '.git.uncommitted_files // 0' 2>/dev/null || echo "0")
  
  local context_str="You are a concise local coding assistant running inside a Hyprland scratchpad."
  context_str+=" Repository: $(basename "$dir")"
  [ -n "$branch" ] && context_str+=" (branch: $branch)"
  [ "$uncommitted" -gt 0 ] && context_str+=" [$uncommitted uncommitted files]"
  [ -n "$file" ] && context_str+=" Current file: $file"
  context_str+=" Be direct, practical, and format code in markdown blocks when needed."
  
  printf '%s\n' "$context_str"
}

# Header
printf '%s\n' "╭─────────────────────────────────────────────────────────────╮"
printf '%s\n' "│           Local LLM AI Scratchpad (CUDA-enabled)           │"
printf '%s\n' "╰─────────────────────────────────────────────────────────────╯"
printf '\n'

# Check server
if ! curl -fsS --max-time 1 "$health" >/dev/null 2>&1; then
  printf '%sℹ  Local LLM server is not responding at %s%s\n' "$C_YELLOW" "$health" "$C_RESET"
  printf '%sStart it now? [Y/n]%s ' "$C_DIM" "$C_RESET"
  read -r answer
  case "${answer:-Y}" in
    y|Y|yes|YES) start_server ;;
  esac
fi

if ! curl -fsS --max-time 2 "$health" >/dev/null 2>&1; then
  printf '\n%s✗ Server still unavailable.%s\n' "$C_RED" "$C_RESET"
  diagnose_server
  exec zsh -l
fi

printf '%s✓ Server ready%s at %s\n' "$C_GREEN" "$C_RESET" "$endpoint"
printf '%sModel:%s %s\n\n' "$C_DIM" "$C_RESET" "$model"

# Get context
context_json=$(get_project_context)
context_prompt=$(format_context_system_prompt "$context_json")

printf '%sContext:%s %s\n' "$C_DIM" "$C_RESET" "$(echo "$context_json" | jq -r '.directory // "."')"
printf '%sCommands:%s /exit, /clear, /context, /help\n\n' "$C_DIM" "$C_RESET"

# History with context
history="[$(jq -n --arg content "$context_prompt" '{role:"system",content:$content}')]"

while :; do
  printf '%s%s>%s ' "$C_CYAN" "local" "$C_RESET"
  IFS= read -r prompt || break
  
  case "$prompt" in
    /exit|exit|quit)
      printf '%s← Goodbye%s\n' "$C_DIM" "$C_RESET"
      break
      ;;
    /clear)
      history="[$(jq -n --arg content "$context_prompt" '{role:"system",content:$content}')]"
      printf '%s✓ Context cleared%s\n' "$C_GREEN" "$C_RESET"
      continue
      ;;
    /context)
      printf '%s%s%s\n' "$C_BOLD" "$context_prompt" "$C_RESET"
      continue
      ;;
    /help)
      printf '%sAvailable commands:%s\n' "$C_BOLD" "$C_RESET"
      printf '  %s/exit%s — Close the AI scratchpad\n' "$C_DIM" "$C_RESET"
      printf '  %s/clear%s — Reset conversation context\n' "$C_DIM" "$C_RESET"
      printf '  %s/context%s — Show current project context\n' "$C_DIM" "$C_RESET"
      printf '  %s/help%s — Show this help\n' "$C_DIM" "$C_RESET"
      continue
      ;;
    '') continue ;;
  esac

  # Build request
  history="$(jq --arg content "$prompt" '. + [{role:"user",content:$content}]' <<<"$history")"
  payload="$(jq -n --arg model "$model" --argjson messages "$history" \
    '{model:$model,messages:$messages,temperature:0.3,stream:false}')"

  # Call API
  printf '%s⟳ Thinking...%s' "$C_YELLOW" "$C_RESET"
  response="$(curl -fsS --max-time 120 "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>/tmp/noxflow-llm-error.$$ || true)"

  if [ -z "$response" ]; then
    printf '\r%s✗ Request failed%s\n' "$C_RED" "$C_RESET"
    sed -n '1,8p' /tmp/noxflow-llm-error.$$ 2>/dev/null || true
    rm -f /tmp/noxflow-llm-error.$$
    continue
  fi
  rm -f /tmp/noxflow-llm-error.$$

  answer="$(jq -r '.choices[0].message.content // .content // empty' <<<"$response")"
  if [ -z "$answer" ]; then
    printf '\r%s✗ Unexpected response%s\n' "$C_RED" "$C_RESET"
    printf '%s%s%s\n' "$C_DIM" "$response" "$C_RESET"
    continue
  fi

  # Format response
  printf '\r%s%s%s\n' "$C_RESET" "$answer" "$C_RESET"
  msg_count=$((msg_count + 1))

  # Keep last 16 messages + system prompt to avoid token bloat
  history="$(jq --arg content "$answer" \
    '. + [{role:"assistant",content:$content}] | if length > 17 then [.[0]] + .[-16:] else . end' \
    <<<"$history")"
done
