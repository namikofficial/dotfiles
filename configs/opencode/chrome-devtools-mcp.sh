#!/usr/bin/env bash
set -euo pipefail

mcp_bin="${CHROME_DEVTOOLS_MCP_BIN:-/home/namik/.local/share/opencode/mcp/node_modules/.bin/chrome-devtools-mcp}"

if [ ! -x "$mcp_bin" ]; then
  mcp_bin="$(command -v chrome-devtools-mcp || true)"
fi

if [ -z "$mcp_bin" ] || [ ! -x "$mcp_bin" ]; then
  printf 'chrome-devtools-mcp is not installed\n' >&2
  exit 127
fi

# Launch a dedicated, persistent Chrome profile for agent work. This keeps the
# user's personal Chrome session and credentials completely separate, avoids
# Chrome's current-profile approval dialog, and preserves the agent profile's
# cookies/local storage between OpenCode sessions.
profile_dir="${CHROME_DEVTOOLS_MCP_USER_DATA_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/opencode/chrome-devtools-profile}"
mkdir -p "$profile_dir"
exec "$mcp_bin" \
  --channel stable \
  --userDataDir "$profile_dir" \
  --no-usage-statistics \
  --experimentalPageIdRouting \
  "$@"
