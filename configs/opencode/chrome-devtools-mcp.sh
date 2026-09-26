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

# Attach to the user's active Chrome profile. Chrome 144+ must have remote
# debugging enabled at chrome://inspect/#remote-debugging and may ask for
# approval when the agent connects. The MCP can access open tabs and session
# data in that profile.
exec "$mcp_bin" \
  --channel stable \
  --autoConnect \
  --no-usage-statistics \
  --experimentalPageIdRouting \
  "$@"
