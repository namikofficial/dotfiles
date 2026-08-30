#!/usr/bin/env bash
set -euo pipefail

server="${1:-}"
shift || true
profile="${NOXFLOW_MCP_PROFILE:-minimal}"
source_path="$(readlink -f "${BASH_SOURCE[0]}")"
script_dir="$(cd "$(dirname "$source_path")" && pwd)"
mcp_home="${OPENCODE_MCP_HOME:-$HOME/.local/share/opencode/mcp}"

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
    exec "$script_dir/chrome-devtools-mcp.sh" "$@"
    ;;
  codegraph)
    codegraph_bin="${CODEGRAPH_MCP_BIN:-$mcp_home/node_modules/.bin/codegraph}"
    if [ ! -x "$codegraph_bin" ]; then
      printf 'codegraph MCP is not installed at %s; run %s/setup/install-opencode-mcp.sh\n' \
        "$codegraph_bin" "$(cd "$script_dir/../.." && pwd)" >&2
      exit 127
    fi
    exec "$codegraph_bin" serve --mcp "$@"
    ;;
  local-docs)
    exec "$script_dir/../../system/local-docs-mcp.sh" "$@"
    ;;
  obsidian)
    exec "$script_dir/obsidian-mcp.sh" "$@"
    ;;
  maestro)
    exec maestro mcp "$@"
    ;;
  *)
    printf 'unknown MCP server: %s\n' "$server" >&2
    exit 2
    ;;
esac
