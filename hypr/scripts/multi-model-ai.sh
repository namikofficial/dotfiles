#!/usr/bin/env bash
# Open a project-rooted AI shell with the local llama-swap/OpenCode config ready.

set -euo pipefail

LLM_BASE_URL="${LLM_BASE_URL:-http://127.0.0.1:8080/v1}"
HEALTH_ENDPOINT="${LLM_HEALTH_ENDPOINT:-${LLM_BASE_URL}/models}"
OPENCODE_TEMPLATE="${HOME}/Documents/code/dotfiles/configs/opencode/opencode.local-llamacpp.json"
OPENCODE_RUNTIME_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_RUNTIME_CONFIG="${OPENCODE_RUNTIME_DIR}/opencode.json"
AI_CONTEXT="${NOXFLOW_AI_CONTEXT:-$PWD}"

C_BOLD='\033[1m'
C_DIM='\033[2m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_RESET='\033[0m'

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf '%sMissing command:%s %s\n' "$C_RED" "$C_RESET" "$1"
    exec zsh -li
  }
}

choose_context_dir() {
  if [ -n "${AI_CONTEXT:-}" ] && [ -d "$AI_CONTEXT" ]; then
    printf '%s\n' "$AI_CONTEXT"
    return 0
  fi
  if [ -d "$HOME/Documents/code" ]; then
    printf '%s\n' "$HOME/Documents/code"
    return 0
  fi
  printf '%s\n' "$HOME"
}

remote_models() {
  curl -fsS --max-time 2 "$HEALTH_ENDPOINT" | jq -r '.data[].id // empty' 2>/dev/null || true
}

select_model() {
  local requested="${NOXFLOW_AI_MODEL:-${LLM_CHAT_MODEL:-}}"
  local available preferred model
  mapfile -t available < <(remote_models)

  if [ "${#available[@]}" -eq 0 ]; then
    return 1
  fi

  if [ -n "$requested" ]; then
    for model in "${available[@]}"; do
      if [ "$model" = "$requested" ]; then
        printf '%s\n' "$model"
        return 0
      fi
    done
  fi

  for preferred in gemma-3-4b local gemma-2-2b llama-3-8b; do
    for model in "${available[@]}"; do
      if [ "$model" = "$preferred" ]; then
        printf '%s\n' "$model"
        return 0
      fi
    done
  done

  printf '%s\n' "${available[0]}"
}

ensure_server() {
  if curl -fsS --max-time 1 "$HEALTH_ENDPOINT" >/dev/null 2>&1; then
    return 0
  fi

  printf '%sLocal LLM server is not responding at %s%s\n' "$C_YELLOW" "$HEALTH_ENDPOINT" "$C_RESET"
  printf '%sStart llama-swap-manager now? [Y/n]%s ' "$C_DIM" "$C_RESET"
  read -r answer

  case "${answer:-Y}" in
    y|Y|yes|YES)
      if command -v llama-swap-manager >/dev/null 2>&1; then
        printf '%sStarting local endpoint...%s\n' "$C_YELLOW" "$C_RESET"
        llama-swap-manager start || true
        sleep 2
      fi
      ;;
  esac

  curl -fsS --max-time 2 "$HEALTH_ENDPOINT" >/dev/null 2>&1
}

ensure_opencode_config() {
  mkdir -p "$OPENCODE_RUNTIME_DIR"
  [ -f "$OPENCODE_TEMPLATE" ] || return 1
  ln -sfn "$OPENCODE_TEMPLATE" "$OPENCODE_RUNTIME_CONFIG"
}

opencode_bin() {
  if command -v opencode >/dev/null 2>&1; then
    printf 'opencode\n'
    return 0
  fi
  if command -v opencode-cli >/dev/null 2>&1; then
    printf 'opencode-cli\n'
    return 0
  fi
  return 1
}

