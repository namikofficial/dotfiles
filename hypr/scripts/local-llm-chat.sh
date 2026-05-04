#!/usr/bin/env bash
set -euo pipefail

endpoint="${LLM_CHAT_ENDPOINT:-http://127.0.0.1:8000/v1/chat/completions}"
health="${LLM_HEALTH_ENDPOINT:-http://127.0.0.1:8000/health}"
model="${LLM_CHAT_MODEL:-local}"
export LD_LIBRARY_PATH="${LLAMA_LIBRARY_PATH:-$HOME/.local/lib}:${LD_LIBRARY_PATH:-}"
export GGML_BACKEND_PATH="${LLAMA_BACKEND_PATH:-${LLAMA_LIBRARY_PATH:-$HOME/.local/lib}/libggml-cpu-x64.so}"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1"
    exec zsh -l
  }
}

need_cmd curl
need_cmd jq

start_server() {
  if command -v llm-manager >/dev/null 2>&1; then
    printf 'Starting local llama.cpp server...\n'
    llm-manager start llama || true
  else
    printf 'llm-manager is unavailable. Start llama-server manually, then reopen this pane.\n'
  fi
}

diagnose_server() {
  if command -v llama-server >/dev/null 2>&1; then
    missing="$(ldd "$(command -v llama-server)" 2>/dev/null | awk '/not found/ {print "  " $1}' || true)"
    if [ -n "$missing" ]; then
      printf '\nllama-server is installed but cannot load these shared libraries:\n%s\n' "$missing"
      printf 'Reinstall/fix the llama.cpp package before the AI scratchpad can answer.\n'
    fi
  fi
  if [ -f "$HOME/.cache/kage/llm-logs/llm.log" ]; then
    printf '\nLast llama.cpp log lines:\n'
    tail -n 12 "$HOME/.cache/kage/llm-logs/llm.log" 2>/dev/null || true
  fi
}

if ! curl -fsS --max-time 1 "$health" >/dev/null 2>&1; then
  printf 'Local LLM server is not responding at %s\n' "$health"
  printf 'Start it now? [Y/n] '
  read -r answer
  case "${answer:-Y}" in
    y|Y|yes|YES) start_server ;;
  esac
fi

if ! curl -fsS --max-time 2 "$health" >/dev/null 2>&1; then
  printf '\nServer still unavailable. Leaving an interactive shell open.\n'
  diagnose_server
  exec zsh -l
fi

printf 'Local LLM scratchpad\n'
printf 'endpoint: %s\n' "$endpoint"
printf 'type /exit to close, /clear to reset context\n\n'

history='[{"role":"system","content":"You are a concise local coding assistant running inside a Hyprland scratchpad. Be direct and practical."}]'

while :; do
  printf '\nlocal> '
  IFS= read -r prompt || break
  case "$prompt" in
    /exit|exit|quit) break ;;
    /clear)
      history='[{"role":"system","content":"You are a concise local coding assistant running inside a Hyprland scratchpad. Be direct and practical."}]'
      printf 'context cleared\n'
      continue
      ;;
    '') continue ;;
  esac

  history="$(jq --arg content "$prompt" '. + [{"role":"user","content":$content}]' <<<"$history")"
  payload="$(jq -n --arg model "$model" --argjson messages "$history" \
    '{model:$model,messages:$messages,temperature:0.3,stream:false}')"

  response="$(curl -fsS --max-time 120 "$endpoint" \
    -H 'Content-Type: application/json' \
    -d "$payload" 2>/tmp/noxflow-llm-error.$$ || true)"

  if [ -z "$response" ]; then
    printf 'request failed:\n'
    sed -n '1,8p' /tmp/noxflow-llm-error.$$ 2>/dev/null || true
    rm -f /tmp/noxflow-llm-error.$$
    continue
  fi
  rm -f /tmp/noxflow-llm-error.$$

  answer="$(jq -r '.choices[0].message.content // .content // empty' <<<"$response")"
  if [ -z "$answer" ]; then
    printf 'unexpected response:\n%s\n' "$response"
    continue
  fi

  printf '\n%s\n' "$answer"
  history="$(jq --arg content "$answer" '. + [{"role":"assistant","content":$content}] | if length > 17 then [.[0]] + .[-16:] else . end' <<<"$history")"
done
