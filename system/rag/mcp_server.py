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
import dataclasses
import json
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path
from typing import Any

try:
    from mcp.server import NotificationOptions, Server
    from mcp.server.models import InitializationOptions
    import mcp.server.stdio as mcp_stdio
    import mcp.types as types
    MCP_AVAILABLE = True
except ModuleNotFoundError:  # pragma: no cover - exercised indirectly in tests
    MCP_AVAILABLE = False

    @dataclasses.dataclass
    class NotificationOptions:
        pass

    @dataclasses.dataclass
    class InitializationOptions:
        server_name: str
        server_version: str
        capabilities: dict[str, Any]

    @dataclasses.dataclass
    class _TextContent:
        type: str
        text: str

    @dataclasses.dataclass
    class _Tool:
        name: str
        description: str
        inputSchema: dict[str, Any]

    @dataclasses.dataclass
    class _Resource:
        uri: str
        name: str
        description: str
        mimeType: str

    class _TypesModule:
        TextContent = _TextContent
        Tool = _Tool
        Resource = _Resource
        AnyUrl = str

    types = _TypesModule()

    class Server:
        def __init__(self, _name: str) -> None:
            self._capabilities: dict[str, Any] = {}

        def list_resources(self):
            def decorator(func):
                return func
            return decorator

        def read_resource(self):
            def decorator(func):
                return func
            return decorator

        def list_tools(self):
            def decorator(func):
                return func
            return decorator

        def call_tool(self):
            def decorator(func):
                return func
            return decorator

        def get_capabilities(self, **_kwargs: Any) -> dict[str, Any]:
            return {}

        async def run(self, *_args: Any, **_kwargs: Any) -> None:
            raise RuntimeError("python package 'mcp' is required to run rag-mcp")

from .agent_support import (
    describe_task,
    evaluate_query,
    file_card,
    perf_report_from_result,
    record_outcome,
    related_tests,
    render_agent_context_markdown,
    runtime_config,
    suggest_commands,
)
from .orchestrator import (
    compact_completed_subtasks,
    learn_from_task_outcome,
    load_task_graph,
    mark_subtask_done,
    mark_subtask_failed,
    mark_subtask_running,
    next_subtask,
    plan_task,
    task_step,
    reflect_run,
    subtask_context,
    task_graph_status,
)
from .memory import repo_memory_status_rows
from .retrieval import gather_context, reranker_enabled, retrieve
from .settings import get_mode_profile, load_config
from .state import get_retrieval_run, latest_retrieval_run, retrieval_run_payload
from .storage import connect_db, get_qdrant, infer_repo_filter


_server = Server("rag-mcp")


@contextmanager
def db_conn():
    conn = connect_db()
    try:
        yield conn
    finally:
        conn.close()


def _related_tests_payload(path: str) -> dict[str, Any]:
    with db_conn() as conn:
        repo = infer_repo_filter(conn, None)
        return {"tests": related_tests(conn, repo, path)}


def _file_card_payload(path: str, why_selected: str | None) -> dict[str, Any]:
    with db_conn() as conn:
        repo = infer_repo_filter(conn, None)
        return file_card(conn, repo, path, why_selected)


def _record_outcome_payload(arguments: dict[str, Any]) -> dict[str, Any]:
    with db_conn() as conn:
        repo = infer_repo_filter(conn, None)
        outcome_id = record_outcome(
            repo=repo,
            task=arguments["task"],
            retrieved_files=list(arguments.get("retrieved_files", [])),
            edited_files=list(arguments.get("edited_files", [])),
            checks_run=list(arguments.get("checks_run", [])),
            passed=bool(arguments.get("passed", False)),
            notes=arguments.get("notes"),
            run_id=arguments.get("run_id"),
        )
        return {"stored": True, "outcome_id": outcome_id}


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


