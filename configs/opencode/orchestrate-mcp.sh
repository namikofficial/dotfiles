#!/usr/bin/env bash
set -euo pipefail

mcp_home="${OPENCODE_MCP_HOME:-$HOME/.local/share/opencode/mcp}"
server_bin="${MCP_ORCHESTRATE_BIN:-$mcp_home/node_modules/.bin/mcp-orchestrate}"

if [ ! -x "$server_bin" ]; then
  printf 'mcp-orchestrate is not installed at %s; run setup/install-opencode-mcp.sh\n' "$server_bin" >&2
  exit 127
fi

exec "$server_bin" "$@"
