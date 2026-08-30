#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_HOME="${OPENCODE_LOCAL_DOCS_HOME:-$HOME/.local/share/opencode/local-docs}"
VENV="${DOCS_HOME}/.venv"

if [ ! -x "${VENV}/bin/python" ]; then
  printf 'Local docs venv not ready. Run: %s/setup/install-opencode-mcp.sh\n' "$REPO_DIR" >&2
  exit 1
fi

exec "${VENV}/bin/python" "${SCRIPT_DIR}/local_docs_cache.py" "$@"
