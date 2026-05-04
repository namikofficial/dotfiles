#!/usr/bin/env bash
set -euo pipefail

RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
VENV="${RAG_HOME}/.venv"
CLI="${HOME}/Documents/code/dotfiles/system/rag_cli.py"

if [ ! -x "${VENV}/bin/python" ]; then
  printf 'RAG environment is not installed yet.\n'
  printf 'Run: %s/setup/install-local-rag-stack.sh\n' "$HOME/Documents/code/dotfiles"
  exit 1
fi

exec "${VENV}/bin/python" "$CLI" "$@"
