#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MCP_HOME="${OPENCODE_MCP_HOME:-$HOME/.local/share/opencode/mcp}"

command -v npm >/dev/null 2>&1 || {
  echo "npm is required" >&2
  exit 1
}

mkdir -p "$MCP_HOME"
install -m 0644 "$REPO_DIR/configs/opencode/mcp-runtime-package.json" "$MCP_HOME/package.json"
npm install --prefix "$MCP_HOME" --no-audit --no-fund

printf 'OpenCode MCP dependencies installed.\n'
printf 'Node MCP root: %s\n' "$MCP_HOME"
