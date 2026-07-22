#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${AI_WORKBENCH_DIR:-$HOME/Documents/code/ai}"
NODE_BIN="${AI_NODE_BIN:-$(command -v node || true)}"

if [ ! -f "$REPO_DIR/mcp/server/src/main.ts" ]; then
  printf 'Workbench MCP source is missing: %s\n' "$REPO_DIR/mcp/server/src/main.ts" >&2
  exit 1
fi

if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ]; then
  printf 'Node.js is required to run Workbench MCP.\n' >&2
  exit 1
fi

STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export AI_RUNTIME_DIR="${AI_RUNTIME_DIR:-$STATE_HOME/ai-workbench/runtime}"
export AI_DATABASE_PATH="${AI_DATABASE_PATH:-$AI_RUNTIME_DIR/ai.db}"
export AI_API_URL="${AI_API_URL:-http://127.0.0.1:4417}"

exec "$NODE_BIN" --experimental-strip-types "$REPO_DIR/mcp/server/src/main.ts" "$@"
