#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
WEBUI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/open-webui"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1" >&2
    exit 1
  }
}

need_cmd bash
need_cmd docker
need_cmd python

mkdir -p "$RAG_HOME" "$WEBUI_DIR"

if [ ! -d "$RAG_HOME/.venv" ]; then
  printf 'Bootstrapping local RAG stack in %s\n' "$RAG_HOME"
  "$REPO_DIR/setup/install-local-rag-stack.sh"
else
  printf 'RAG venv already present: %s/.venv\n' "$RAG_HOME"
fi

printf 'Bootstrapping Open WebUI stack in %s\n' "$WEBUI_DIR"
"$REPO_DIR/setup/install-open-webui-stack.sh"

printf '\nBootstrap complete.\n'
printf 'Next:\n'
printf '  cd %s && docker compose --env-file .env up -d\n' "$WEBUI_DIR"
printf '  local-ai-runtime start\n'
printf '  rag doctor\n'
printf '  %s/setup/test-open-webui-stack.sh\n' "$REPO_DIR"
