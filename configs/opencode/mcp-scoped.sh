#!/usr/bin/env bash
set -euo pipefail

server="${1:-}"
shift || true
profile="${NOXFLOW_MCP_PROFILE:-minimal}"

enabled_for_profile() {
  local name="$1"
  case "$profile:$name" in
    minimal:browser | dev:browser | dev:codegraph | dev:local-docs | notes:browser | notes:codegraph | notes:local-docs | notes:obsidian | mobile:browser | mobile:codegraph | mobile:local-docs | mobile:maestro)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

if [ -z "$server" ]; then
  printf 'usage: %s {browser|codegraph|local-docs|obsidian|maestro}\n' "$0" >&2
  exit 2
fi

if ! enabled_for_profile "$server"; then
  printf 'MCP server %s is disabled for profile %s; use NOXFLOW_MCP_PROFILE=dev|notes|mobile\n' "$server" "$profile" >&2
  exit 78
fi

case "$server" in
  browser)
    exec "$(dirname "$0")/chrome-devtools-mcp.sh" "$@"
    ;;
  codegraph)
    exec codegraph serve --mcp "$@"
    ;;
  local-docs)
    exec "$(dirname "$0")/../../system/local-docs-mcp.sh" "$@"
    ;;
  obsidian)
    exec "$(dirname "$0")/obsidian-mcp.sh" "$@"
    ;;
  maestro)
    exec maestro mcp "$@"
    ;;
  *)
    printf 'unknown MCP server: %s\n' "$server" >&2
    exit 2
    ;;
esac
