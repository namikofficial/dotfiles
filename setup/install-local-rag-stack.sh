#!/usr/bin/env bash
set -euo pipefail

RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
VENV="${RAG_HOME}/.venv"
QDRANT_CONTAINER="${RAG_QDRANT_CONTAINER:-qdrant}"
CONFIG_FILE="${RAG_HOME}/config.json"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1" >&2
    exit 1
  }
}

need_cmd python
need_cmd docker

mkdir -p "$RAG_HOME/qdrant_storage" "$HOME/.local/bin"

if [ ! -d "$VENV" ]; then
  python -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV/bin/pip" install \
  qdrant-client \
  fastembed \
  rich \
  watchdog \
  pathspec \
  gitignore-parser >/dev/null

if [ ! -f "$CONFIG_FILE" ]; then
  cat >"$CONFIG_FILE" <<EOF
{
  "qdrant_url": "http://127.0.0.1:6333",
  "qdrant_collection": "local-rag-chunks",
  "answer_url": "http://127.0.0.1:8080/v1/chat/completions",
  "answer_model": "local",
  "embedding_model": "BAAI/bge-small-en-v1.5",
  "retrieval_context_tokens": 12000,
  "answer_max_tokens": 2500
}
EOF
fi

if ! docker info >/dev/null 2>&1; then
  printf 'Docker daemon is not reachable. Start Docker, then rerun this script.\n' >&2
  exit 1
fi

if docker ps --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
  :
elif docker ps -a --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
  docker start "$QDRANT_CONTAINER" >/dev/null
else
  docker run -d \
    --name "$QDRANT_CONTAINER" \
    -p 6333:6333 \
    -v "${RAG_HOME}/qdrant_storage:/qdrant/storage" \
    qdrant/qdrant >/dev/null
fi

ln -sfn "$HOME/Documents/code/dotfiles/system/rag.sh" "$HOME/.local/bin/rag"

printf 'RAG stack is ready.\n'
printf 'Config: %s\n' "$CONFIG_FILE"
printf 'CLI: %s\n' "$HOME/.local/bin/rag"
printf 'Qdrant: http://127.0.0.1:6333\n'
printf '\nSuggested next steps:\n'
printf '  rag doctor\n'
printf '  rag index %s\n' "$HOME/Documents/code/dotfiles"
printf '  rag search "scratchpad manager"\n'
