#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKBENCH_DIR="${AI_WORKBENCH_DIR:-$HOME/Documents/code/ai}"
MCP_CMD="$REPO_DIR/system/workbench-mcp.sh"

[ -x "$MCP_CMD" ] || {
  echo "missing executable: $MCP_CMD" >&2
  exit 1
}
[ -f "$WORKBENCH_DIR/mcp/server/src/main.ts" ] || {
  echo "missing Workbench MCP source: $WORKBENCH_DIR" >&2
  exit 1
}

python - "$MCP_CMD" <<'PY'
import json
import subprocess
import sys

command = [sys.argv[1]]
requests = [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "dotfiles-smoke", "version": "1"}}},
    {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}},
    {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
]
payload = "".join(json.dumps(request) + "\n" for request in requests)
process = subprocess.run(command, input=payload, text=True, capture_output=True, timeout=30)
if process.returncode != 0:
    raise SystemExit(process.stderr or f"Workbench MCP exited with {process.returncode}")
responses = [json.loads(line) for line in process.stdout.splitlines() if line.strip()]
if not any(response.get("id") == 1 and response.get("result") for response in responses):
    raise SystemExit(f"initialize failed: {responses}")
tools = next((response.get("result", {}).get("tools", []) for response in responses if response.get("id") == 2), [])
names = {tool.get("name") for tool in tools}
required = {"ai_list_projects", "ai_search_project", "ai_get_runtime_health"}
missing = sorted(required - names)
if missing:
    raise SystemExit(f"missing Workbench tools: {missing}")
print(f"workbench MCP smoke: ok ({len(names)} tools)")
PY

if command -v opencode >/dev/null 2>&1; then
  opencode mcp list || true
fi
