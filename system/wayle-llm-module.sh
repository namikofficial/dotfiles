#!/usr/bin/env bash
# Wayle custom module: LLM Status
# Shows: running model, tokens/sec, current log lines
# Updates every 5 seconds

set -euo pipefail

LOGS_DIR="${HOME}/.cache/kage/llm-logs"
CACHE_FILE="/tmp/wayle-llm-status.json"

get_llm_status() {
  local status_json="{}"
  
  # Check if server is running
  if curl -s http://127.0.0.1:8000/v1/models >/dev/null 2>&1; then
    local model=$(curl -s http://127.0.0.1:8000/v1/models 2>/dev/null | jq -r '.data[0].id // "unknown"' || echo "unknown")
    status_json=$(jq -n \
      --arg running "true" \
      --arg model "$model" \
      --arg port "8000" \
      '{running: $running, model: $model, port: $port}')
  else
    status_json='{"running":"false"}'
  fi
  
  # Get recent log lines
  if [ -f "${LOGS_DIR}/llm.log" ]; then
    local recent_log=$(tail -3 "${LOGS_DIR}/llm.log" 2>/dev/null | tr '\n' ' ' | cut -c 1-100)
    status_json=$(echo "$status_json" | jq --arg log "$recent_log" '.log = $log')
  fi
  
  echo "$status_json"
}

# Output for Wayle (JSON format)
STATUS=$(get_llm_status)
echo "$STATUS" > "$CACHE_FILE"

# Format for display
RUNNING=$(echo "$STATUS" | jq -r '.running')
MODEL=$(echo "$STATUS" | jq -r '.model // "none"')
LOG=$(echo "$STATUS" | jq -r '.log // ""')

if [ "$RUNNING" = "true" ]; then
  printf '{"text":"🤖 LLM: %s","tooltip":"Model: %s\\nLogs: %s"}' "$MODEL" "$MODEL" "$LOG"
else
  printf '{"text":"🤖 Offline","tooltip":"LLM server not running\\nStart: llm-manager start gemma"}'
fi