def _json_text(payload: Any) -> list[types.TextContent]:
    return _text(json.dumps(payload, indent=2, sort_keys=True))


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
        return p.read_text() if p.exists() else "# Current Task\n\n*No task initialized. Run: rag task start \"<description>\"*"

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
                "Build agent-ready context before non-trivial edits. Returns readable task, edit scope, "
                "missing context, evidence, git state, and suggested checks."
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
                    "format": {
                        "type": "string",
                        "enum": ["markdown", "json"],
                        "default": "markdown",
                        "description": "Readable markdown is default; JSON is available for automation.",
                    },
                },
                "required": ["task"],
            },
        ),
        types.Tool(
            name="rag_plan_task",
            description="Split a broad task into a dependency-aware task graph and write .agent/task-graph.json.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task": {"type": "string"},
                    "repo": {"type": "string"},
                    "max_subtasks": {"type": "integer", "default": 8},
                },
                "required": ["task"],
            },
        ),
        types.Tool(
            name="rag_next_subtask",
            description="Return the next ready subtask from the current task graph.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="rag_subtask_context",
            description="Build focused retrieval context for one subtask and return its edit scope.",
            inputSchema={
                "type": "object",
                "properties": {
                    "subtask_id": {"type": "string"},
                    "format": {"type": "string", "enum": ["compact", "full"], "default": "compact"},
                },
                "required": ["subtask_id"],
            },
        ),
        types.Tool(
            name="rag_subtask_running",
            description="Mark a subtask as running and increment its attempt counter.",
            inputSchema={
                "type": "object",
                "properties": {
                    "subtask_id": {"type": "string"},
                },
                "required": ["subtask_id"],
            },
        ),
        types.Tool(
            name="rag_subtask_done",
            description="Record a completed subtask outcome, checks, and edited files.",
            inputSchema={
                "type": "object",
                "properties": {
                    "subtask_id": {"type": "string"},
                    "retrieved_files": {"type": "array", "items": {"type": "string"}},
                    "edited_files": {"type": "array", "items": {"type": "string"}},
                    "checks_run": {"type": "array", "items": {"type": "string"}},
                    "passed": {"type": "boolean", "default": True},
                    "notes": {"type": "string"},
                },
                "required": ["subtask_id"],
            },
        ),
        types.Tool(
            name="rag_subtask_failed",
            description="Record a failed subtask attempt and keep retry context narrow.",
            inputSchema={
                "type": "object",
                "properties": {
                    "subtask_id": {"type": "string"},
                    "retrieved_files": {"type": "array", "items": {"type": "string"}},
                    "edited_files": {"type": "array", "items": {"type": "string"}},
                    "checks_run": {"type": "array", "items": {"type": "string"}},
                    "notes": {"type": "string"},
                },
                "required": ["subtask_id"],
            },
        ),
        types.Tool(
            name="rag_task_status",
            description="Return the current task graph status and next runnable subtask.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="rag_task_step",
            description="Return the next orchestration action OpenCode should take: plan, get context, record outcome, learn, or finish.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task": {
                        "type": "string",
                        "description": "Optional task description used when there is no active task graph.",
                    }
                },
            },
        ),
        types.Tool(
            name="rag_reflect_run",
            description="Summarize retrieval and task outcomes after a run.",
            inputSchema={"type": "object", "properties": {}},
        ),
        types.Tool(
            name="rag_learn_from_outcome",
            description="Promote stable lessons from the latest task run into .rag/profile.json and memory.",
            inputSchema={
                "type": "object",
                "properties": {
                    "run_id": {"type": "string"},
                },
            },
        ),
        types.Tool(
            name="rag_edit_scope",
            description="Use before editing to see likely edit files, nearby tests, read-only evidence, and paths to avoid.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task": {"type": "string"},
                },
                "required": ["task"],
            },
        ),
        types.Tool(
            name="rag_missing_context",
            description="Use when uncertain. Reports whether current retrieval is sufficient and what context is still missing.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task": {"type": "string"},
                    "selected_files": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["task"],
            },
        ),
        types.Tool(
            name="rag_find_tests",
            description="Find nearby likely test files for a source file or task-relevant file.",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                },
                "required": ["path"],
            },
        ),
        types.Tool(
            name="rag_explain_file",
            description="Return a file card: purpose, symbols, imports, related tests, risk level, and why it was selected.",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {"type": "string"},
                    "why_selected": {"type": "string"},
                },
                "required": ["path"],
            },
        ),
        types.Tool(
            name="rag_record_outcome",
            description="Call after finishing work to store retrieved files, edited files, checks, and success for future ranking.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task": {"type": "string"},
                    "retrieved_files": {"type": "array", "items": {"type": "string"}},
                    "edited_files": {"type": "array", "items": {"type": "string"}},
                    "checks_run": {"type": "array", "items": {"type": "string"}},
                    "passed": {"type": "boolean"},
                    "notes": {"type": "string"},
                    "run_id": {"type": "string"},
                },
                "required": ["task", "retrieved_files", "edited_files", "checks_run", "passed"],
            },
        ),
        types.Tool(
            name="rag_suggest_commands",
            description="Suggest exact validation commands for the selected files and task.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task": {"type": "string"},
                    "selected_files": {"type": "array", "items": {"type": "string"}},
                },
                "required": ["task"],
            },
        ),
        types.Tool(
            name="rag_perf_report",
            description="Inspect the latest retrieval run for slow stages, candidate counts, token load, and optimization hints.",
            inputSchema={
                "type": "object",
                "properties": {
                    "run_id": {"type": "string"},
                },
            },
        ),
        types.Tool(
            name="rag_eval_query",
            description="Probe retrieval quality for a query before editing. Returns top files, coverage, warnings, and scope.",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "mode": {"type": "string", "enum": ["quick", "deep", "agent"], "default": "deep"},
                },
                "required": ["query"],
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
            fmt = arguments.get("format", "markdown")
            _run_rag("context", "git", "--refresh", timeout=15)
            payload = await asyncio.to_thread(describe_task, task, target_agent=target)
            graph = await asyncio.to_thread(load_task_graph)
            stale_task_graph = False
            if graph is not None:
                graph_words = {word for word in graph.task.lower().split() if word}
                task_words = {word for word in task.lower().split() if word}
                overlap_ratio = len(graph_words & task_words) / max(1, len(task_words))
                graph_active = any(item.status.value in {"ready", "running"} for item in graph.subtasks)
                stale_task_graph = overlap_ratio < 0.25 and not graph_active
                current = graph.active_subtask() if not stale_task_graph else None
                payload["current_subtask"] = current.to_dict() if current else None
                payload["next_mcp_tool"] = "rag_subtask_context" if current else "rag_plan_task"
                payload["task_graph"] = graph.to_dict() if not stale_task_graph else None
            payload["stale_task_graph"] = stale_task_graph
            if fmt == "json":
                return _json_text(
                    {
                        "task": payload["task"],
                        "ready_to_edit": payload["ready_to_edit"],
                        "edit_scope": payload["edit_scope"],
                        "must_inspect_first": payload["files"][:6],
                        "project_memory": payload["project_memory"],
                        "git_state": payload["git_state"],
                        "evidence": payload["evidence"],
                        "missing_context": payload["missing_context"],
                        "suggested_commands": payload["suggested_commands"],
                        "grounding_rules": [
                            "Stay inside edit_scope unless direct inspection disproves it.",
                            "Do not claim checks passed unless command output confirms it.",
                        ],
                        "current_subtask": payload.get("current_subtask"),
                        "next_mcp_tool": payload.get("next_mcp_tool"),
                        "stale_task_graph": payload.get("stale_task_graph", False),
                        "run": payload["run"],
                    }
                )
            return _text(render_agent_context_markdown(payload))

        if name == "rag_plan_task":
            graph = await asyncio.to_thread(
                plan_task,
                arguments["task"],
                arguments.get("repo"),
                int(arguments.get("max_subtasks", 8)),
            )
            return _json_text(graph.to_dict())

        if name == "rag_next_subtask":
            graph = await asyncio.to_thread(load_task_graph)
            subtask = await asyncio.to_thread(next_subtask, graph)
            return _json_text(subtask.to_dict() if subtask else {"subtask": None})

        if name == "rag_subtask_context":
            graph = await asyncio.to_thread(load_task_graph)
            output_format = "full" if arguments.get("format") == "full" else "compact"
            payload = await asyncio.to_thread(subtask_context, graph, arguments["subtask_id"], output_format=output_format)
            return _json_text(payload)

        if name == "rag_subtask_running":
            graph = await asyncio.to_thread(load_task_graph)
            if graph is None:
                return _text("No task graph found")
            updated = await asyncio.to_thread(mark_subtask_running, graph, arguments["subtask_id"])
            return _json_text(updated.to_dict())

        if name == "rag_subtask_done":
            graph = await asyncio.to_thread(load_task_graph)
            if graph is None:
                return _text("No task graph found")
            try:
                updated = await asyncio.to_thread(
                    mark_subtask_done,
                    graph,
                    arguments["subtask_id"],
                    retrieved_files=list(arguments.get("retrieved_files", [])),
                    edited_files=list(arguments.get("edited_files", [])),
                    checks_run=list(arguments.get("checks_run", [])),
                    passed=bool(arguments.get("passed", True)),
                    notes=arguments.get("notes"),
                )
            except ValueError as exc:
                return _json_text({"ok": False, "error": str(exc), "next_mcp_tool": "rag_subtask_failed"})
            return _json_text(updated.to_dict())

        if name == "rag_subtask_failed":
            graph = await asyncio.to_thread(load_task_graph)
            if graph is None:
                return _text("No task graph found")
            updated = await asyncio.to_thread(
                mark_subtask_failed,
                graph,
                arguments["subtask_id"],
                retrieved_files=list(arguments.get("retrieved_files", [])),
                edited_files=list(arguments.get("edited_files", [])),
                checks_run=list(arguments.get("checks_run", [])),
                notes=arguments.get("notes"),
            )
            subtask = updated.get_subtask(arguments["subtask_id"])
            retryable = bool(subtask and subtask.attempts < 3)
            return _json_text({**updated.to_dict(), "retryable": retryable, "next_mcp_tool": "rag_next_subtask"})

        if name == "rag_task_status":
            payload = await asyncio.to_thread(task_graph_status)
            return _json_text(payload)

        if name == "rag_task_step":
            payload = await asyncio.to_thread(task_step, arguments.get("task"))
            return _json_text(payload)

        if name == "rag_reflect_run":
            payload = await asyncio.to_thread(reflect_run)
            return _json_text(payload)

        if name == "rag_learn_from_outcome":
            payload = await asyncio.to_thread(learn_from_task_outcome, arguments.get("run_id"))
            return _json_text(payload)

        if name == "rag_edit_scope":
            payload = await asyncio.to_thread(describe_task, arguments["task"], target_agent="opencode")
            return _json_text(payload["edit_scope"])

        if name == "rag_missing_context":
            payload = await asyncio.to_thread(describe_task, arguments["task"], target_agent="opencode")
            missing = dict(payload["missing_context"])
            if arguments.get("selected_files"):
                missing["selected_files"] = list(arguments["selected_files"])
            return _json_text(missing)

        if name == "rag_find_tests":
            payload = await asyncio.to_thread(_related_tests_payload, arguments["path"])
            return _json_text(payload)

        if name == "rag_explain_file":
            payload = await asyncio.to_thread(_file_card_payload, arguments["path"], arguments.get("why_selected"))
            return _json_text(payload)

        if name == "rag_record_outcome":
            payload = await asyncio.to_thread(_record_outcome_payload, arguments)
            return _json_text(payload)

        if name == "rag_suggest_commands":
            commands = await asyncio.to_thread(
                suggest_commands,
                _repo_root(),
                list(arguments.get("selected_files", [])),
                arguments["task"],
            )
            return _json_text({"commands": commands})

        if name == "rag_perf_report":
            with db_conn() as conn:
                row = get_retrieval_run(conn, arguments["run_id"]) if arguments.get("run_id") else latest_retrieval_run(conn, infer_repo_filter(conn, None))
            if row is None:
                return _json_text({"slow_stages": [], "candidate_counts": {}, "packed_tokens": 0, "recommendations": []})
            payload = retrieval_run_payload(row)
            report = {
                "slow_stages": [stage for stage, value in payload["timings_ms"].items() if float(value) >= 150.0],
                "candidate_counts": payload["candidate_counts"],
                "packed_tokens": payload["packed_context_token_estimate"],
                "recommendations": [],
            }
            if payload["mode"] == "quick" and any(stage in report["slow_stages"] for stage in ("github", "test_failures", "errors")):
                report["recommendations"].append("keep quick mode on cheap channels only")
            if payload["packed_context_token_estimate"] >= 10000:
                report["recommendations"].append("trim packed context or rely more on summaries")
            return _json_text(report)

        if name == "rag_eval_query":
            payload = await asyncio.to_thread(
                evaluate_query,
                arguments["query"],
                mode=arguments.get("mode", "deep"),
            )
            payload.pop("result", None)
            return _json_text(payload)

        if name == "rag_context_git_refresh":
            r = _run_rag("context", "git", "--refresh", timeout=15)
            return _text(r.stdout or "Git context refreshed")

        if name == "rag_memory_status":
            with db_conn() as conn:
                repo = infer_repo_filter(conn, None)
                rows = repo_memory_status_rows(conn, repo)
            if not rows:
                return _text("No memory status")
            lines = [
                f"- {row['repo']}: memory={'yes' if row['has_memory'] else 'no'}, summaries={row['summary_count']}, chunks={row['chunk_count']}"
                for row in rows
            ]
            return _text("\n".join(lines))

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
    if not MCP_AVAILABLE:
        raise SystemExit("python package 'mcp' is required to run rag-mcp")
    async with mcp_stdio.stdio_server() as (read_stream, write_stream):
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
