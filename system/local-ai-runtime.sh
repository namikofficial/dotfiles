#!/usr/bin/env bash
set -euo pipefail

SOURCE_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SOURCE_PATH")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RAG_HOME="${RAG_HOME:-$HOME/ai-rag}"
CONFIG_FILE="${RAG_CONFIG_FILE:-$RAG_HOME/config.json}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/noxflow"
CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
QDRANT_CONTAINER="${RAG_QDRANT_CONTAINER:-qdrant}"
QDRANT_IMAGE="${RAG_QDRANT_IMAGE:-qdrant/qdrant}"
QDRANT_STORAGE_DIR="${RAG_QDRANT_STORAGE_DIR:-$RAG_HOME/qdrant_storage}"
DEFAULT_QDRANT_URL="${RAG_QDRANT_URL:-http://127.0.0.1:6333}"
DEFAULT_ANSWER_URL="${RAG_ANSWER_URL:-http://127.0.0.1:8080/v1/chat/completions}"
DEFAULT_ANSWER_MODEL="${RAG_ANSWER_MODEL:-gemma-3-4b}"

mkdir -p "$RUNTIME_DIR" "$QDRANT_STORAGE_DIR"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1" >&2
    exit 1
  }
}

config_value() {
  local key="$1" default="$2"
  python - "$CONFIG_FILE" "$key" "$default" <<'PY'
import json
import sys
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
key = sys.argv[2]
default = sys.argv[3]

try:
    payload = json.loads(config_path.read_text()) if config_path.exists() else {}
except json.JSONDecodeError:
    payload = {}

value = payload.get(key, default)
if isinstance(value, (dict, list)):
    print(json.dumps(value))
else:
    print(value)
PY
}

models_url() {
  python - "$1" <<'PY'
import sys

print(sys.argv[1].replace("/chat/completions", "/models"))
PY
}

is_loopback_url() {
  python - "$1" <<'PY'
import sys
from urllib.parse import urlparse

hostname = (urlparse(sys.argv[1]).hostname or "").lower()
sys.exit(0 if hostname in {"127.0.0.1", "localhost", "::1"} else 1)
PY
}

url_port() {
  python - "$1" "$2" <<'PY'
import sys
from urllib.parse import urlparse

parsed = urlparse(sys.argv[1])
default = int(sys.argv[2])
print(parsed.port or default)
PY
}

wait_for_http() {
  local url="$1" timeout_seconds="${2:-60}"
  local deadline=$((SECONDS + timeout_seconds))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

with_lock() {
  local name="$1"
  shift
  local lock_file="$RUNTIME_DIR/${name}.lock"
  if command -v flock >/dev/null 2>&1; then
    (
      exec 9>"$lock_file"
      flock 9
      "$@"
    )
    return
  fi
  "$@"
}

qdrant_url() {
  config_value qdrant_url "$DEFAULT_QDRANT_URL"
}

answer_url() {
  config_value answer_url "$DEFAULT_ANSWER_URL"
}

answer_model() {
  config_value answer_model "$DEFAULT_ANSWER_MODEL"
}

llm_health_url() {
  if [ -n "${LLM_HEALTH_ENDPOINT:-}" ]; then
    printf '%s\n' "$LLM_HEALTH_ENDPOINT"
    return 0
  fi
  models_url "$(answer_url)"
}

llama_swap_manager_path() {
  if command -v llama-swap-manager >/dev/null 2>&1; then
    command -v llama-swap-manager
    return 0
  fi
  if [ -x "$REPO_DIR/system/llama-swap-manager.sh" ]; then
    printf '%s\n' "$REPO_DIR/system/llama-swap-manager.sh"
    return 0
  fi
  return 1
}

ensure_container_runtime() {
  need_cmd "$CONTAINER_RUNTIME"
  if ! "$CONTAINER_RUNTIME" info >/dev/null 2>&1; then
    printf '%s daemon is not reachable.\n' "$CONTAINER_RUNTIME" >&2
    exit 1
  fi
}

ensure_qdrant_locked() {
  local url host_port
  need_cmd python
  need_cmd curl
  url="$(qdrant_url)"
  if ! is_loopback_url "$url"; then
    return 0
  fi
  if curl -fsS --max-time 1 "${url%/}/collections" >/dev/null 2>&1; then
    return 0
  fi

  ensure_container_runtime
  host_port="$(url_port "$url" 6333)"
  "$CONTAINER_RUNTIME" update --restart=no "$QDRANT_CONTAINER" >/dev/null 2>&1 || true

  if "$CONTAINER_RUNTIME" ps --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
    :
  elif "$CONTAINER_RUNTIME" ps -a --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
    printf 'Starting local Qdrant...\n' >&2
    "$CONTAINER_RUNTIME" start "$QDRANT_CONTAINER" >/dev/null
  else
    printf 'Creating local Qdrant container...\n' >&2
    "$CONTAINER_RUNTIME" create \
      --restart no \
      --name "$QDRANT_CONTAINER" \
      -p "${host_port}:6333" \
      -v "${QDRANT_STORAGE_DIR}:/qdrant/storage" \
      "$QDRANT_IMAGE" >/dev/null
    "$CONTAINER_RUNTIME" start "$QDRANT_CONTAINER" >/dev/null
  fi

  if ! wait_for_http "${url%/}/collections" 45; then
    printf 'Qdrant did not become ready at %s\n' "$url" >&2
    exit 1
  fi
}

warm_llm() {
  local url model payload
  need_cmd python
  need_cmd curl
  url="$(answer_url)"
  model="$(answer_model)"
  payload="$(python - "$model" <<'PY'
import json
import sys

print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": "ok"}],
    "max_tokens": 1,
    "temperature": 0.0,
    "stream": False,
}))
PY
)"
  curl -fsS --max-time 240 "$url" \
    -H 'Content-Type: application/json' \
    -d "$payload" >/dev/null
}

