#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
VENV="${RAG_HOME}/.venv"
CLI="${SCRIPT_DIR}/rag_cli.py"

if [ ! -x "${VENV}/bin/python" ]; then
  printf 'RAG environment is not installed yet.\n'
  printf 'Run: %s/setup/install-local-rag-stack.sh\n' "$REPO_DIR"
  exit 1
fi

exec "${VENV}/bin/python" "$CLI" "$@"
