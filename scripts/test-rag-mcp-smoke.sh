#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

python - <<'PY'
import asyncio
import json
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch

system_dir = Path.cwd() / "system"
sys.path.insert(0, str(system_dir))

from rag import mcp_server  # noqa: E402
from rag.orchestrator import task_step  # noqa: E402


async def main() -> int:
    tools = await mcp_server._list_tools()
    names = {tool.name for tool in tools}
    required = {"rag_task_step", "rag_task_continue", "rag_should_use_graph"}
    missing = sorted(required - names)
    if missing:
        raise SystemExit(f"missing tools: {missing}")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / ".git").mkdir()
        with patch("rag.orchestrator.repo_root", return_value=root), patch(
            "rag.orchestrator.cached_probe_runtime",
            return_value={"qdrant_ready": False, "llm_ready": False},
        ):
            parsed = task_step("smoke test task")
    if parsed.get("state") != "needs_plan":
        raise SystemExit(f"unexpected rag_task_step state: {parsed}")
    print("ok: rag-mcp tool surface and rag_task_step contract")
    return 0


raise SystemExit(asyncio.run(main()))
PY