ensure_llm_locked() {
  local health_url manager
  need_cmd python
  need_cmd curl
  health_url="$(llm_health_url)"
  if ! is_loopback_url "$health_url"; then
    return 0
  fi
  if curl -fsS --max-time 1 "$health_url" >/dev/null 2>&1; then
    return 0
  fi

  manager="$(llama_swap_manager_path)" || {
    printf 'llama-swap-manager is unavailable.\n' >&2
    exit 1
  }

  printf 'Starting local llama-swap...\n' >&2
  "$manager" start >/dev/null

  if ! wait_for_http "$health_url" 120; then
    printf 'Local LLM endpoint did not become ready at %s\n' "$health_url" >&2
    exit 1
  fi

  printf 'Warming local model...\n' >&2
  warm_llm
}

ensure_qdrant() {
  with_lock qdrant ensure_qdrant_locked
}

ensure_llm() {
  local health_url
  health_url="$(llm_health_url)"
  if is_loopback_url "$health_url" && curl -fsS --max-time 1 "$health_url" >/dev/null 2>&1; then
    return 0
  fi
  with_lock llama-swap ensure_llm_locked
}

stop_qdrant() {
  if ! command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1; then
    return 0
  fi
  if ! "$CONTAINER_RUNTIME" info >/dev/null 2>&1; then
    return 0
  fi
  if "$CONTAINER_RUNTIME" ps --format '{{.Names}}' | grep -Fxq "$QDRANT_CONTAINER"; then
    "$CONTAINER_RUNTIME" stop "$QDRANT_CONTAINER" >/dev/null
  fi
}

stop_llm() {
  local manager
  manager="$(llama_swap_manager_path)" || return 0
  "$manager" stop >/dev/null 2>&1 || true
}

status_qdrant() {
  local url
  need_cmd python
  need_cmd curl
  url="$(qdrant_url)"
  if is_loopback_url "$url" && curl -fsS --max-time 1 "${url%/}/collections" >/dev/null 2>&1; then
    printf 'qdrant: running (%s)\n' "$url"
  else
    printf 'qdrant: stopped (%s)\n' "$url"
  fi
}

status_llm() {
  local health_url
  need_cmd python
  need_cmd curl
  health_url="$(llm_health_url)"
  if is_loopback_url "$health_url" && curl -fsS --max-time 1 "$health_url" >/dev/null 2>&1; then
    printf 'llm: running (%s)\n' "$health_url"
  else
    printf 'llm: stopped (%s)\n' "$health_url"
  fi
}

case "${1:-status}" in
  ensure-qdrant) ensure_qdrant ;;
  ensure-llm) ensure_llm ;;
  start)
    ensure_qdrant
    ensure_llm
    ;;
  stop)
    stop_llm
    stop_qdrant
    ;;
  status)
    status_qdrant
    status_llm
    ;;
  *)
    printf 'usage: %s {ensure-qdrant|ensure-llm|start|stop|status}\n' "$0" >&2
    exit 1
    ;;
esac
