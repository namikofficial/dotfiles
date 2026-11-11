#!/usr/bin/env bash
# Control the local llama.cpp router that serves the agentic-coding lanes.
#
# The router is a single llama-server in llama.cpp router mode. It keeps ONE
# model resident at a time (--models-max 1); the llama.cpp default of 4 is an
# immediate cudaMalloc OOM on a 6 GB card.
#
# Subcommands:
#   render    re-render ~/.config/llama-router/models.ini from the template
#   start     render, then start the user unit
#   stop      stop the user unit
#   restart   stop then start
#   status    report unit state, health and the available lanes
#   health    check the HTTP health endpoint only
set -euo pipefail

# Resolve through the ~/.local/bin symlink so SCRIPT_DIR points at the
# repository copy, not at the directory the symlink happens to live in.
script_path="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$script_path")" && pwd)"
UNIT="${LLAMA_ROUTER_UNIT:-llama-router.service}"
PORT="${LLAMA_ROUTER_PORT:-8080}"
HOST="${LLAMA_ROUTER_HOST:-127.0.0.1}"
MODEL_ROOT="${LLAMA_MODEL_ROOT:-/home/namik/llama-models}"
PRESET="${LLAMA_ROUTER_PRESET:-$HOME/.config/llama-router/models.ini}"

usage() {
  sed -n '3,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

render_preset() {
  python3 "$SCRIPT_DIR/render-preset.py" \
    --model-root "$MODEL_ROOT" \
    --output "$PRESET"
}

router_health() {
  curl -fsS --max-time 3 "http://$HOST:$PORT/health" 2>/dev/null
}

list_lanes() {
  curl -fsS --max-time 5 "http://$HOST:$PORT/models" 2>/dev/null | python3 -c '
import json
import sys

try:
    payload = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    sys.exit(1)

for entry in payload.get("data", []):
    status = (entry.get("status") or {}).get("value", "unknown")
    print("  {:<22} {:<10} {}".format(entry.get("id", "?"), status, "ready"))
'
}

cmd_status() {
  printf 'unit      : %s\n' "$UNIT"
  printf 'preset    : %s\n' "$PRESET"
  printf 'model root: %s\n' "$MODEL_ROOT"
  printf 'endpoint  : http://%s:%s/v1\n' "$HOST" "$PORT"
  systemctl --user is-active "$UNIT" 2>/dev/null || true

  if health=$(router_health); then
    printf 'health    : %s\n' "$health"
    printf 'lanes:\n'
    list_lanes || printf '  (could not list lanes)\n'
  else
    printf 'health    : unreachable\n'
  fi
}

case "${1:-status}" in
  render)
    render_preset
    ;;
  start)
    render_preset
    systemctl --user daemon-reload
    systemctl --user start "$UNIT"
    sleep 2
    cmd_status
    ;;
  stop)
    systemctl --user stop "$UNIT"
    ;;
  restart)
    systemctl --user stop "$UNIT" || true
    render_preset
    systemctl --user daemon-reload
    systemctl --user start "$UNIT"
    sleep 2
    cmd_status
    ;;
  status)
    cmd_status
    ;;
  health)
    router_health
    ;;
  -h | --help | help)
    usage
    ;;
  *)
    printf 'unknown subcommand: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
esac
