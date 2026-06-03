#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STACK_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/open-webui"
COMPOSE_SRC="$REPO_DIR/configs/open-webui/docker-compose.yml"
COMPOSE_DEST="$STACK_DIR/compose.yml"
ENV_DEST="$STACK_DIR/.env"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing command: %s\n' "$1" >&2
    exit 1
  }
}

need_cmd docker
need_cmd jq
need_cmd openssl

mkdir -p "$STACK_DIR"
ln -sfn "$COMPOSE_SRC" "$COMPOSE_DEST"

if [ ! -f "$ENV_DEST" ]; then
  webui_secret="$(openssl rand -hex 32)"
  mcpo_key="$(openssl rand -hex 24)"
  cat >"$ENV_DEST" <<EOF
WEBUI_SECRET_KEY=$webui_secret
OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1
OPENAI_API_KEY=local
OPENAI_API_BASE_URLS=
DEFAULT_MODELS=
MCPO_API_KEY=$mcpo_key
EOF
else
  if grep -q '^WEBUI_SECRET_KEY=replace-with-a-long-random-string$' "$ENV_DEST"; then
    sed -i "s/^WEBUI_SECRET_KEY=.*/WEBUI_SECRET_KEY=$(openssl rand -hex 32)/" "$ENV_DEST"
  fi
  if grep -q '^OPENAI_API_BASE_URL=http://127\.0\.0\.1:8080/v1$' "$ENV_DEST"; then
    sed -i 's#^OPENAI_API_BASE_URL=.*#OPENAI_API_BASE_URL=http://host.docker.internal:8080/v1#' "$ENV_DEST"
  fi
  if grep -q '^MCPO_API_KEY=local$' "$ENV_DEST"; then
    sed -i "s/^MCPO_API_KEY=.*/MCPO_API_KEY=$(openssl rand -hex 24)/" "$ENV_DEST"
  fi
fi

printf 'Open WebUI stack prepared.\n'
printf 'Config: %s\n' "$COMPOSE_DEST"
printf 'Env:    %s\n' "$ENV_DEST"
printf '\nNext:\n'
printf '  cd %s && docker compose --env-file .env up -d\n' "$STACK_DIR"
printf '  open http://127.0.0.1:3080\n'
printf '\nRAG bridge endpoints:\n'
printf '  Swagger docs:  http://127.0.0.1:8088/docs\n'
printf '  OpenAPI spec:  http://127.0.0.1:8088/openapi.json\n'
printf '  Docker URL:    http://rag-mcpo:8000/openapi.json\n'
printf 'Use MCPO_API_KEY from %s as the bearer token when registering the OpenAPI tool.\n' "$ENV_DEST"
