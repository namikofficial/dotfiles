#!/usr/bin/env bash
# local-llm-chat-enhanced.sh
# Improved AI scratchpad with project context, better formatting, and command support

set -euo pipefail
AI_COMMON="${HOME}/.config/hypr/scripts/ai-runtime-common.sh"
if [ -r "$AI_COMMON" ]; then
  # shellcheck disable=SC1090
  . "$AI_COMMON"
fi

# Colors
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_GREEN='\033[32m'
C_CYAN='\033[36m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_RESET='\033[0m'

endpoint="${LLM_CHAT_ENDPOINT:-${AI_LLM_BASE_URL:-http://127.0.0.1:8080/v1}/chat/completions}"
health="${LLM_HEALTH_ENDPOINT:-${AI_HEALTH_ENDPOINT:-http://127.0.0.1:8080/v1/models}}"
model="${LLM_CHAT_MODEL:-local}"
prompt_builder="${HOME}/.config/hypr/scripts/ai-helper-context.sh"
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
  command -v ai_start_server >/dev/null 2>&1 && ai_start_server && return 0
  command -v llama-swap-manager >/dev/null 2>&1 && llama-swap-manager start >/dev/null 2>&1 || true
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

fallback_context_dir() {
  local dir="${AI_WORKBENCH_PROJECT_PATH:-${NOXFLOW_AI_CONTEXT:-$PWD}}"
  if [ -d "$dir" ]; then
    cd "$dir" 2>/dev/null && pwd -P
  else
    pwd -P
  fi
}

fallback_context_system_prompt() {
  local dir
  dir="$(fallback_context_dir)"
  printf 'You are a concise local coding assistant running inside a Hyprland scratchpad. Workspace: %s.' "$dir"
  [ -n "${AI_WORKBENCH_PROJECT_ID:-}" ] && printf ' Workbench project ID: %s.' "$AI_WORKBENCH_PROJECT_ID"
  [ -n "${AI_WORKBENCH_SESSION_ID:-}" ] && printf ' Shared session ID: %s.' "$AI_WORKBENCH_SESSION_ID"
  printf ' Canonical project status is unavailable; do not infer branch, task, or repository state. Be direct, practical, and format code in markdown blocks when needed.\n'
}

fallback_context_summary() {
  local dir
  dir="$(fallback_context_dir)"
  printf 'Workspace: %s | Workbench context unavailable (directory-only fallback)\n' "$dir"
}

refresh_context() {
  if [ -x "$prompt_builder" ]; then
    context_prompt="$("$prompt_builder" prompt scratchpad 2>/dev/null || true)"
    context_summary="$("$prompt_builder" summary 2>/dev/null || true)"
  else
    context_prompt=""
    context_summary=""
  fi

  [ -n "$context_prompt" ] || context_prompt="$(fallback_context_system_prompt)"
  [ -n "$context_summary" ] || context_summary="$(fallback_context_summary)"
}

trim_history() {
  history="$(jq '
    def cap($n): if (.content|length) > $n then .content = (.content[0:$n]) else . end;
    [.[0]] + ((.[1:] | map(cap(3000)))[-14:] // [])
  ' <<<"$history")"
}

list_models() {
  if command -v ai_remote_models >/dev/null 2>&1; then
    ai_remote_models
  else
    curl -fsS --max-time 2 "$health" | jq -r '.data[].id // empty' 2>/dev/null || true
  fi
}

print_health() {
  if curl -fsS --max-time 2 "$health" >/dev/null 2>&1; then
    printf '%s✓ healthy%s %s\n' "$C_GREEN" "$C_RESET" "$health"
  else
    printf '%s✗ unavailable%s %s\n' "$C_RED" "$C_RESET" "$health"
  fi
}

# Header
printf '%s\n' "╭─────────────────────────────────────────────────────────────╮"
printf '%s\n' "│           Local LLM AI Scratchpad (CUDA-enabled)           │"
printf '%s\n' "╰─────────────────────────────────────────────────────────────╯"
printf '\n'

# Check server
if ! curl -fsS --max-time 1 "$health" >/dev/null 2>&1; then
  printf '%sℹ  Local LLM server is not responding; starting runtime...%s\n' "$C_YELLOW" "$C_RESET"
  start_server
fi

if ! curl -fsS --max-time 2 "$health" >/dev/null 2>&1; then
  printf '\n%s✗ Server still unavailable.%s\n' "$C_RED" "$C_RESET"
  diagnose_server
  exec zsh -l
fi

printf '%s✓ Server ready%s at %s\n' "$C_GREEN" "$C_RESET" "$endpoint"
printf '%sModel:%s %s\n\n' "$C_DIM" "$C_RESET" "$model"

# Get context
refresh_context

printf '%sContext:%s\n%s\n' "$C_DIM" "$C_RESET" "$context_summary"
printf '%sCommands:%s /exit, /clear, /context, /ctx, /models, /model <name>, /health, /retry, /help\n\n' "$C_DIM" "$C_RESET"

# History with context
history="[$(jq -n --arg content "$context_prompt" '{role:"system",content:$content}')]"

while :; do
  printf '%s%s>%s ' "$C_CYAN" "local" "$C_RESET"
  IFS= read -r prompt || break

  case "$prompt" in
    /exit | exit | quit)
      printf '%s← Goodbye%s\n' "$C_DIM" "$C_RESET"
      break
      ;;
    /clear)
      refresh_context
      history="[$(jq -n --arg content "$context_prompt" '{role:"system",content:$content}')]"
      printf '%s✓ Context cleared%s\n' "$C_GREEN" "$C_RESET"
      continue
      ;;
    /context | /ctx)
      refresh_context
      printf '%s%s%s\n' "$C_BOLD" "$context_summary" "$C_RESET"
      continue
      ;;
    /models)
      printf '%sAvailable models:%s\n' "$C_BOLD" "$C_RESET"
      list_models | sed 's/^/  - /'
      continue
      ;;
    /health)
      print_health
      continue
      ;;
    /retry)
      start_server
      print_health
      continue
      ;;
    '/model '*)
      requested_model="${prompt#/model }"
      if [ -z "$requested_model" ]; then
        printf '%sUsage:%s /model <name>\n' "$C_YELLOW" "$C_RESET"
        continue
      fi
      model="$requested_model"
      printf '%s✓ Model set%s %s\n' "$C_GREEN" "$C_RESET" "$model"
      continue
      ;;
    /help)
      printf '%sAvailable commands:%s\n' "$C_BOLD" "$C_RESET"
      printf '  %s/exit%s — Close the AI scratchpad\n' "$C_DIM" "$C_RESET"
      printf '  %s/clear%s — Reset conversation context\n' "$C_DIM" "$C_RESET"
      printf '  %s/context%s | %s/ctx%s — Show current project context\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
      printf '  %s/models%s — List available local models\n' "$C_DIM" "$C_RESET"
      printf '  %s/model <name>%s — Switch active model\n' "$C_DIM" "$C_RESET"
      printf '  %s/health%s — Check local runtime health\n' "$C_DIM" "$C_RESET"
      printf '  %s/retry%s — Restart local runtime and recheck\n' "$C_DIM" "$C_RESET"
      printf '  %s/help%s — Show this help\n' "$C_DIM" "$C_RESET"
      continue
      ;;
    '') continue ;;
  esac

  # Build request
  history="$(jq --arg content "$prompt" '. + [{role:"user",content:$content}]' <<<"$history")"
  trim_history
  payload="$(jq -n --arg model "$model" --argjson messages "$history" \
    '{model:$model,messages:$messages,temperature:0.3,stream:true}')"

  # Call API
  printf '%s⟳ Thinking...%s' "$C_YELLOW" "$C_RESET"
  curl_rc=0
  response="$(curl -fsS --max-time 120 -N "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>&1)" || curl_rc=$?

  if [ "${curl_rc:-0}" -ne 0 ] || [ -z "$response" ]; then
    printf '\r%s✗ Request failed%s\n' "$C_RED" "$C_RESET"
    printf '%s\n' "$response" | sed -n '1,8p'
    continue
  fi

  answer="$(printf '%s\n' "$response" | awk '
    /^data: /{
      line=substr($0,7);
      if (line=="[DONE]") next;
      print line;
    }' | jq -r '.choices[0].delta.content // .choices[0].message.content // empty' 2>/dev/null | tr -d "\r" | paste -sd "" -)"
  if [ -z "$answer" ]; then
    answer="$(jq -r '.choices[0].message.content // .content // empty' <<<"$response")"
  fi
  if [ -z "$answer" ]; then
    printf '\r%s✗ Unexpected response%s\n' "$C_RED" "$C_RESET"
    printf '%s%s%s\n' "$C_DIM" "$response" "$C_RESET"
    continue
  fi

  # Format response
  printf '\r%s%s%s\n' "$C_RESET" "$answer" "$C_RESET"
  msg_count=$((msg_count + 1))

  # Keep last 16 messages + system prompt to avoid token bloat
  history="$(jq --arg content "$answer" '. + [{role:"assistant",content:$content}]' <<<"$history")"
  trim_history
done
