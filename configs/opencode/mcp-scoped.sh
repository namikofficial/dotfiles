#!/usr/bin/env bash
set -euo pipefail

server="${1:-}"
shift || true
profile="${NOXFLOW_MCP_PROFILE:-minimal}"
source_path="$(readlink -f "${BASH_SOURCE[0]}")"
script_dir="$(cd "$(dirname "$source_path")" && pwd)"

case "$profile:$server" in
  web:browser) exec "$script_dir/chrome-devtools-mcp.sh" "$@" ;;
  mobile:maestro) exec maestro mcp "$@" ;;
  *)
    printf 'MCP server %s is unavailable for profile %s; supported: web:browser, mobile:maestro\n' "$server" "$profile" >&2
    exit 78
    ;;
esac
