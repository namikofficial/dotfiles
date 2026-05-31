"""RAG MCP server — exposes read-only context and retrieval tools to OpenCode.

v1 tool surface (context and retrieval only, no code editing):
  rag_status              current RAG + repo health
  rag_search              hybrid retrieval search
  rag_deep                deep RAG answer with LLM reasoning
  rag_agent_context       full agent-ready context pack with handoff
  rag_context_git_refresh refresh git diff context source
  rag_memory_status       show repo memory freshness
  rag_memory_pack         build a reusable context pack

Run as a module:
  python -m rag.mcp_server
"""
from __future__ import annotations

import asyncio
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from mcp.server import NotificationOptions, Server
from mcp.server.models import InitializationOptions
import mcp.server.stdio
import mcp.types as types


_server = Server("rag-mcp")


def _repo_root() -> Path:
    current = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists() or (current / ".agent").exists():
            return current
        current = current.parent
    return Path.cwd()


def _run_rag(*args: str, timeout: int = 45) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "rag.cli", *args],
        cwd=_repo_root(),
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _text(content: str) -> list[types.TextContent]:
    return [types.TextContent(type="text", text=content)]


# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

@_server.list_resources()
async def _list_resources() -> list[types.Resource]:
    return [
        types.Resource(
            uri="rag://task/current",  # type: ignore[arg-type]
            name="Current Task",
            description="Active task plan from .agent/task.md",
            mimeType="text/markdown",
        ),
        types.Resource(
            uri="rag://memory/project",  # type: ignore[arg-type]
            name="Project Memory",
            description="Persistent project knowledge from .agent/memory.md",
            mimeType="text/markdown",
        ),
        types.Resource(
            uri="rag://git/status",  # type: ignore[arg-type]
            name="Git Status",
            description="Current git repository status",
            mimeType="text/plain",
        ),
        types.Resource(
            uri="rag://sessions/recent",  # type: ignore[arg-type]
            name="Recent Sessions",
            description="Last 5 RAG session compactions for this repo",
            mimeType="text/markdown",
        ),
    ]


@_server.read_resource()
async def _read_resource(uri: types.AnyUrl) -> str:
    root = _repo_root()
    s = str(uri)

    if s == "rag://task/current":
        p = root / ".agent" / "task.md"
        return p.read_text() if p.exists() else "# Current Task\n\n*No task initialized. Run: rag task init \"<description>\"*"

    if s == "rag://memory/project":
        p = root / ".agent" / "memory.md"
        return p.read_text() if p.exists() else "# Project Memory\n\n*No memory yet.*"

    if s == "rag://git/status":
        result = subprocess.run(
            ["git", "log", "--oneline", "-5"],
            cwd=root, capture_output=True, text=True, timeout=5,
        )
        status = subprocess.run(
            ["git", "status", "--short"],
            cwd=root, capture_output=True, text=True, timeout=5,
        )
        out = "## Recent commits\n\n```\n" + (result.stdout or "(none)") + "```\n\n"
        out += "## Uncommitted changes\n\n```\n" + (status.stdout or "(none)") + "```"
        return out

    if s == "rag://sessions/recent":
        result = _run_rag("memory", "compact", "--limit", "5")
        return result.stdout or "*No session compactions yet.*"

    raise ValueError(f"Unknown resource URI: {uri}")


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

@_server.list_tools()
async def _list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="rag_status",
            description="Show local RAG health: qdrant, venv, indexed repos, model endpoint.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="rag_search",
            description="Hybrid retrieval search over indexed code and docs.",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string", "description": "Search query"},
                    "limit": {"type": "integer", "description": "Max results", "default": 8},
                },
                "required": ["query"],
            },
        ),
        types.Tool(
            name="rag_deep",
            description="Deep RAG answer: retrieves context then calls LLM for reasoning.",
            inputSchema={
                "type": "object",
                "properties": {
                    "question": {"type": "string", "description": "Question to answer"},
                    "budget": {
                        "type": "string",
                        "description": "Reasoning budget",
                        "enum": ["low", "medium", "high"],
                        "default": "medium",
                    },
                },
                "required": ["question"],
            },
        ),
        types.Tool(
            name="rag_agent_context",
            description=(
                "Build a full agent context pack for a task: refreshes git, runs agent-mode "
                "retrieval, writes .agent/handoff.md, returns task + memory + handoff content."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "task": {"type": "string", "description": "Task description"},
                    "target_agent": {
                        "type": "string",
                        "enum": ["opencode", "codex", "copilot", "generic"],
                        "default": "opencode",
                    },
                },
                "required": ["task"],
            },
        ),
        types.Tool(
            name="rag_context_git_refresh",
            description="Refresh the git diff/branch context source so retrieval reflects current changes.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="rag_memory_status",
            description="Show repo memory freshness and indexed chunk counts.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="rag_memory_pack",
            description="Build a reusable context pack summarising project memory.",
            inputSchema={
                "type": "object",
                "properties": {
                    "target_agent": {
                        "type": "string",
                        "enum": ["opencode", "codex", "copilot", "generic"],
                        "default": "opencode",
                    },
                },
            },
        ),
    ]


@_server.call_tool()
async def _call_tool(name: str, arguments: dict[str, Any]) -> list[types.TextContent]:
    try:
        if name == "rag_status":
            r = _run_rag("status")
            return _text(r.stdout or r.stderr or "No output")

        if name == "rag_search":
            query = arguments["query"]
            limit = str(arguments.get("limit", 8))
            r = _run_rag("search", query, "--limit", limit)
            return _text(r.stdout or f"Search failed: {r.stderr}")

        if name == "rag_deep":
            question = arguments["question"]
            r = _run_rag("deep", question, timeout=90)
            return _text(r.stdout or f"Deep search failed: {r.stderr}")

        if name == "rag_agent_context":
            task = arguments["task"]
            target = arguments.get("target_agent", "opencode")
            root = _repo_root()
            _run_rag("context", "git", "--refresh", timeout=15)
            r = _run_rag("agent", task, "--target-agent", target, "--save-handoff", timeout=90)
            if r.returncode != 0:
                return _text(f"Agent context failed: {r.stderr}")
            parts: dict[str, str] = {}
            for fname in ("task.md", "memory.md", "handoff.md"):
                p = root / ".agent" / fname
                if p.exists():
                    parts[fname] = p.read_text()
            return _text(json.dumps(parts, indent=2))

        if name == "rag_context_git_refresh":
            r = _run_rag("context", "git", "--refresh", timeout=15)
            return _text(r.stdout or "Git context refreshed")

        if name == "rag_memory_status":
            r = _run_rag("memory", "status")
            return _text(r.stdout or r.stderr or "No memory status")

        if name == "rag_memory_pack":
            target = arguments.get("target_agent", "opencode")
            r = _run_rag("memory", "pack", "--target-agent", target, timeout=60)
            return _text(r.stdout or f"Memory pack failed: {r.stderr}")

        return _text(f"Unknown tool: {name}")

    except subprocess.TimeoutExpired:
        return _text(f"Timed out running {name}")
    except Exception as exc:  # noqa: BLE001
        return _text(f"Error in {name}: {exc}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def _run() -> None:
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await _server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="rag-mcp",
                server_version="1.0.0",
                capabilities=_server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


def main() -> None:
    asyncio.run(_run())


if __name__ == "__main__":
    main()
