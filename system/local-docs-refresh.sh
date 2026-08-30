#!/usr/bin/env bash
set -euo pipefail

DOCS_HOME="${OPENCODE_LOCAL_DOCS_HOME:-$HOME/.local/share/opencode/local-docs}"
PYTHON_BIN="$DOCS_HOME/.venv/bin/python"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$PYTHON_BIN" ]; then
  printf 'NOT_CONFIGURED: install OpenCode MCP dependencies first\n' >&2
  exit 0
fi

timeout "${LOCAL_DOCS_REFRESH_TIMEOUT:-900}" "$PYTHON_BIN" "$SCRIPT_DIR/local_docs_cache.py" refresh
