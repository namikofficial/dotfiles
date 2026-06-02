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
COMPLETION_DIR="$HOME/.local/share/zsh/site-functions"
LOCAL_AI_RUNTIME_LINK="$HOME/.local/bin/local-ai-runtime"

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

mkdir -p "$RAG_HOME/qdrant_storage" "$HOME/.local/bin" "$COMPLETION_DIR"

if [ ! -d "$VENV" ]; then
  python -m venv "$VENV"
fi

"$VENV/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV/bin/pip" install -r "$REQUIREMENTS_FILE" >/dev/null

"$VENV/bin/python" - <<PY
import sys
from pathlib import Path

sys.path.insert(0, ${REPO_DIR@Q} + "/system")

from rag.settings import write_merged_config

write_merged_config(Path(${CONFIG_FILE@Q}))
PY

if ! "$CONTAINER_RUNTIME" info >/dev/null 2>&1; then
  printf '%s daemon is not reachable. Start it, then rerun this script.\n' "$CONTAINER_RUNTIME" >&2
  if [ "$CONTAINER_RUNTIME" = "docker" ]; then
    printf 'Alternative: CONTAINER_RUNTIME=podman %s\n' "$0" >&2
  fi
  exit 1
fi

if "$CONTAINER_RUNTIME" ps -a --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
  "$CONTAINER_RUNTIME" update --restart=no "$QDRANT_CONTAINER" >/dev/null
else
  "$CONTAINER_RUNTIME" create \
    --restart no \
    --name "$QDRANT_CONTAINER" \
    -p 6333:6333 \
    -v "${RAG_HOME}/qdrant_storage:/qdrant/storage" \
    qdrant/qdrant >/dev/null
fi

ln -sfn "$REPO_DIR/system/rag.sh" "$HOME/.local/bin/rag"
ln -sfn "$REPO_DIR/system/rag-mcp.sh" "$HOME/.local/bin/rag-mcp"
ln -sfn "$REPO_DIR/system/local-ai-runtime.sh" "$LOCAL_AI_RUNTIME_LINK"
ln -sfn "$REPO_DIR/system/completions/_rag" "$COMPLETION_DIR/_rag"

RAG_CONFIG_DIR="$HOME/.config/rag"
mkdir -p "$RAG_CONFIG_DIR"
if [ ! -f "$RAG_CONFIG_DIR/models.json" ]; then
  cp "$REPO_DIR/configs/rag/models.json" "$RAG_CONFIG_DIR/models.json"
fi

# Force zsh to see a newly linked completion on the next shell start.
rm -f "$HOME/.cache/zsh/.zcompdump" "$HOME/.zcompdump" 2>/dev/null || true

printf 'Local RAG stack is ready.\n\n'
printf 'Paths:\n'
printf '  Config:  %s\n' "$CONFIG_FILE"
printf '  CLI:     %s\n' "$HOME/.local/bin/rag"
printf '  MCP:     %s\n' "$HOME/.local/bin/rag-mcp"
printf '  Runtime: %s\n' "$LOCAL_AI_RUNTIME_LINK"
printf '  Zsh:     %s\n' "$COMPLETION_DIR/_rag"
printf '  SQLite:  %s\n' "${RAG_HOME}/rag.sqlite3"
printf '  Qdrant:  http://127.0.0.1:6333\n'
printf '  Storage: %s\n' "${RAG_HOME}/qdrant_storage"
printf '  Rerank:  enabled by default on this machine\n'
printf '\nVerify:\n'
printf '  local-ai-runtime status\n'
printf '  rag doctor\n'
printf '\nIndex this repo:\n'
printf '  cd %s && rag index\n' "$REPO_DIR"
printf '\nTry search:\n'
printf '  rag search "scratchpad manager"\n'
printf '\nAsk with retrieved context:\n'
printf '  rag ask "how does the scratchpad manager choose the AI terminal?"\n'
printf '\nMaintenance:\n'
printf '  local-ai-runtime stop\n'
printf '  rag reindex\n'
printf '  rag status\n'
