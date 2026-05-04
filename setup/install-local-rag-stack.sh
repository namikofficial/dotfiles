#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
VENV="${RAG_HOME}/.venv"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
QDRANT_CONTAINER="${RAG_QDRANT_CONTAINER:-qdrant}"
CONFIG_FILE="${RAG_HOME}/config.json"
REQUIREMENTS_FILE="${REPO_DIR}/system/rag-requirements.txt"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1" >&2
    exit 1
  }
}

need_cmd python
if ! command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1; then
  printf 'Missing container runtime: %s\n' "$CONTAINER_RUNTIME" >&2
  if [ "$CONTAINER_RUNTIME" = "docker" ]; then
    printf 'Docker is required for the default Qdrant setup.\n' >&2
    printf 'Alternative: CONTAINER_RUNTIME=podman %s\n' "$0" >&2
  fi
  exit 1
fi

mkdir -p "$RAG_HOME/qdrant_storage" "$HOME/.local/bin"

if [ ! -d "$VENV" ]; then
  python -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV/bin/pip" install -r "$REQUIREMENTS_FILE" >/dev/null

"$VENV/bin/python" - <<PY
import json
from pathlib import Path

config_path = Path(${CONFIG_FILE@Q})
defaults = {
    "qdrant_url": "http://127.0.0.1:6333",
    "qdrant_collection": "local-rag-chunks",
    "answer_url": "http://127.0.0.1:8080/v1/chat/completions",
    "answer_model": "local",
    "embedding_model": "BAAI/bge-small-en-v1.5",
    "retrieval_context_tokens": 12000,
    "answer_max_tokens": 2500,
    "key_aliases": {
        "ctrl": "CTRL",
        "control": "CTRL",
    },
    "reranker": {
        "enabled": True,
        "mode": "heuristic",
        "top_k_input": 30,
        "top_k_output": 12,
        "content_weight": 0.03,
        "path_weight": 0.02,
        "symbol_weight": 0.02,
    },
    "retrieval": {
        "max_chunks_per_file": 3,
        "max_fact_files": 8,
        "max_summary_files": 8,
    },
    "context_budget": {
        "total_tokens": 12000,
        "memory_tokens": 1800,
        "facts_tokens": 1800,
        "file_summary_tokens": 2200,
        "chunk_tokens": 6000,
        "reserved_answer_tokens": 2200,
    },
    "indexing": {
        "profile": "balanced",
    },
    "index_profiles": {
        "fast": {
            "facts": True,
            "file_summaries": False,
            "repo_memory": False,
        },
        "balanced": {
            "facts": True,
            "file_summaries": True,
            "repo_memory": False,
        },
        "deep": {
            "facts": True,
            "file_summaries": True,
            "repo_memory": True,
        },
    },
}

def merge(base, override):
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge(merged[key], value)
        else:
            merged[key] = value
    return merged

current = {}
if config_path.exists():
    current = json.loads(config_path.read_text())
config_path.write_text(json.dumps(merge(defaults, current), indent=2) + "\\n")
PY

if ! "$CONTAINER_RUNTIME" info >/dev/null 2>&1; then
  printf '%s daemon is not reachable. Start it, then rerun this script.\n' "$CONTAINER_RUNTIME" >&2
  if [ "$CONTAINER_RUNTIME" = "docker" ]; then
    printf 'Alternative: CONTAINER_RUNTIME=podman %s\n' "$0" >&2
  fi
  exit 1
fi

if "$CONTAINER_RUNTIME" ps --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
  :
elif "$CONTAINER_RUNTIME" ps -a --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
  "$CONTAINER_RUNTIME" start "$QDRANT_CONTAINER" >/dev/null
else
  "$CONTAINER_RUNTIME" run -d \
    --name "$QDRANT_CONTAINER" \
    -p 6333:6333 \
    -v "${RAG_HOME}/qdrant_storage:/qdrant/storage" \
    qdrant/qdrant >/dev/null
fi

ln -sfn "$REPO_DIR/system/rag.sh" "$HOME/.local/bin/rag"

printf 'Local RAG stack is ready.\n\n'
printf 'Paths:\n'
printf '  Config:  %s\n' "$CONFIG_FILE"
printf '  CLI:     %s\n' "$HOME/.local/bin/rag"
printf '  SQLite:  %s\n' "${RAG_HOME}/rag.sqlite3"
printf '  Qdrant:  http://127.0.0.1:6333\n'
printf '  Storage: %s\n' "${RAG_HOME}/qdrant_storage"
printf '  Rerank:  enabled by default on this machine\n'
printf '\nVerify:\n'
printf '  rag doctor\n'
printf '\nIndex this repo:\n'
printf '  cd %s && rag index\n' "$REPO_DIR"
printf '\nTry search:\n'
printf '  rag search "scratchpad manager"\n'
printf '\nAsk with retrieved context:\n'
printf '  rag ask "how does the scratchpad manager choose the AI terminal?"\n'
printf '\nMaintenance:\n'
printf '  rag reindex\n'
printf '  rag status\n'
