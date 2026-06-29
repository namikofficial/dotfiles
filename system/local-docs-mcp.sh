#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
VENV="${RAG_HOME}/.venv"

if [ ! -x "${VENV}/bin/python" ]; then
  printf 'RAG venv not ready. Run: %s/setup/install-local-rag-stack.sh\n' "$REPO_DIR" >&2
  exit 1
fi

exec "${VENV}/bin/python" "${SCRIPT_DIR}/local_docs_cache.py" mcp "$@"
