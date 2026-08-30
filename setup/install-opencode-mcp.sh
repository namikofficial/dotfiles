#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MCP_HOME="${OPENCODE_MCP_HOME:-$HOME/.local/share/opencode/mcp}"
DOCS_HOME="${OPENCODE_LOCAL_DOCS_HOME:-$HOME/.local/share/opencode/local-docs}"

command -v npm >/dev/null 2>&1 || {
  echo "npm is required" >&2
  exit 1
}
command -v uv >/dev/null 2>&1 || {
  echo "uv is required" >&2
  exit 1
}

mkdir -p "$MCP_HOME" "$DOCS_HOME"
install -m 0644 "$REPO_DIR/configs/opencode/mcp-runtime-package.json" "$MCP_HOME/package.json"
npm install --prefix "$MCP_HOME" --no-audit --no-fund

if [ ! -x "$DOCS_HOME/.venv/bin/python" ]; then
  uv venv --python 3.12 "$DOCS_HOME/.venv"
fi
uv pip install --python "$DOCS_HOME/.venv/bin/python" 'mcp>=1,<2'
uv tool install --force mcp-server-git

printf 'OpenCode MCP dependencies installed.\n'
printf 'Node MCP root: %s\n' "$MCP_HOME"
printf 'Local docs venv: %s\n' "$DOCS_HOME/.venv"
