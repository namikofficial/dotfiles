#!/usr/bin/env bash
# Wayle custom module: LLM Status
# Shows: running model, endpoint, recent log tail
# Updates every 5 seconds

set -euo pipefail

MODEL_ENV="${HOME}/.config/local-ai/current-model.env"
LOGS_DIR="${HOME}/.cache/kage/llm-logs"
CACHE_FILE="/tmp/wayle-llm-status.json"
BASE_URL="${LLM_BASE_URL:-http://127.0.0.1:8080/v1}"

# Read configured model from env file as fallback label
configured_model() {
  if [ -f "$MODEL_ENV" ]; then
    # shellcheck source=/dev/null
    source "$MODEL_ENV" 2>/dev/null || true
    echo "${LOCAL_AI_MODEL_ID:-local}"
  else
    echo "local"
  fi
}

get_llm_status() {
  local status_json="{}"

  if curl -fsS --max-time 1 "${BASE_URL}/models" >/dev/null 2>&1; then
    local model
    model=$(curl -fsS --max-time 1 "${BASE_URL}/models" 2>/dev/null |
      jq -r '.data[0].id // "local"' || echo "local")
    status_json=$(jq -n \
      --arg running "true" \
      --arg model "$model" \
      --arg port "8080" \
      '{running: $running, model: $model, port: $port}')
  else
    local cfg_model
    cfg_model=$(configured_model)
    status_json=$(jq -n --arg m "$cfg_model" '{"running":"false","configured":$m}')
  fi

  if [ -f "${LOGS_DIR}/llama-swap.log" ]; then
    local recent_log
    recent_log=$(tail -3 "${LOGS_DIR}/llama-swap.log" 2>/dev/null |
      tr '\n' ' ' | cut -c 1-100)
    status_json=$(echo "$status_json" | jq --arg log "$recent_log" '.log = $log')
  fi

  echo "$status_json"
}

STATUS=$(get_llm_status)
echo "$STATUS" >"$CACHE_FILE"

RUNNING=$(echo "$STATUS" | jq -r '.running')
MODEL=$(echo "$STATUS" | jq -r '.model // .configured // "local"')
LOG=$(echo "$STATUS" | jq -r '.log // ""')

if [ "$RUNNING" = "true" ]; then
  jq -cn --arg text " $MODEL" \
    --arg tooltip "Model: $MODEL
Endpoint: $BASE_URL
Logs: $LOG" '{text:$text, tooltip:$tooltip}'
else
  jq -cn --arg text " off ($MODEL)" \
    --arg tooltip "LLM server not running
Configured: $MODEL
Start: local-ai-runtime start" '{text:$text, tooltip:$tooltip}'
fi
