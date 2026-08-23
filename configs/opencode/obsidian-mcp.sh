#!/usr/bin/env bash
set -euo pipefail

env_file="${OBSIDIAN_ENV_FILE:-$HOME/.config/opencode/obsidian.env}"
if [ -f "$env_file" ]; then
  set -a
  # This file is user-owned and contains only Obsidian MCP environment values.
  . "$env_file"
  set +a
fi

vault_path="${OBSIDIAN_VAULT_PATH:-$HOME/Documents/notes/DocsVault}"
rest_config="${OBSIDIAN_REST_CONFIG:-$vault_path/.obsidian/plugins/obsidian-local-rest-api/data.json}"
cert_path="${OBSIDIAN_CERT_PATH:-$HOME/Documents/certs/obsidian-local-rest-api.crt}"
server_bin="${OBSIDIAN_MCP_BIN:-$HOME/.config/nvm/versions/node/v24.18.0/bin/obsidian-mcp-server}"
npx_bin="${OBSIDIAN_NPX_BIN:-$HOME/.config/nvm/versions/node/v24.18.0/bin/npx}"

if [ -f "$rest_config" ] && command -v jq >/dev/null 2>&1; then
  api_key="$(jq -r '.apiKey // empty' "$rest_config" 2>/dev/null || true)"
  insecure_enabled="$(jq -r '.enableInsecureServer // false' "$rest_config" 2>/dev/null || true)"
  insecure_port="$(jq -r '.insecurePort // 27123' "$rest_config" 2>/dev/null || true)"
  secure_port="$(jq -r '.port // 27124' "$rest_config" 2>/dev/null || true)"

  [ -n "$api_key" ] && export OBSIDIAN_API_KEY="${OBSIDIAN_API_KEY:-$api_key}"
  if [ "$insecure_enabled" = "true" ]; then
    export OBSIDIAN_BASE_URL="${OBSIDIAN_BASE_URL:-http://127.0.0.1:${insecure_port}}"
    export OBSIDIAN_VERIFY_SSL="${OBSIDIAN_VERIFY_SSL:-false}"
  else
    export OBSIDIAN_BASE_URL="${OBSIDIAN_BASE_URL:-https://127.0.0.1:${secure_port}}"
    export OBSIDIAN_VERIFY_SSL="${OBSIDIAN_VERIFY_SSL:-true}"
  fi
fi

export OBSIDIAN_ENABLE_CACHE="${OBSIDIAN_ENABLE_CACHE:-false}"
export OBSIDIAN_VAULT_PATH="$vault_path"
export VAULT_PATH="$vault_path"
export MCP_TRANSPORT_TYPE="${MCP_TRANSPORT_TYPE:-stdio}"

if [ -f "$cert_path" ]; then
  export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-$cert_path}"
fi

if [ -x "$server_bin" ]; then
  exec "$server_bin"
fi

if [ -x "$npx_bin" ]; then
  exec "$npx_bin" -y obsidian-mcp-server
fi

exec npx -y obsidian-mcp-server
