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

# Attach to the user's already-running Chrome. This deliberately does not
# launch a second Chromium profile or expose a non-local debugging endpoint.
exec "$mcp_bin" \
  --autoConnect \
  --channel stable \
  --no-usage-statistics \
  --experimentalPageIdRouting \
  "$@"
