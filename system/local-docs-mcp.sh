#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_HOME="${OPENCODE_LOCAL_DOCS_HOME:-$HOME/.local/share/opencode/local-docs}"
PYTHON_BIN="$DOCS_HOME/.venv/bin/python"

if [ ! -x "$PYTHON_BIN" ]; then
  printf 'local-docs MCP is not installed. Run: %s/setup/install-opencode-mcp.sh\n' "$REPO_DIR" >&2
  exit 1
fi

# local-docs is independent of the retired Python RAG stack.
exec "$PYTHON_BIN" "${SCRIPT_DIR}/local_docs_cache.py" mcp "$@"
