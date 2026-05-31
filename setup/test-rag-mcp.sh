#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v python >/dev/null 2>&1; then
  echo "python not found" >&2
  exit 1
fi

if ! python -c "import mcp" >/dev/null 2>&1; then
  echo "python package 'mcp' is not installed; install it before running this smoke test" >&2
  exit 1
fi

MCP_CMD=""
if command -v rag-mcp >/dev/null 2>&1; then
  MCP_CMD="rag-mcp"
elif [ -x "$REPO_DIR/system/rag-mcp.sh" ]; then
  MCP_CMD="$REPO_DIR/system/rag-mcp.sh"
fi

if [ -n "$MCP_CMD" ]; then
  set +e
  timeout 2s "$MCP_CMD" >/tmp/rag-mcp-smoke.out 2>/tmp/rag-mcp-smoke.err
  rc=$?
  set -e
  if [ "$rc" -ne 124 ]; then
    echo "rag-mcp did not stay running under timeout smoke (rc=$rc)" >&2
    sed -n '1,80p' /tmp/rag-mcp-smoke.err >&2 || true
    exit 1
  fi
fi

TMP_REPO="$(mktemp -d)"
trap 'rm -rf "$TMP_REPO"' EXIT
mkdir -p "$TMP_REPO/.git"

REPO_DIR="$REPO_DIR" TMP_REPO="$TMP_REPO" python - <<'PY'
import asyncio
import json
import os
import sys

repo_dir = os.environ["REPO_DIR"]
tmp_repo = os.environ["TMP_REPO"]

sys.path.insert(0, os.path.join(repo_dir, "system"))
os.chdir(tmp_repo)

from rag import mcp_server


def parse_json(contents):
    text = contents[0].text
    return json.loads(text)


async def main() -> None:
    tools = await mcp_server._list_tools()
    names = {tool.name for tool in tools}
    assert "rag_task_step" in names, "rag_task_step missing from tools list"

    payload = parse_json(await mcp_server._call_tool("rag_task_step", {"task": "smoke task"}))
    assert payload["state"] == "needs_plan", f"unexpected initial state: {payload}"

    graph = parse_json(await mcp_server._call_tool("rag_plan_task", {"task": "smoke task"}))
    assert graph.get("task_id"), "rag_plan_task did not return task graph"

    subtask = parse_json(await mcp_server._call_tool("rag_next_subtask", {}))
    assert isinstance(subtask, dict) and subtask.get("id") == "T1", f"unexpected next subtask: {subtask}"

    context = parse_json(await mcp_server._call_tool("rag_subtask_context", {"subtask_id": "T1"}))
    assert context.get("subtask", {}).get("id") == "T1", "context did not return T1"
    assert "context" not in context, "compact context should omit full context text"

    print("rag mcp smoke: ok")


asyncio.run(main())
PY
