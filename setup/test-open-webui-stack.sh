#!/usr/bin/env bash
set -euo pipefail

WEBUI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/open-webui"
ENV_FILE="$WEBUI_DIR/.env"
COMPOSE_FILE="$WEBUI_DIR/compose.yml"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1" >&2
    exit 1
  }
}

need_cmd curl
need_cmd docker
need_cmd jq

[ -f "$ENV_FILE" ] || { printf 'Missing env file: %s\n' "$ENV_FILE" >&2; exit 1; }
[ -f "$COMPOSE_FILE" ] || { printf 'Missing compose file: %s\n' "$COMPOSE_FILE" >&2; exit 1; }

mcpo_key="$(awk -F= '/^MCPO_API_KEY=/{print $2}' "$ENV_FILE")"
[ -n "$mcpo_key" ] || { printf 'MCPO_API_KEY is missing in %s\n' "$ENV_FILE" >&2; exit 1; }

printf '[open-webui] health: '
curl -fsS --max-time 10 http://127.0.0.1:3080/health | jq -e '.status == true' >/dev/null
printf 'ok\n'

printf '[rag-mcpo] openapi: '
curl -fsS --max-time 10 http://127.0.0.1:8088/openapi.json | jq -e '.info.title == "rag-mcp"' >/dev/null
printf 'ok\n'

printf '[rag-mcpo] tool call: '
curl -fsS --max-time 20 \
  -X POST http://127.0.0.1:8088/rag_memory_status \
  -H "Authorization: Bearer $mcpo_key" \
  -H 'content-type: application/json' \
  -d '{}' | jq -e 'type == "string" and contains("dotfiles")' >/dev/null
printf 'ok\n'

printf '[open-webui] host model endpoint from container: '
docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" exec -T open-webui python - <<'PY' | jq -e 'length > 0' >/dev/null
import json
import urllib.request

with urllib.request.urlopen("http://host.docker.internal:8080/v1/models", timeout=10) as response:
    payload = json.load(response)
print(json.dumps([model.get("id") for model in payload.get("data", [])]))
PY
printf 'ok\n'