load_opencode_mcp_env() {
  local mcp_file="${HOME}/.copilot/mcp.json"
  command -v jq >/dev/null 2>&1 || return 0

  local obsidian_rest_config="${HOME}/Documents/notes/namikBrain/.obsidian/plugins/obsidian-local-rest-api/data.json"
  local value
  if [ -f "$obsidian_rest_config" ]; then
    value="$(jq -r '.apiKey // empty' "$obsidian_rest_config" 2>/dev/null || true)"
    [ -n "$value" ] && export OBSIDIAN_API_KEY="${OBSIDIAN_API_KEY:-$value}"

    local insecure_enabled insecure_port secure_port
    insecure_enabled="$(jq -r '.enableInsecureServer // false' "$obsidian_rest_config" 2>/dev/null || true)"
    insecure_port="$(jq -r '.insecurePort // 27123' "$obsidian_rest_config" 2>/dev/null || true)"
    secure_port="$(jq -r '.port // 27124' "$obsidian_rest_config" 2>/dev/null || true)"
    if [ "$insecure_enabled" = "true" ]; then
      export OBSIDIAN_BASE_URL="${OBSIDIAN_BASE_URL:-http://127.0.0.1:${insecure_port}}"
      export OBSIDIAN_VERIFY_SSL="${OBSIDIAN_VERIFY_SSL:-false}"
    else
      export OBSIDIAN_BASE_URL="${OBSIDIAN_BASE_URL:-https://127.0.0.1:${secure_port}}"
      export OBSIDIAN_VERIFY_SSL="${OBSIDIAN_VERIFY_SSL:-false}"
    fi
    export OBSIDIAN_ENABLE_CACHE="${OBSIDIAN_ENABLE_CACHE:-false}"
  fi

  [ -f "$mcp_file" ] || return 0
  if [ -z "${OBSIDIAN_VAULT_PATH:-}" ]; then
    value="$(jq -r '.mcpServers.obsidian.env.OBSIDIAN_VAULT_PATH // empty' "$mcp_file" 2>/dev/null || true)"
    [ -n "$value" ] && export OBSIDIAN_VAULT_PATH="$value"
  fi
}

launch_opencode() {
  local model="$1" context="$2" bin
  bin="$(opencode_bin)" || return 1

  ensure_opencode_config || {
    printf '%sOpenCode config template is missing: %s%s\n' "$C_RED" "$OPENCODE_TEMPLATE" "$C_RESET"
    return 1
  }

  printf '%sLaunching OpenCode%s in %s\n' "$C_GREEN" "$C_RESET" "$context"
  printf '%sProvider:%s llamacpp/%s\n\n' "$C_DIM" "$C_RESET" "$model"
  "$bin" "$context" --model "llamacpp/$model"
}

launch_enhanced_chat() {
  local model="$1" context="$2"
  printf '%sFalling back to local chat scratchpad%s\n' "$C_YELLOW" "$C_RESET"
  export LLM_CHAT_MODEL="$model"
  cd "$context"
  exec "$HOME/.config/hypr/scripts/local-llm-chat-enhanced.sh"
}

need_cmd curl
need_cmd jq

context_dir="$(choose_context_dir)"
cd "$context_dir"

printf '%s\n' "╔════════════════════════════════════════════════════════════════╗"
printf '%s\n' "║                  Local AI Workspace Shell                     ║"
printf '%s\n' "╚════════════════════════════════════════════════════════════════╝"
printf '\n'

if ! ensure_server; then
  printf '%sServer is still unavailable. Dropping into a shell.%s\n' "$C_RED" "$C_RESET"
  exec zsh -li
fi

model="$(select_model)" || {
  printf '%sNo models are currently exposed by llama-swap.%s\n' "$C_RED" "$C_RESET"
  exec zsh -li
}

ensure_opencode_config || {
  printf '%sOpenCode config template is missing: %s%s\n' "$C_RED" "$OPENCODE_TEMPLATE" "$C_RESET"
}
load_opencode_mcp_env
export LLM_CHAT_MODEL="$model"
export OPENCODE_MODEL="${OPENCODE_MODEL:-llamacpp/$model}"
export NOXFLOW_AI_CONTEXT="$context_dir"

available_models="$(remote_models | paste -sd ',' - | sed 's/,/, /g')"
printf '%sWorkspace:%s %s\n' "$C_DIM" "$C_RESET" "$context_dir"
printf '%sModel:%s %s\n' "$C_DIM" "$C_RESET" "$model"
printf '%sAvailable:%s %s\n\n' "$C_DIM" "$C_RESET" "${available_models:-none}"

if [ "${NOXFLOW_AI_AUTOSTART:-0}" = "1" ]; then
  if launch_opencode "$model" "$context_dir"; then
    exit 0
  fi
  printf '%sOpenCode auto-start failed. Keeping an interactive shell instead.%s\n\n' "$C_YELLOW" "$C_RESET"
fi

printf '%sReady.%s Run %sopencode%s when you want the local AI agent.\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "$C_RESET"
printf '%sTip:%s you are already in the project root, and the OpenCode MCP env/config is prepared for this shell.\n\n' "$C_DIM" "$C_RESET"
exec zsh -li
