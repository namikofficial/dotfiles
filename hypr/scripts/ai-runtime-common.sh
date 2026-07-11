#!/usr/bin/env bash
set -euo pipefail

AI_LLM_BASE_URL="${LLM_BASE_URL:-http://127.0.0.1:8080/v1}"
AI_HEALTH_ENDPOINT="${LLM_HEALTH_ENDPOINT:-${AI_LLM_BASE_URL}/models}"
AI_DEFAULT_MODEL="${LLM_CHAT_MODEL:-local}"

ai_need_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

ai_remote_models() {
  curl -fsS --max-time 2 "$AI_HEALTH_ENDPOINT" | jq -r '.data[].id // empty' 2>/dev/null || true
}

ai_select_model() {
  local requested="${1:-${NOXFLOW_AI_MODEL:-$AI_DEFAULT_MODEL}}"
  local model preferred
  local available=()

  mapfile -t available < <(ai_remote_models)
  [ "${#available[@]}" -gt 0 ] || return 1

  if [ -n "$requested" ]; then
    for model in "${available[@]}"; do
      [ "$model" = "$requested" ] && printf '%s\n' "$model" && return 0
    done
  fi

  for preferred in local qwen3-4b-local granite-agent; do
    for model in "${available[@]}"; do
      [ "$model" = "$preferred" ] && printf '%s\n' "$model" && return 0
    done
  done

  printf '%s\n' "${available[0]}"
}

ai_start_server() {
  if command -v llama-swap-manager >/dev/null 2>&1; then
    llama-swap-manager start
  fi
}

ai_ensure_server() {
  local auto_start="${1:-1}"
  if curl -fsS --max-time 1 "$AI_HEALTH_ENDPOINT" >/dev/null 2>&1; then
    return 0
  fi

  if [ "$auto_start" = "1" ]; then
    ai_start_server
    sleep 1
  fi

  curl -fsS --max-time 2 "$AI_HEALTH_ENDPOINT" >/dev/null 2>&1
}
