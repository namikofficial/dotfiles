from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import uuid
import urllib.request
from datetime import datetime
from pathlib import Path

from qdrant_client import models
from rich.table import Table
from rich.progress import (
    BarColumn,
    MofNCompleteColumn,
    Progress,
    SpinnerColumn,
    TaskProgressColumn,
    TextColumn,
    TimeElapsedColumn,
    TimeRemainingColumn,
)

from .code_intel import tree_sitter_available
from .indexing import index_repo
from .llm import ask_llm, complete_llm, models_url
from .contracts import AgentPlan, Target
from .executors import executor_matrix, get_executor
from .learning import list_memory_candidates, review_memory_candidate
from .memory import (
    build_context_pack,
    generate_repo_memory,
    list_tool_taxonomy,
    refresh_file_summaries,
    repo_memory_status_rows,
    store_repo_memory,
    store_context_pack,
    write_context_pack_file,
)
from .retrieval import (
    approx_tokens,
    analysis_for_plan,
    build_retrieval_plan,
    RetrievalPlan,
    capture_git_context,
    expected_missing_context_categories,
    fact_hits,
    gather_context,
    print_retrieval_explain,
    reranker_enabled,
    row_file_type_match_count,
    row_path_match_count,
    row_symbol_match_count,
    retrieve,
)
from .runtime import CHUNKER_NAME, CONFIG_PATH, DB_PATH, INDEX_SCHEMA, console
from .model_registry import model_role_matrix
from .prompt_compiler import compile_prompt
from .router import build_agent_plan, target_from_flag
from .settings import (
    get_index_profile,
    get_mode_profile,
    load_config,
    missing_required_config_keys,
    required_config_key_paths,
    unknown_config_keys,
)
from .state import (
    add_command,
    add_decision,
    add_error,
    add_eval_case,
    add_test_failure,
    add_todo,
    compact_session,
    detect_memory_conflicts,
    eval_case_expected_files,
    extract_memory_from_compaction,
    format_operational_state,
    get_eval_case,
    get_session,
    list_git_contexts,
    list_github_contexts,
    list_commands,
    list_decisions,
    list_eval_cases,
    list_errors,
    list_memory_entries,
    list_session_compactions,
    list_sessions,
    list_test_failures,
    list_todos,
    load_operational_state,
    record_session,
    record_execution_run,
    remember_memory,
    save_handoff,
    session_compaction_details,
    session_files,
    upsert_github_context,
    update_todo_status,
)
from .storage import (
    collection_vector_size,
    connect_db,
    ensure_collection,
    get_embedder,
    get_qdrant,
    git_branch_for,
    infer_repo_filter,
    resolve_repo_name,
    repo_identity,
)
from .types import IndexInterrupted


SERVICE_HELPER = Path(__file__).resolve().parents[1] / "local-ai-runtime.sh"


def ensure_local_runtime(args: argparse.Namespace) -> None:
    for action, required in (
        ("ensure-qdrant", getattr(args, "needs_qdrant", False)),
        ("ensure-llm", getattr(args, "needs_llm", False)),
    ):
        if not required:
            continue
        if not SERVICE_HELPER.is_file():
            raise SystemExit(f"Missing runtime helper: {SERVICE_HELPER}")
        try:
            subprocess.run([str(SERVICE_HELPER), action], check=True)
        except subprocess.CalledProcessError as exc:
            label = "Qdrant" if action == "ensure-qdrant" else "local LLM"
            raise SystemExit(
                f"Unable to start {label.lower()} automatically. "
                f"Run `{SERVICE_HELPER.name} start` and retry."
            ) from exc


class SuggestingArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        suggestion = suggestion_for_argparse_error(message)
        if suggestion:
            message = f"{message}\n\nDid you mean: {suggestion}"
        super().error(message)


def suggestion_for_argparse_error(message: str) -> str | None:
    match = re.search(r"invalid choice: '([^']+)' \(choose from (.+)\)", message)
    if not match:
        return None
    entered = match.group(1)
    raw_choices = match.group(2)
    choices = re.findall(r"'([^']+)'", raw_choices)
    if not choices:
        choices = [choice.strip(" ,") for choice in raw_choices.split(",") if choice.strip(" ,")]
    close = difflib.get_close_matches(entered, choices, n=1, cutoff=0.55)
    if close:
        return close[0]
    prefix_matches = [choice for choice in choices if choice.startswith(entered[:2])]
    if prefix_matches:
        return prefix_matches[0]
    return None


RAG_WORKFLOWS = {
    "setup": [
        ("rag doctor --deep", "verify config, SQLite, Qdrant, embeddings, and answer model"),
        ("rag index --profile balanced", "index the current repo with facts and file summaries"),
        ("rag status", "check indexed repos, chunk counts, memory, and reranker settings"),
    ],
    "ask": [
        ('rag quick "what does this file do?"', "fast answer path for small questions"),
        ('rag deep "review this flow"', "larger context with repo memory and operational state"),
        ('rag ask --mode auto "why is auth failing?"', "let the router choose quick/deep/agent"),
    ],
    "debug": [
        ('rag search "AuthService.login" --explain', "show matching chunks and retrieval-stage counts"),
        ('rag inspect "AuthService.login"', "inspect query rewrites, intent, routing, and typo corrections"),
        ('rag missing "debug checkout failure"', "show what file categories retrieval expects"),
        ('rag why "checkout failure" src/checkout.ts', "explain why an indexed file did or did not rank"),
    ],
    "trace": [
        ("rag facts list --kind keybind", "browse extracted structured facts"),
        ("rag trace symbol AuthService", "trace an indexed symbol to nearby evidence"),
        ("rag graph AuthService", "show lightweight dependency edges from symbols or paths"),
    ],
    "state": [
        ("rag context git --refresh", "store current branch, status, and diff for retrieval"),
        ("rag context github pr 123", "ingest PR title, files, comments, linked issues, and checks"),
        ('rag context test-failure add "pytest -q" --output-file /tmp/failure.txt', "store failure output"),
        ('rag todo add "Refresh retrieval docs" --repo dotfiles', "track repo-scoped follow-up work"),
    ],
    "memory": [
        ("rag summarize", "refresh durable repo memory"),
        ("rag memory status", "show repo memory freshness and drift"),
        ("rag memory notes --scope all", "list developer memory notes"),
        ("rag memory pack dotfiles --target-agent codex --write-file", "write reusable handoff context"),
    ],
    "handoff": [
        ('rag agent "prepare implementation handoff" --target-agent codex --save-handoff', "generate a coding-agent packet"),
        ('rag handoff human "explain this subsystem"', "format a human-readable handoff"),
        ("rag session list", "find saved answers and handoffs"),
        ("rag session show <session-id>", "reopen a saved session"),
    ],
}


SUGGEST_ALIASES = {
    "health": "setup",
    "install": "setup",
    "index": "setup",
    "query": "ask",
    "answer": "ask",
    "find": "debug",
    "debugging": "debug",
    "explain": "debug",
    "fact": "trace",
    "facts": "trace",
    "symbol": "trace",
    "todo": "state",
    "github": "state",
    "git": "state",
    "context": "state",
    "remember": "memory",
    "pack": "memory",
    "agent": "handoff",
    "codex": "handoff",
}


def route_mode(query: str) -> tuple[str, str]:
    lowered = query.lower()
    terms = lowered.split()
    agent_markers = (
        "agent",
        "handoff",
        "codex",
        "copilot",
        "opencode",
        "implement",
        "migration",
        "multi-step",
        "prepare context",
        "task graph",
    )
    deep_markers = (
        "review",
        "architecture",
        "analyze",
        "debug",
        "investigate",
        "cleanup",
        "refactor",
        "plan",
        "workflow",
        "broken",
        "failing",
        "why",
    )
    if any(marker in lowered for marker in agent_markers):
        return "agent", "matched long-running implementation or handoff language"
    if "\n" in query or len(terms) >= 18 or any(marker in lowered for marker in deep_markers):
        return "deep", "matched analysis/debug depth heuristics"
    return "quick", "defaulted to the fast question path"


def resolved_mode(args: argparse.Namespace, config: dict) -> tuple[str, str]:
    requested = getattr(args, "mode", None) or config["routing"]["default_mode"]
    if requested and requested != "auto":
        return requested, f"explicit {requested} mode"
    return route_mode(args.query)


def optional_repo_memory(args: argparse.Namespace, result, mode_config: dict) -> str | None:
    use_memory = bool(mode_config["answer"]["use_memory"])
    if getattr(args, "memory", False):
        use_memory = True
    return result.memory["summary"] if use_memory and result.memory else None


def render_handoff(
    query: str,
    repo: str | None,
    route_reason: str,
    context: str,
    files: list[str],
    state_text: str | None,
    *,
    target_agent: str = "generic",
    missing_context: list[str] | None = None,
) -> str:
    file_lines = [f"- {item}" for item in files] if files else ["- none captured"]
    template_titles = {
        "generic": "Coding agent handoff",
        "codex": "Codex implementation handoff",
        "opencode": "OpenCode execution handoff",
        "copilot": "Copilot coding handoff",
        "human": "Human collaborator handoff",
    }
    template_steps = {
        "generic": [
            "- Re-open the important files and validate the retrieved context before editing.",
            "- Turn any incomplete items into concrete code/test tasks.",
            "- Keep changes small, then rerun the relevant tests.",
        ],
        "codex": [
            "- Start with the important files and convert the goal into precise code edits.",
            "- Preserve existing CLI surfaces unless a retrieved constraint requires otherwise.",
            "- Finish by rerunning the closest existing tests before handing back.",
        ],
        "opencode": [
            "- Use the retrieved files as the narrow execution scope.",
            "- Prefer patch-sized edits and keep shell commands reproducible.",
            "- Update tightly coupled docs/tests before closing the task.",
        ],
        "copilot": [
            "- Rehydrate the task from the retrieved context and operational memory first.",
            "- Keep the SQLite-first architecture intact while implementing the requested feature.",
            "- Return concise progress plus any residual risks after validation.",
        ],
        "human": [
            "- Read the goal and important files before planning any edits.",
            "- Validate assumptions against the retrieved context and operational state.",
            "- Use the suggested steps as a checklist for implementation and verification.",
        ],
    }
    sections = [
        f"# {template_titles.get(target_agent, template_titles['generic'])}",
        "",
        "## Goal",
        query,
        "",
        "## Target agent",
        target_agent,
        "",
        "## Target repo",
        repo or "unscoped",
        "",
        "## Constraints",
        "- Stay grounded in retrieved files and state.",
        "- Preserve current CLI compatibility surfaces unless the code demands otherwise.",
        "- Prefer retrieval/ranking/state improvements over extra helper-model chains.",
        "",
        "## Routing",
        f"- mode: agent",
        f"- reason: {route_reason}",
        "",
    ]
    if state_text:
        sections.extend(["## Operational state", state_text, ""])
    sections.extend(
        [
            "## Important files",
            *file_lines,
            "",
            "## Retrieved context",
            context or "No context packed.",
            "",
            "## Suggested first steps",
            *template_steps.get(target_agent, template_steps["generic"]),
        ]
    )
    if missing_context:
        sections.extend(
            [
                "",
                "## Missing context checklist",
                *[f"- {humanize_missing_label(item)}" for item in missing_context],
            ]
        )
    return "\n".join(sections).strip()


SECRET_PATTERN = re.compile(
    r"(?i)(password|passwd|secret|token|api[_-]?key|authorization|cookie|session|private[_-]?key|aws_secret_access_key)"
)
REDACT_ASSIGNMENT_PATTERN = re.compile(r"(?i)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|KEY)[A-Z0-9_]*)=([^\s]+)")


def retrieve_for_cli(
    query: str,
    *,
    repo: str | None,
    mode: str,
    rerank: bool | None = None,
) -> tuple[sqlite3.Connection, dict, str | None, object]:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    resolved_repo = infer_repo_filter(conn, repo)
    effective_config = get_mode_profile(config, mode)
    result = retrieve(
        conn,
        client,
        effective_config,
        query,
        resolved_repo,
        reranker_enabled(effective_config, rerank),
        mode=mode,
    )
    return conn, effective_config, resolved_repo, result


def humanize_missing_label(label: str) -> str:
    mapping = {
        "definition file": "definition / service file",
        "caller file": "caller / route entry file",
        "test file": "test coverage",
        "config file": "config or env file",
        "schema/entity file": "schema / entity / model file",
        "related docs": "docs / troubleshooting notes",
        "error log": "recent error logs",
    }
    return mapping.get(label, label)


def compact_file_refs(items: list[str], limit: int = 6) -> list[str]:
    normalized: list[str] = []
    for item in items:
        base = item.split(":", 1)[0]
        if base not in normalized:
            normalized.append(base)
    return normalized[:limit]


def format_duration(seconds: float) -> str:
    seconds = max(0, int(seconds))
    hours, remainder = divmod(seconds, 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{hours}h{minutes:02d}m{secs:02d}s"
    if minutes:
        return f"{minutes}m{secs:02d}s"
    return f"{secs}s"


def shorten_progress_path(path: str, limit: int = 48) -> str:
    if len(path) <= limit:
        return path
    return "..." + path[-(limit - 3):]


def make_index_progress() -> Progress:
    return Progress(
        SpinnerColumn(),
        TextColumn("[bold cyan]{task.description}"),
        BarColumn(bar_width=24),
        MofNCompleteColumn(),
        TaskProgressColumn(),
        TextColumn("elapsed"),
        TimeElapsedColumn(),
        TextColumn("eta"),
        TimeRemainingColumn(),
        TextColumn("changed {task.fields[changed]} skipped {task.fields[skipped]} chunks {task.fields[chunks]}"),
        TextColumn("{task.fields[rate]}"),
        TextColumn("[dim]{task.fields[current]}[/dim]"),
        console=console,
        refresh_per_second=2,
    )


def make_index_progress_callback(progress: Progress, label: str):
    task_id: int | None = None
    started_at = time.monotonic()
    fields = {"changed": 0, "skipped": 0, "chunks": 0}

    def callback(event: dict[str, object]) -> None:
        nonlocal task_id, started_at
        event_name = str(event.get("event", ""))
        if event_name == "start":
            started_at = time.monotonic()
            task_id = progress.add_task(
                label,
                total=int(event.get("total_files", 0)),
                changed=0,
                skipped=0,
                chunks=0,
                rate="0.0 files/s",
                current="scanning complete",
            )
            return
        if task_id is None:
            return
        processed = int(event.get("processed_files", 0))
        elapsed = max(0.001, time.monotonic() - started_at)
        rate = f"{processed / elapsed:.1f} files/s"
        fields["changed"] = int(event.get("changed_files", fields["changed"]))
        fields["skipped"] = int(event.get("skipped_files", fields["skipped"]))
        fields["chunks"] = int(event.get("total_chunks", fields["chunks"]))
        update = {
            "completed": processed,
            "changed": fields["changed"],
            "skipped": fields["skipped"],
            "chunks": fields["chunks"],
            "rate": rate,
        }
        if "path" in event:
            update["current"] = shorten_progress_path(str(event["path"]))
        if event_name == "cleanup":
            update["current"] = f"cleanup: {int(event.get('removed_files', 0))} removed"
        if event_name == "finish":
            update["current"] = "done"
        progress.update(task_id, **update)

    return callback


def sanitize_imported_command(command: str) -> str | None:
    stripped = command.strip()
    if not stripped:
        return None
    if SECRET_PATTERN.search(stripped):
        return None
    redacted = REDACT_ASSIGNMENT_PATTERN.sub(r"\1=<redacted>", stripped)
    if "://" in redacted:
        redacted = re.sub(r"://([^/\s:@]+):([^/\s@]+)@", r"://\1:<redacted>@", redacted)
    return redacted


def parse_zsh_history_line(line: str) -> tuple[str, int | None] | None:
    stripped = line.strip()
    if not stripped:
        return None
    match = re.match(r"^:\s+\d+:(\d+);(.*)$", stripped)
    if match:
        return match.group(2).strip(), None
    return stripped, None


def expected_files_from_result(result, *, limit: int = 6) -> list[str]:
    file_refs = [row["path"] for row in result.rows[:limit]]
    file_refs.extend(row["path"] for row in result.summaries[:limit])
    return compact_file_refs(file_refs, limit=limit)


def render_markdown_pack(query: str, mode: str, route_reason: str, context: str, files: list[str], debug: dict) -> str:
    file_lines = [f"- {item}" for item in files[:12]] or ["- none"]
    sections = [
        f"# Query pack: {query}",
        "",
        f"- mode: {mode}",
        f"- route: {route_reason}",
        f"- intent: {debug.get('intent', '-')}",
        "",
        "## Files",
        *file_lines,
        "",
        "## Retrieval",
        f"- rewrites: {len(debug.get('rewrites', []))}",
        f"- selected chunks: {len(files)}",
        f"- missing-context desired: {', '.join(debug.get('missing_context_desired', [])) or '-'}",
        "",
        "## Context",
        "```text",
        context.strip(),
        "```",
    ]
    return "\n".join(sections).strip()


def render_query_inspection(result, mode: str, route_reason: str) -> str:
    analysis = result.plan.analysis
    expected = [humanize_missing_label(item) for item in expected_missing_context_categories(result.plan)]
    lines = [
        f"intent: {result.plan.intent}",
        f"mode: {mode}",
        f"route reason: {route_reason}",
        "expanded queries:",
        *[f"- {rewrite}" for rewrite in result.plan.rewrites],
    ]
    if analysis is not None:
        if analysis.corrected_terms:
            lines.extend(["typo corrections:", *[f"- {term}" for term in analysis.corrected_terms]])
        if analysis.preferred_languages or analysis.preferred_kinds:
            preferred = [
                *[f"language:{item}" for item in analysis.preferred_languages],
                *[f"kind:{item}" for item in analysis.preferred_kinds],
                *[f"path:{item}" for item in analysis.preferred_paths],
            ]
            lines.extend(["preferences:", *[f"- {item}" for item in preferred[:10]]])
    if expected:
        lines.extend(["expected files:", *[f"- {item}" for item in expected]])
    return "\n".join(lines)


def run_query_mode(args: argparse.Namespace) -> int:
    timings: list[tuple[str, float]] = []
    stage_started = time.perf_counter()

    def mark(stage: str) -> None:
        nonlocal stage_started
        now = time.perf_counter()
        timings.append((stage, (now - stage_started) * 1000))
        stage_started = now

    config = load_config()
    mode, route_reason = resolved_mode(args, config)
    effective_config = get_mode_profile(config, mode)
    mark("config")
    conn = connect_db()
    client = get_qdrant(effective_config)
    repo = infer_repo_filter(conn, getattr(args, "repo", None))
    mark("connect")
    result = retrieve(
        conn,
        client,
        effective_config,
        args.query,
        repo,
        reranker_enabled(effective_config, getattr(args, "rerank", None)),
        mode=mode,
    )
    mark("retrieve")
    if not result.rows:
        console.print("[yellow]No indexed context matched that query.[/yellow]")
        return 1
    state_text: str | None = None
    if effective_config["answer"]["use_operational_state"]:
        state_text = format_operational_state(load_operational_state(conn, repo))
        mark("operational_state")
    context, files = gather_context(
        result.rows,
        effective_config,
        facts=result.facts,
        summaries=result.summaries,
        context_sources=result.context_sources,
        memory=optional_repo_memory(args, result, effective_config),
        operational_state=state_text,
        operational_state_tokens=int(effective_config["answer"]["operational_state_tokens"]),
    )
    mark("context_pack")
    if getattr(args, "show_context", False):
        print_retrieval_explain(result.debug, result.rows)
        console.print(f"\n[bold]Route:[/bold] {mode} ({route_reason})")
        console.print("\n[bold]Context:[/bold]")
        console.print(context)
        console.print()
    target_agent = getattr(args, "target_agent", "generic")
    if mode == "agent" and getattr(args, "output_format", "handoff") == "handoff":
        output = render_handoff(
            args.query,
            repo,
            route_reason,
            context,
            files,
            state_text,
            target_agent=target_agent,
            missing_context=list(result.debug.get("missing_context_remaining", [])),
        )
        console.print(output)
        session_id = record_session(conn, repo, mode, args.query, route_reason, "handoff", output, files)
        compact_session(conn, session_id)
        if getattr(args, "save_handoff", False):
            handoff_path = save_handoff(repo, args.query, output)
            console.print(f"\n[green]Saved[/green] handoff to {handoff_path}")
        console.print(f"\n[dim]Session {session_id} saved.[/dim]")
        return 0
    answer = ask_llm(effective_config, args.query, context, mode=mode)
    mark("llm")
    console.print(f"[bold]{mode.title()} answer:[/bold]")
    console.print(answer or "[red]No answer returned.[/red]")
    console.print("\n[bold]Relevant files:[/bold]")
    for item in files:
        console.print(f"- {item}")
    session_id = record_session(conn, repo, mode, args.query, route_reason, "answer", answer, files)
    if mode in {"deep", "agent"}:
        compact_session(conn, session_id)
        mark("compact")
    console.print(f"\n[dim]Session {session_id} saved.[/dim]")
    if os.environ.get("RAG_TIMINGS"):
        console.print("\n[bold]Timings:[/bold]")
        for stage, elapsed_ms in timings:
            console.print(f"- {stage}: {elapsed_ms:.1f}ms")
    return 0


def _context_for_agent_plan(plan: AgentPlan, *, rerank: bool | None = None) -> tuple[sqlite3.Connection, dict, str]:
    config = load_config()
    effective_config = get_mode_profile(config, plan.mode)
    effective_config["retrieval_pipeline"]["semantic_limit"] = plan.retrieval_semantic_limit
    effective_config["retrieval_pipeline"]["keyword_limit"] = plan.retrieval_keyword_limit
    conn = connect_db()
    client = get_qdrant(effective_config)
    result = retrieve(
        conn,
        client,
        effective_config,
        plan.task,
        plan.repo if plan.repo != "unscoped" else None,
        reranker_enabled(effective_config, rerank),
        mode=plan.mode,
    )
    state_text: str | None = None
    if plan.context.include_git or plan.context.include_test_failures or plan.context.include_recent_errors:
        state_text = format_operational_state(load_operational_state(conn, plan.repo))
    context, _files = gather_context(
        result.rows,
        effective_config,
        facts=result.facts,
        summaries=result.summaries,
        context_sources=result.context_sources if plan.context.include_git or plan.context.include_github else [],
        memory=result.memory["summary"] if plan.context.include_memory and result.memory else None,
        operational_state=state_text,
        operational_state_tokens=int(effective_config["answer"]["operational_state_tokens"]),
    )
    return conn, effective_config, context


def render_agent_plan_json(plan: AgentPlan) -> str:
    return json.dumps(plan.to_dict(), indent=2, sort_keys=True)


def cmd_v7_plan(args: argparse.Namespace) -> int:
    conn = connect_db()
    plan = build_agent_plan(
        args.query,
        conn=conn,
        repo=getattr(args, "repo", None),
        explicit_target=target_from_flag(getattr(args, "target", None)),
    )
    console.print(render_agent_plan_json(plan))
    return 0


def cmd_v7_context(args: argparse.Namespace) -> int:
    ensure_local_runtime(argparse.Namespace(needs_qdrant=True, needs_llm=False))
    conn = connect_db()
    plan = build_agent_plan(
        args.query,
        conn=conn,
        repo=getattr(args, "repo", None),
        explicit_target=target_from_flag(getattr(args, "target", None)),
    )
    conn.close()
    context_conn, _config, context = _context_for_agent_plan(plan, rerank=getattr(args, "rerank", None))
    prompt = compile_prompt(plan, context)
    console.print("[bold]Context summary[/bold]")
    console.print(prompt.context_summary)
    console.print("\n[bold]AgentPlan[/bold]")
    console.print(render_agent_plan_json(plan))
    console.print("\n[bold]Compiled context[/bold]")
    console.print(context or "No context packed.")
    context_conn.close()
    return 0


def cmd_v7_execute(args: argparse.Namespace) -> int:
    ensure_local_runtime(argparse.Namespace(needs_qdrant=True, needs_llm=False))
    conn = connect_db()
    plan = build_agent_plan(
        args.query,
        conn=conn,
        repo=getattr(args, "repo", None),
        explicit_target=target_from_flag(args.target),
    )
    conn.close()
    context_conn, _config, context = _context_for_agent_plan(plan, rerank=getattr(args, "rerank", None))
    prompt = compile_prompt(plan, context)
    executor = get_executor(plan.target)
    ok, reason = executor.available()
    if not ok:
        console.print(f"[red]{plan.target} unavailable:[/red] {reason}")
        return 1
    run_id = str(uuid.uuid4())
    prompt_hash = hashlib.sha256(prompt.text().encode("utf-8")).hexdigest()
    if getattr(args, "dry_run", False) or plan.target in {"copy", "local-answer"}:
        output = executor.dry_run(prompt, plan) if getattr(args, "dry_run", False) else prompt.text()
        console.print(output)
        record_execution_run(
            context_conn,
            run_id=run_id,
            session_id=plan.session_id,
            repo=plan.repo,
            target=plan.target,
            profile_id=plan.profile,
            intent=plan.intent,
            mode=plan.mode,
            risk_level=plan.risk_level,
            query=plan.task,
            prompt_hash=prompt_hash,
            agent_plan=plan.to_dict(),
            status="dry_run" if getattr(args, "dry_run", False) else "printed",
            stdout=output,
            files_modified=[],
        )
        context_conn.close()
        return 0
    started = time.time()
    record_execution_run(
        context_conn,
        run_id=run_id,
        session_id=plan.session_id,
        repo=plan.repo,
        target=plan.target,
        profile_id=plan.profile,
        intent=plan.intent,
        mode=plan.mode,
        risk_level=plan.risk_level,
        query=plan.task,
        prompt_hash=prompt_hash,
        agent_plan=plan.to_dict(),
        status="running",
        started_at=started,
    )
    result = executor.run(prompt, plan)
    record_execution_run(
        context_conn,
        run_id=run_id,
        session_id=plan.session_id,
        repo=plan.repo,
        target=plan.target,
        profile_id=plan.profile,
        intent=plan.intent,
        mode=plan.mode,
        risk_level=plan.risk_level,
        query=plan.task,
        prompt_hash=prompt_hash,
        agent_plan=plan.to_dict(),
        status="success" if result.success else "failed",
        stdout=result.stdout,
        stderr=result.stderr,
        exit_code=result.exit_code,
        duration_ms=result.duration_ms,
        files_modified=result.files_modified,
        started_at=started,
        finished_at=time.time(),
    )
    console.print(result.stdout)
    if result.stderr:
        console.print(result.stderr)
    context_conn.close()
    return result.exit_code


def cmd_learn(args: argparse.Namespace) -> int:
    conn = connect_db()
    if getattr(args, "candidate_id", None) and getattr(args, "review_status", None):
        if not review_memory_candidate(conn, args.candidate_id, args.review_status, content=getattr(args, "content", None)):
            console.print(f"[red]No memory candidate found:[/red] {args.candidate_id}")
            return 1
    rows = list_memory_candidates(conn, status=args.status, limit=args.limit)
    table = Table(title="Memory candidates")
    table.add_column("id")
    table.add_column("status")
    table.add_column("kind")
    table.add_column("confidence")
    table.add_column("content")
    for row in rows:
        table.add_row(row["id"], row["status"], row["kind"], f"{row['confidence']:.2f}", row["content"][:90])
    console.print(table)
    return 0


def cmd_skill(args: argparse.Namespace) -> int:
    """Manage auto-generated OpenCode skills."""
    import collections
    import re as _re

    skills_auto_dir = Path("~/.codex/skills/auto").expanduser()
    repo_skills_dir = Path(__file__).parent.parent.parent / "configs" / "opencode" / "skills"

    if args.skill_command == "list":
        all_skills: list[tuple[str, Path]] = []
        for base, label in [(repo_skills_dir, "repo"), (skills_auto_dir, "auto")]:
            if base.exists():
                for p in sorted(base.iterdir()):
                    if p.is_dir() and (p / "SKILL.md").exists():
                        all_skills.append((label, p / "SKILL.md"))
        if not all_skills:
            console.print("[yellow]No skills found.[/yellow]")
            return 0
        table = Table(title="OpenCode skills")
        table.add_column("source")
        table.add_column("name")
        table.add_column("path")
        for label, p in all_skills:
            table.add_row(label, p.parent.name, str(p))
        console.print(table)
        return 0

    if args.skill_command == "generate":
        conn = connect_db()
        repo = resolve_repo_name(conn, getattr(args, "repo", None))
        rows = list_session_compactions(conn, repo if not getattr(args, "global_scope", False) else None, limit=100)
        if len(rows) < 3:
            console.print("[yellow]Not enough sessions to generate skills (need ≥ 3).[/yellow]")
            return 0

        # Count query patterns by prefix words to find common task categories
        category_counter: dict[str, list[str]] = collections.defaultdict(list)
        keyword_groups = {
            "debug": ["debug", "error", "fix", "broken", "fail", "crash", "issue"],
            "refactor": ["refactor", "clean", "restructure", "extract", "rename"],
            "implement": ["implement", "add", "create", "build", "write", "new"],
            "review": ["review", "check", "inspect", "audit", "analyze"],
            "migration": ["migrate", "migration", "upgrade", "update", "convert"],
            "test": ["test", "spec", "coverage", "assert", "mock"],
            "document": ["document", "docs", "readme", "explain", "describe"],
            "deploy": ["deploy", "release", "package", "build", "ci"],
        }
        for row in rows:
            summary = str(row["summary"]).lower()
            for category, keywords in keyword_groups.items():
                if any(kw in summary for kw in keywords):
                    category_counter[category].append(str(row["summary"]))

        skills_auto_dir.mkdir(parents=True, exist_ok=True)
        generated = 0
        for category, examples in category_counter.items():
            if len(examples) < 3:
                continue
            skill_dir = skills_auto_dir / category
            skill_file = skill_dir / "SKILL.md"
            if skill_file.exists() and not getattr(args, "force", False):
                continue
            skill_dir.mkdir(parents=True, exist_ok=True)
            examples_text = "\n".join(f"- {e[:120]}" for e in examples[:5])
            config = load_config()
            system = (
                "You generate concise OpenCode skill files. A skill file has three required sections: "
                "## Trigger (when to use), ## Steps (numbered instructions), ## Do not (anti-patterns). "
                "Be specific, not generic. No more than 300 words."
            )
            prompt = (
                f"Generate a SKILL.md for the '{category}' task category. "
                f"These are real examples from this project:\n{examples_text}\n\n"
                "Output only the markdown skill file starting with `# {Title}`."
            )
            try:
                content = complete_llm(config, system, prompt, max_tokens=600)
                if not all(section in content for section in ("##", "## ")):
                    continue
                skill_file.write_text(content.strip() + "\n")
                console.print(f"[green]Generated[/green] skill: {category} → {skill_file}")
                generated += 1
            except Exception as exc:  # noqa: BLE001
                console.print(f"[yellow]Skipped {category}:[/yellow] {exc}")

        if generated == 0:
            console.print("[dim]No new skills generated (need ≥ 3 matching sessions per category, or use --force).[/dim]")
        else:
            console.print(f"\n[bold]{generated}[/bold] skill(s) written to {skills_auto_dir}")
        return 0

    raise SystemExit(f"Unknown skill command: {args.skill_command}")




def cmd_mcp(_args: argparse.Namespace) -> int:
    from .server import run_mcp_stdio

    return run_mcp_stdio()


def _resolve_task_file(agent_dir: Path) -> Path:
    """Return the most recent task file in agent_dir, falling back to task.md."""
    timestamped = sorted(agent_dir.glob("task-*.md"), key=lambda p: p.name, reverse=True)
    if timestamped:
        return timestamped[0]
    return agent_dir / "task.md"


def cmd_task(args: argparse.Namespace) -> int:
    """Manage .agent/ task workflow files."""
    repo_root = Path.cwd()
    # Walk up to find .git root
    candidate = repo_root
    while candidate != candidate.parent:
        if (candidate / ".git").exists():
            repo_root = candidate
            break
        candidate = candidate.parent
    agent_dir = repo_root / ".agent"

    if args.task_command == "init":
        agent_dir.mkdir(exist_ok=True)
        task_file = agent_dir / "task.md"
        task_content = f"""# Current Task

## User Request

{args.description}

## Goal

<!-- What must be true when done -->

## Constraints

- Keep changes minimal.
- Prefer existing project patterns.
- Do not rewrite unrelated code.
- Run checks before final response.

## Relevant Context

<!-- RAG populates this via rag task context -->

## Plan

- [ ] Understand task
- [ ] Retrieve relevant code context
- [ ] Inspect files
- [ ] Edit files
- [ ] Run checks
- [ ] Fix failures
- [ ] Update memory

## Work Log

<!-- Agent appends progress -->

## Final Summary

<!-- Agent fills at end -->

*Task initialized: {datetime.now().isoformat()}*
"""
        task_file.write_text(task_content)
        for fname in ("memory.md", "decisions.md", "checks.md", "handoff.md"):
            p = agent_dir / fname
            if not p.exists():
                p.touch()
        console.print(f"[green]Task initialized[/green] in {agent_dir}")
        console.print("[dim]Run 'rag task context' to populate context, or open OpenCode.[/dim]")
        return 0

    if args.task_command == "context":
        task_file = _resolve_task_file(agent_dir)
        if not task_file.exists():
            raise SystemExit("No task found. Run 'rag task init \"<description>\"' first.")
        description = ""
        for line in task_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("<!--") and not line.startswith("*"):
                description = line
                break
        console.print("[cyan]Refreshing git context...[/cyan]")
        subprocess.run(
            [sys.executable, "-m", "rag.cli", "context", "git", "--refresh"],
            cwd=repo_root,
        )
        target = getattr(args, "target_agent", "opencode")
        console.print(f"[cyan]Building agent handoff for:[/cyan] {description}")
        result = subprocess.run(
            [sys.executable, "-m", "rag.cli", "agent", description,
             "--target-agent", target, "--save-handoff"],
            cwd=repo_root,
        )
        return result.returncode

    if args.task_command == "done":
        task_file = _resolve_task_file(agent_dir)
        if not task_file.exists():
            raise SystemExit("No task found.")
        summary = getattr(args, "summary", None) or "Task completed."
        content = task_file.read_text()
        ts = datetime.now().isoformat()
        content = content.replace(
            "<!-- Agent fills at end -->",
            f"{summary}\n\n*Completed: {ts}*",
        )
        task_file.write_text(content)
        console.print(f"[green]Task marked done.[/green] Summary written to {task_file}")
        return 0

    if args.task_command == "list":
        task_files = sorted(agent_dir.glob("task*.md"), key=lambda p: p.stat().st_mtime, reverse=True)
        if (agent_dir / "task.md").exists():
            t = agent_dir / "task.md"
            if t not in task_files:
                task_files.insert(0, t)
        if not task_files:
            console.print("[yellow]No task files found in .agent/[/yellow]")
            return 0
        table = Table(title=f"Tasks in {agent_dir}")
        table.add_column("file")
        table.add_column("modified")
        table.add_column("preview")
        for tf in task_files[:20]:
            import datetime as _dt

            mtime = _dt.datetime.fromtimestamp(tf.stat().st_mtime).strftime("%Y-%m-%d %H:%M")
            first_line = ""
            for ln in tf.read_text().splitlines():
                ln = ln.strip()
                if ln and not ln.startswith("#") and not ln.startswith("<!--") and not ln.startswith("*"):
                    first_line = ln[:80]
                    break
            table.add_row(tf.name, mtime, first_line)
        console.print(table)
        return 0

    raise SystemExit(f"Unknown task command: {args.task_command}")


def cmd_serve(args: argparse.Namespace) -> int:
    if not args.http:
        raise SystemExit("Use `rag serve --http` to start the HTTP integration server.")
    from .server import run_http

    return run_http(args.host, args.port)


def cmd_index(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    root = Path(args.path).expanduser().resolve()
    profile_name, profile = get_index_profile(config, args.profile)
    console.print(f"[cyan]Indexing[/cyan] {root} ...")
    try:
        with make_index_progress() as progress:
            changed_files, total_chunks = index_repo(
                conn,
                client,
                config,
                root,
                changed_only=args.changed_only,
                profile=profile,
                progress_callback=make_index_progress_callback(progress, f"index {root.name}"),
            )
    except IndexInterrupted as exc:
        elapsed = f" after {format_duration(exc.elapsed_seconds)}" if exc.elapsed_seconds else ""
        progress_text = (
            f" Processed {exc.processed_files}/{exc.total_files} files."
            if exc.total_files
            else ""
        )
        console.print(
            f"[yellow]Cancelled{elapsed}.[/yellow] Kept {exc.changed_files} completed files "
            f"and {exc.total_chunks} chunks.{progress_text} "
            "Rerun [bold]rag index --changed-only[/bold] to continue from the current directory."
        )
        return 130
    if profile["repo_memory"]:
        repo = repo_identity(root)[1]
        console.print(f"[cyan]Refreshing repo memory[/cyan] for {repo} ...")
        store_repo_memory(conn, repo, generate_repo_memory(conn, config, repo))
    console.print(
        f"[green]Indexed[/green] {changed_files} files and {total_chunks} chunks from {root} "
        f"(profile: {profile_name})"
    )
    return 0


def cmd_reindex(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    profile_name, profile = get_index_profile(config, args.profile)
    repos = conn.execute("SELECT root FROM indexed_repos ORDER BY repo").fetchall()
    if not repos:
        console.print("[yellow]No repos indexed yet.[/yellow]")
        return 0
    total_files = 0
    total_chunks = 0
    for row in repos:
        root = Path(row["root"])
        console.print(f"[cyan]Reindexing[/cyan] {root} ...")
        try:
            with make_index_progress() as progress:
                changed_files, chunks = index_repo(
                    conn,
                    client,
                    config,
                    root,
                    changed_only=True,
                    profile=profile,
                    progress_callback=make_index_progress_callback(progress, f"reindex {root.name}"),
                )
        except IndexInterrupted as exc:
            total_files += exc.changed_files
            total_chunks += exc.total_chunks
            elapsed = f" after {format_duration(exc.elapsed_seconds)}" if exc.elapsed_seconds else ""
            progress_text = (
                f" Processed {exc.processed_files}/{exc.total_files} files in the interrupted repo."
                if exc.total_files
                else ""
            )
            console.print(
                f"[yellow]Cancelled{elapsed}.[/yellow] Kept {total_files} completed files "
                f"and {total_chunks} chunks so far.{progress_text}"
            )
            return 130
        total_files += changed_files
        total_chunks += chunks
        if profile["repo_memory"]:
            repo = repo_identity(root)[1]
            console.print(f"[cyan]Refreshing repo memory[/cyan] for {repo} ...")
            store_repo_memory(conn, repo, generate_repo_memory(conn, config, repo))
    console.print(f"[green]Reindexed[/green] {total_files} changed files and {total_chunks} chunks (profile: {profile_name})")
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    collection_name = config["qdrant_collection"]
    points = 0
    qdrant_status = "stopped"
    try:
        client = get_qdrant(config)
        if client.collection_exists(collection_name):
            points = int(client.get_collection(collection_name).points_count or 0)
        qdrant_status = "running"
    except Exception:
        client = None
    console.print("[bold]RAG status[/bold]")
    console.print(f"Config: {CONFIG_PATH}")
    console.print(f"SQLite: {DB_PATH}")
    console.print(f"Qdrant: {config['qdrant_url']} ({qdrant_status})")
    console.print(f"Collection: {collection_name}")
    console.print()
    console.print(f"Repos indexed: {conn.execute('SELECT COUNT(*) FROM indexed_repos').fetchone()[0]}")
    console.print(f"Chunks: {conn.execute('SELECT COUNT(*) FROM chunks').fetchone()[0]}")
    console.print(f"Facts: {conn.execute('SELECT COUNT(*) FROM facts').fetchone()[0]}")
    console.print(f"File summaries: {conn.execute('SELECT COUNT(*) FROM file_summaries').fetchone()[0]}")
    console.print(f"Repo memories: {conn.execute('SELECT COUNT(*) FROM repo_memory').fetchone()[0]}")
    console.print(f"Memory notes: {conn.execute('SELECT COUNT(*) FROM developer_memory').fetchone()[0]}")
    console.print(f"Context packs: {conn.execute('SELECT COUNT(*) FROM context_packs').fetchone()[0]}")
    console.print(f"Git snapshots: {conn.execute('SELECT COUNT(*) FROM git_context').fetchone()[0]}")
    console.print(f"GitHub refs: {conn.execute('SELECT COUNT(*) FROM github_context').fetchone()[0]}")
    console.print(f"Test failures: {conn.execute('SELECT COUNT(*) FROM test_failure_memory').fetchone()[0]}")
    console.print(f"Todos: {conn.execute('SELECT COUNT(*) FROM task_todos').fetchone()[0]}")
    console.print(f"Decisions: {conn.execute('SELECT COUNT(*) FROM task_decisions').fetchone()[0]}")
    console.print(f"Sessions: {conn.execute('SELECT COUNT(*) FROM task_sessions').fetchone()[0]}")
    console.print(f"Session compactions: {conn.execute('SELECT COUNT(*) FROM session_compactions').fetchone()[0]}")
    console.print(f"Embedding model: {config['embedding_model']}")
    console.print(f"Answer model: {config['answer_model']}")
    console.print(
        "Reranker: "
        + ("enabled" if config["reranker"]["enabled"] else "disabled")
        + f" ({config['reranker']['mode']})"
    )
    profile_name, _profile = get_index_profile(config, None)
    console.print(f"Index profile: {profile_name}")
    console.print(
        "Context budget: "
        f"{config['context_budget']['total_tokens']} total / "
        f"{config['context_budget']['memory_tokens']} memory / "
        f"{config['context_budget']['facts_tokens']} facts / "
        f"{config['context_budget']['file_summary_tokens']} summaries / "
        f"{config['context_budget']['chunk_tokens']} chunks / "
        f"{config['context_budget']['reserved_answer_tokens']} answer reserve"
    )
    console.print(
        "Retrieval diversity: "
        f"{config['retrieval']['max_chunks_per_file']} chunks/file, "
        f"{config['retrieval']['max_fact_files']} fact files, "
        f"{config['retrieval']['max_summary_files']} summary files"
    )
    memory_statuses = repo_memory_status_rows(conn)
    if memory_statuses:
        fresh = sum(1 for row in memory_statuses if row["status"] == "fresh")
        stale = sum(1 for row in memory_statuses if row["status"] == "stale")
        missing = sum(1 for row in memory_statuses if row["status"] == "missing")
        console.print(f"Repo memory freshness: {fresh} fresh, {stale} stale, {missing} missing")
    console.print("Last indexed:")
    rows = conn.execute(
        "SELECT repo, root, last_indexed FROM indexed_repos ORDER BY last_indexed DESC"
    ).fetchall()
    if not rows:
        console.print("- none")
    for row in rows:
        stamp = datetime.fromtimestamp(row["last_indexed"]).strftime("%Y-%m-%d %H:%M")
        console.print(f"- {row['repo']}  {stamp}  {row['root']}")
    console.print(f"Qdrant points: {points}")
    return 0


def cmd_route(args: argparse.Namespace) -> int:
    """Show model routing decision for a query."""
    from .llm import _approx_tokens, _task_complexity, _select_model  # noqa: PLC0415
    config = load_config()
    question = args.query
    context = args.context or ""
    tokens = _approx_tokens(question + context)
    complexity = _task_complexity(question, context)
    model_id, endpoint = _select_model(config, complexity)
    console.print("[bold]Route diagnosis[/bold]")
    console.print(f"Query:      {question[:80]}{'...' if len(question) > 80 else ''}")
    console.print(f"Tokens:     ~{tokens}")
    console.print(f"Complexity: {complexity}")
    console.print(f"Model:      {model_id}")
    console.print(f"Endpoint:   {endpoint}")
    return 0


def cmd_clean(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    ensure_collection(client, config)
    if args.all:
        if client.collection_exists(config["qdrant_collection"]):
            client.delete_collection(config["qdrant_collection"])
        conn.execute("DELETE FROM chunks")
        conn.execute("DELETE FROM chunks_fts")
        conn.execute("DELETE FROM facts")
        conn.execute("DELETE FROM file_summaries")
        conn.execute("DELETE FROM repo_memory")
        conn.execute("DELETE FROM developer_memory")
        conn.execute("DELETE FROM context_packs")
        conn.execute("DELETE FROM git_context")
        conn.execute("DELETE FROM github_context")
        conn.execute("DELETE FROM indexed_repos")
        conn.execute("DELETE FROM task_todos")
        conn.execute("DELETE FROM task_decisions")
        conn.execute("DELETE FROM command_memory")
        conn.execute("DELETE FROM error_memory")
        conn.execute("DELETE FROM test_failure_memory")
        conn.execute("DELETE FROM task_sessions")
        conn.execute("DELETE FROM session_compactions")
        conn.commit()
        ensure_collection(client, config)
        console.print("[green]Cleared[/green] all local RAG state")
        return 0
    repo = args.repo
    if not repo:
        raise SystemExit("Use rag clean --repo <name> or rag clean --all")
    rows = conn.execute("SELECT chunk_id FROM chunks WHERE repo = ?", (repo,)).fetchall()
    ids = [row["chunk_id"] for row in rows]
    if ids:
        client.delete(
            collection_name=config["qdrant_collection"],
            points_selector=models.PointIdsList(points=ids),
            wait=True,
        )
    conn.execute("DELETE FROM chunks WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM chunks_fts WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM facts WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM file_summaries WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM repo_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM developer_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM context_packs WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM git_context WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM github_context WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM indexed_repos WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM task_todos WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM task_decisions WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM command_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM error_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM test_failure_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM task_sessions WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM session_compactions WHERE repo = ?", (repo,))
    conn.commit()
    console.print(f"[green]Cleared[/green] repo state for {repo}")
    return 0


def fetch_github_context_from_gh(root: Path, ref_type: str, ref_number: int) -> dict[str, object]:
    if ref_type == "pr":
        payload = json.loads(
            subprocess.check_output(
                [
                    "gh",
                    "pr",
                    "view",
                    str(ref_number),
                    "--json",
                    "title,body,files,comments,reviews,closingIssuesReferences",
                ],
                cwd=str(root),
                text=True,
            )
        )
        ci_logs = ""
        try:
            ci_logs = subprocess.check_output(
                ["gh", "pr", "checks", str(ref_number)],
                cwd=str(root),
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
        except subprocess.CalledProcessError:
            ci_logs = ""
        return {
            "title": payload.get("title", ""),
            "body": payload.get("body", ""),
            "changed_files": [row.get("path", "") for row in payload.get("files", []) if row.get("path")],
            "comments": [row.get("body", "") for row in payload.get("comments", []) if row.get("body")],
            "review_comments": [row.get("body", "") for row in payload.get("reviews", []) if row.get("body")],
            "linked_issues": [
                f"#{row.get('number')}" for row in payload.get("closingIssuesReferences", []) if row.get("number")
            ],
            "ci_logs_text": ci_logs,
            "source": "gh",
        }
    payload = json.loads(
        subprocess.check_output(
            [
                "gh",
                "issue",
                "view",
                str(ref_number),
                "--json",
                "title,body,comments,closedByPullRequests",
            ],
            cwd=str(root),
            text=True,
        )
    )
    return {
        "title": payload.get("title", ""),
        "body": payload.get("body", ""),
        "changed_files": [],
        "comments": [row.get("body", "") for row in payload.get("comments", []) if row.get("body")],
        "review_comments": [],
        "linked_issues": [
            f"PR #{row.get('number')}" for row in payload.get("closedByPullRequests", []) if row.get("number")
        ],
        "ci_logs_text": "",
        "source": "gh",
    }


def cmd_context(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    repo = resolve_repo_name(conn, getattr(args, "repo", None))
    if args.context_command == "git":
        if not repo:
            raise SystemExit("No repo selected. Use --repo or run inside an indexed repo.")
        row = capture_git_context(conn, repo) if args.refresh else None
        if row is None:
            rows = list_git_contexts(conn, repo, limit=1)
            row = rows[0] if rows else capture_git_context(conn, repo)
        if row is None:
            console.print(f"[yellow]No git context available for {repo}.[/yellow]")
            return 1
        console.print(f"[bold]{repo}[/bold] branch={row['branch']} dirty={'yes' if row['dirty'] else 'no'}")
        console.print(f"head={row['head_commit'] or '-'} indexed_branch={row['indexed_branch'] or '-'} indexed_commit={row['indexed_commit'] or '-'}")
        console.print("\n[bold]Status[/bold]")
        console.print(row["status_short"] or "-")
        console.print("\n[bold]Diff[/bold]")
        console.print((row["diff_text"] or "-")[:1200])
        console.print("\n[bold]Staged diff[/bold]")
        console.print((row["staged_diff_text"] or "-")[:1200])
        return 0
    if args.context_command == "github":
        if args.manual:
            if not args.title:
                raise SystemExit("--title is required with --manual")
            payload = {
                "title": args.title,
                "body": args.body or "",
                "changed_files": args.changed_file or [],
                "comments": args.comment or [],
                "review_comments": args.review_comment or [],
                "linked_issues": args.linked_issue or [],
                "ci_logs_text": args.ci_log or "",
                "source": "manual",
            }
        else:
            repo_row = conn.execute("SELECT root FROM indexed_repos WHERE repo = ?", (repo,)).fetchone()
            if repo_row is None:
                raise SystemExit("GitHub ingestion requires an indexed repo or --manual fields.")
            try:
                payload = fetch_github_context_from_gh(Path(repo_row["root"]), args.ref_type, args.number)
            except subprocess.CalledProcessError as exc:
                raise SystemExit(f"gh failed to ingest {args.ref_type} #{args.number}: {exc}") from exc
        upsert_github_context(
            conn,
            repo,
            args.ref_type,
            args.number,
            payload["title"],
            body=str(payload.get("body", "")),
            changed_files=list(payload.get("changed_files", [])),
            comments=list(payload.get("comments", [])),
            review_comments=list(payload.get("review_comments", [])),
            ci_logs_text=str(payload.get("ci_logs_text", "")),
            linked_issues=list(payload.get("linked_issues", [])),
            source=str(payload.get("source", "manual")),
        )
        console.print(f"[green]Stored[/green] {args.ref_type} #{args.number} context")
        return 0
    if args.context_command == "test-failure":
        if args.failure_command == "list":
            rows = list_test_failures(conn, repo, args.limit)
            table = Table(title="RAG test failures")
            table.add_column("id", justify="right")
            table.add_column("command")
            table.add_column("fingerprint")
            table.add_column("repo")
            for row in rows:
                table.add_row(str(row["failure_id"]), row["command"][:60], row["fingerprint_hash"], row["repo"] or "-")
            console.print(table)
            return 0
        output_text = args.output or ""
        if args.output_file:
            output_text = Path(args.output_file).expanduser().read_text()
        if not output_text.strip():
            raise SystemExit("Provide --output or --output-file")
        failure_id = add_test_failure(
            conn,
            repo,
            args.command_text,
            output_text,
            runner=args.runner,
            exit_code=args.exit_code,
            source=args.source,
        )
        console.print(f"[green]Stored[/green] test failure {failure_id}")
        return 0

    if args.context_command == "system":
        repo_root_path = Path.cwd()
        candidate = repo_root_path
        while candidate != candidate.parent:
            if (candidate / ".git").exists():
                repo_root_path = candidate
                break
            candidate = candidate.parent

        sections: list[str] = []

        makefile = repo_root_path / "Makefile"
        if makefile.exists():
            targets = re.findall(r'^([a-zA-Z][a-zA-Z0-9_-]+)\s*:', makefile.read_text(), re.MULTILINE)
            if targets:
                sections.append("## Makefile targets\n" + "\n".join(f"- {t}" for t in targets[:30]))

        pkg = repo_root_path / "package.json"
        if pkg.exists():
            try:
                data = json.loads(pkg.read_text())
                scripts = data.get("scripts", {})
                if scripts:
                    sections.append("## npm scripts\n" + "\n".join(f"- {k}: {v}" for k, v in list(scripts.items())[:20]))
            except Exception:
                pass

        pyproject = repo_root_path / "pyproject.toml"
        if pyproject.exists():
            text = pyproject.read_text()
            scripts_match = re.search(r'\[tool\.poetry\.scripts\](.*?)(?=\[|\Z)', text, re.DOTALL)
            if not scripts_match:
                scripts_match = re.search(r'\[project\.scripts\](.*?)(?=\[|\Z)', text, re.DOTALL)
            if scripts_match:
                sections.append("## pyproject scripts\n" + scripts_match.group(0).strip()[:400])

        workflows_dir = repo_root_path / ".github" / "workflows"
        if workflows_dir.is_dir():
            job_lines = []
            for wf in sorted(workflows_dir.glob("*.yml"))[:5]:
                job_names = re.findall(r'^\s{2}([a-zA-Z][a-zA-Z0-9_-]+)\s*:', wf.read_text(), re.MULTILINE)
                if job_names:
                    job_lines.append(f"{wf.name}: {', '.join(job_names[:6])}")
            if job_lines:
                sections.append("## GitHub Actions jobs\n" + "\n".join(f"- {l}" for l in job_lines))

        setup_dir = repo_root_path / "setup"
        if setup_dir.is_dir():
            scripts = [p.name for p in sorted(setup_dir.glob("*.sh"))[:20]]
            if scripts:
                sections.append("## setup scripts\n" + "\n".join(f"- {s}" for s in scripts))

        if not sections:
            console.print("[yellow]No recognizable project tool files found.[/yellow]")
            return 0

        repo_label = repo or repo_root_path.name
        content = f"# System context for {repo_label}\n\n" + "\n\n".join(sections)
        console.print(content)

        if getattr(args, "store", False):
            memory_id = remember_memory(conn, repo_label, "project_facts", "system-context", content)
            console.print(f"[green]Stored[/green] system context as memory {memory_id}")

        return 0

    if args.context_command == "tmux":
        lines = getattr(args, "lines", 50)
        try:
            result = subprocess.run(
                ["tmux", "capture-pane", "-p", "-S", f"-{lines}"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            if result.returncode != 0:
                raise SystemExit("tmux not running or no active pane.")
            output = result.stdout.strip()
        except FileNotFoundError:
            raise SystemExit("tmux is not installed or not in PATH.")

        console.print(f"[bold]tmux pane capture[/bold] (last {lines} lines):")
        console.print(output)

        if getattr(args, "store", False):
            if any(word in output.lower() for word in ("error", "failed", "exception", "traceback")):
                failure_id = add_test_failure(
                    conn,
                    repo or Path.cwd().resolve().name,
                    "tmux-capture",
                    output,
                    runner="tmux",
                    exit_code=None,
                    source="local",
                )
                console.print(f"[green]Stored[/green] as test failure {failure_id}")
            else:
                console.print("[dim]No error patterns detected; not storing as failure.[/dim]")
        return 0

    if args.context_command == "devhealth":
        started_at = time.time()
        try:
            result = subprocess.run(
                ["dev-health"],
                capture_output=True,
                text=True,
                timeout=30,
            )
            output = result.stdout + result.stderr
        except FileNotFoundError:
            raise SystemExit("dev-health not found. Make sure ~/.local/bin is in PATH.")

        console.print(output)

        if getattr(args, "store", False):
            finished_at = time.time()
            record_execution_run(
                conn,
                run_id=f"devhealth-{uuid.uuid4().hex[:12]}",
                session_id=f"context-{uuid.uuid4().hex[:12]}",
                repo=repo or Path.cwd().resolve().name,
                target="dev-health",
                profile_id="context",
                intent="devhealth",
                mode="context",
                risk_level="low",
                query="dev-health",
                prompt_hash=hashlib.sha256(output.encode("utf-8", errors="ignore")).hexdigest(),
                agent_plan={"source": "context.devhealth", "command": "dev-health"},
                status="completed" if result.returncode == 0 else "failed",
                stdout=result.stdout or None,
                stderr=result.stderr or None,
                exit_code=result.returncode,
                duration_ms=int((finished_at - started_at) * 1000),
                files_modified=[],
                started_at=started_at,
                finished_at=finished_at,
            )
            console.print("[green]Stored[/green] dev-health output as execution run")

        return 0

    raise SystemExit(f"Unknown context command: {args.context_command}")


def cmd_search(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    repo = infer_repo_filter(conn, args.repo)
    result = retrieve(conn, client, config, args.query, repo, reranker_enabled(config, args.rerank))
    if args.explain:
        print_retrieval_explain(result.debug, result.rows)
        console.print()
    table = Table(title="RAG search results")
    table.add_column("#", justify="right")
    table.add_column("file")
    table.add_column("kind")
    table.add_column("symbol")
    table.add_column("preview")
    for index, row in enumerate(result.rows[:10], start=1):
        preview = row["content"].strip().replace("\n", " ")
        table.add_row(
            str(index),
            f"{row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}",
            row["kind"],
            row["symbol"] or "-",
            preview[:120],
        )
    console.print(table)
    return 0


def cmd_inspect(args: argparse.Namespace) -> int:
    config = load_config()
    mode, route_reason = resolved_mode(args, config)
    _conn, _effective_config, _repo, result = retrieve_for_cli(
        args.query,
        repo=args.repo,
        mode=mode,
        rerank=args.rerank,
    )
    console.print(render_query_inspection(result, mode, route_reason))
    return 0


def cmd_missing(args: argparse.Namespace) -> int:
    config = load_config()
    mode, _route_reason = resolved_mode(args, config)
    _conn, _effective_config, _repo, result = retrieve_for_cli(
        args.query,
        repo=args.repo,
        mode=mode,
        rerank=args.rerank,
    )
    desired = [humanize_missing_label(item) for item in result.debug.get("missing_context_desired", [])]
    added = [humanize_missing_label(item) for item in result.debug.get("missing_context_added", [])]
    remaining = [humanize_missing_label(item) for item in result.debug.get("missing_context_remaining", [])]
    console.print("[bold]Need:[/bold]")
    for item in desired or ["nothing special detected"]:
        console.print(f"- {item}")
    if added:
        console.print("\n[bold]Added automatically:[/bold]")
        for item in added:
            console.print(f"- {item}")
    if remaining:
        console.print("\n[bold]Still missing:[/bold]")
        for item in remaining:
            console.print(f"- {item}")
    suggestions = [row["path"] for row in result.summaries[:6]]
    if suggestions:
        console.print("\n[bold]Candidate files:[/bold]")
        for item in compact_file_refs(suggestions):
            console.print(f"- {item}")
    return 0


def workflow_keys_for_query(query: str | None) -> list[str]:
    if not query:
        return list(RAG_WORKFLOWS)
    lowered = query.lower()
    selected: list[str] = []
    for key in RAG_WORKFLOWS:
        if key in lowered:
            selected.append(key)
    for alias, key in SUGGEST_ALIASES.items():
        if alias in lowered and key not in selected:
            selected.append(key)
    if selected:
        return selected
    close = difflib.get_close_matches(lowered, list(RAG_WORKFLOWS), n=2, cutoff=0.45)
    return close or ["ask", "debug", "memory"]


def cmd_suggest(args: argparse.Namespace) -> int:
    selected = workflow_keys_for_query(args.query)
    table = Table(title="RAG suggestions")
    table.add_column("area")
    table.add_column("command")
    table.add_column("why")
    for area in selected:
        for command_text, reason in RAG_WORKFLOWS[area]:
            table.add_row(area, command_text, reason)
    console.print(table)
    console.print("\n[dim]Tip: install shell completion with ./setup/install-local-rag-stack.sh, then restart zsh.[/dim]")
    return 0


def find_path_rows(conn: sqlite3.Connection, repo: str | None, path: str) -> list[sqlite3.Row]:
    normalized = path.strip()
    rows = conn.execute(
        """
        SELECT * FROM chunks
        WHERE (? IS NULL OR repo = ?)
          AND (path = ? OR path LIKE ? OR path LIKE ?)
        ORDER BY modified_at DESC, chunk_index ASC
        LIMIT 6
        """,
        (repo, repo, normalized, f"%/{normalized}", f"%{normalized}%"),
    ).fetchall()
    return rows


def cmd_why(args: argparse.Namespace) -> int:
    config = load_config()
    mode, route_reason = resolved_mode(args, config)
    conn, effective_config, repo, result = retrieve_for_cli(
        args.query,
        repo=args.repo,
        mode=mode,
        rerank=args.rerank,
    )
    path_rows = find_path_rows(conn, repo, args.path)
    if not path_rows:
        console.print(f"[yellow]No indexed file matched {args.path}.[/yellow]")
        return 1
    target_paths = {row["path"] for row in path_rows}
    selected = [row for row in result.rows if row["path"] in target_paths]
    analysis = analysis_for_plan(result.plan, effective_config)
    facts = [row for row in result.facts if row["path"] in target_paths]
    summaries = [row for row in result.summaries if row["path"] in target_paths]
    console.print(f"[bold]Why[/bold] {next(iter(target_paths))}")
    console.print(f"mode={mode} intent={result.plan.intent} route={route_reason}")
    for row in path_rows[:2]:
        path_score = row_path_match_count(row["path"].lower(), analysis)
        symbol_score = row_symbol_match_count((row["symbol"] or "").lower(), analysis)
        type_score = row_file_type_match_count(row["language"], row["kind"], row["path"].lower(), analysis)
        console.print(
            f"- chunk {row['start_line']}-{row['end_line']} selected={'yes' if row in selected else 'no'} "
            f"path_match={path_score} symbol_match={symbol_score} type_match={type_score}"
        )
    console.print(f"- facts on file: {len(facts)}")
    console.print(f"- summaries on file: {len(summaries)}")
    if selected:
        console.print("- final selection: yes")
    else:
        console.print("- final selection: no")
        nearby = [row["path"] for row in result.rows[:5]]
        if nearby:
            console.print("- selected instead:")
            for item in compact_file_refs(nearby, limit=5):
                console.print(f"  - {item}")
    return 0


def matching_symbol_rows(conn: sqlite3.Connection, repo: str | None, query: str, limit: int = 6) -> list[sqlite3.Row]:
    tokens = [token for token in re.split(r"[^A-Za-z0-9_.$#/:-]+", query) if token]
    params: list[object] = []
    clauses: list[str] = []
    for token in tokens[:6]:
        clauses.append("(name LIKE ? OR qualified_name LIKE ? OR path LIKE ?)")
        params.extend([f"%{token}%", f"%{token}%", f"%{token}%"])
    sql = "SELECT * FROM symbols"
    if clauses:
        sql += " WHERE (" + " OR ".join(clauses) + ")"
        if repo:
            sql += " AND repo = ?"
            params.append(repo)
    elif repo:
        sql += " WHERE repo = ?"
        params.append(repo)
    sql += " ORDER BY updated_at DESC, start_line ASC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()


def matching_route_facts(conn: sqlite3.Connection, repo: str | None, route_text: str, limit: int = 6) -> list[sqlite3.Row]:
    sql = """
        SELECT * FROM facts
        WHERE kind = 'route-handler'
          AND (key LIKE ? OR value LIKE ? OR path LIKE ?)
    """
    params: list[object] = [f"%{route_text}%", f"%{route_text}%", f"%{route_text}%"]
    if repo:
        sql += " AND repo = ?"
        params.append(repo)
    sql += " ORDER BY updated_at DESC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()


def render_dependency_graph(conn: sqlite3.Connection, repo: str | None, seed_paths: list[str], header: str) -> int:
    if not seed_paths:
        console.print("[yellow]No graph matches found.[/yellow]")
        return 1
    console.print(f"[bold]{header}[/bold]")
    shown: set[str] = set()
    for path in seed_paths[:6]:
        if path in shown:
            continue
        shown.add(path)
        console.print(f"* {path}")
        outbound = conn.execute(
            """
            SELECT dependency_kind, dependency, target_path
            FROM file_dependencies
            WHERE (? IS NULL OR repo = ?) AND source_path = ?
            ORDER BY updated_at DESC, line ASC LIMIT 8
            """,
            (repo, repo, path),
        ).fetchall()
        inbound = conn.execute(
            """
            SELECT source_path, dependency_kind
            FROM file_dependencies
            WHERE (? IS NULL OR repo = ?) AND target_path = ?
            ORDER BY updated_at DESC, line ASC LIMIT 8
            """,
            (repo, repo, path),
        ).fetchall()
        for row in outbound:
            console.print(f"  -> {row['dependency_kind']}: {row['target_path'] or row['dependency']}")
        for row in inbound:
            console.print(f"  <- {row['dependency_kind']}: {row['source_path']}")
    return 0


def cmd_graph(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.route:
        route_text = " ".join(args.route)
        rows = matching_route_facts(conn, repo, route_text)
        paths = [row["path"] for row in rows]
        return render_dependency_graph(conn, repo, paths, f"Route graph: {route_text}")
    if args.db:
        rows = conn.execute(
            """
            SELECT path FROM facts
            WHERE kind IN ('sql-object', 'entity', 'repository')
              AND (key LIKE ? OR value LIKE ? OR path LIKE ?)
              AND (? IS NULL OR repo = ?)
            ORDER BY updated_at DESC LIMIT 8
            """,
            (f"%{args.db}%", f"%{args.db}%", f"%{args.db}%", repo, repo),
        ).fetchall()
        return render_dependency_graph(conn, repo, [row["path"] for row in rows], f"DB graph: {args.db}")
    rows = matching_symbol_rows(conn, repo, args.query or "")
    return render_dependency_graph(conn, repo, [row["path"] for row in rows], f"Symbol graph: {args.query}")


def cmd_ask(args: argparse.Namespace) -> int:
    return run_query_mode(args)


def cmd_quick(args: argparse.Namespace) -> int:
    args.mode = "quick"
    return run_query_mode(args)


def cmd_deep(args: argparse.Namespace) -> int:
    args.mode = "deep"
    return run_query_mode(args)


def cmd_agent(args: argparse.Namespace) -> int:
    args.mode = "agent"
    return run_query_mode(args)


def cmd_handoff(args: argparse.Namespace) -> int:
    args.mode = "agent"
    args.output_format = "handoff"
    args.target_agent = args.target
    return run_query_mode(args)


def cmd_summarize_files(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    refreshed = refresh_file_summaries(conn, repo=repo, changed_only=args.changed_only)
    scope = repo or "all indexed repos"
    console.print(f"[green]Refreshed[/green] {refreshed} file summaries for {scope}")
    return 0


def cmd_summarize(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if not repo:
        raise SystemExit("No repo selected. Use --repo or run inside an indexed repo.")
    console.print(f"[cyan]Summarizing[/cyan] {repo} ...")
    summary = generate_repo_memory(conn, config, repo)
    store_repo_memory(conn, repo, summary)
    console.print(f"[green]Stored[/green] repo memory for {repo}")
    return 0


def cmd_memory(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    repo = resolve_repo_name(conn, getattr(args, "repo", None))
    if args.memory_command == "status":
        rows = repo_memory_status_rows(conn, repo)
        if not rows:
            console.print("[yellow]No indexed repos yet.[/yellow]")
            return 0
        table = Table(title="Repo memory status")
        table.add_column("repo")
        table.add_column("status")
        table.add_column("memory")
        table.add_column("freshness")
        table.add_column("detail")
        for row in rows:
            memory_updated = (
                datetime.fromtimestamp(row["memory_updated_at"]).strftime("%Y-%m-%d %H:%M")
                if row["memory_updated_at"]
                else "-"
            )
            detail = "; ".join(row["reasons"]) if row["reasons"] else f"{row['chunk_count']} chunks"
            table.add_row(row["repo"], str(row["status"]), memory_updated, str(row["freshness_score"]), detail)
        console.print(table)
        return 0
    if args.memory_command == "show":
        if not repo:
            raise SystemExit("No repo selected. Use --repo or run inside an indexed repo.")
        row = conn.execute("SELECT summary FROM repo_memory WHERE repo = ?", (repo,)).fetchone()
        if row is None:
            console.print(f"[yellow]No repo memory stored for {repo}.[/yellow]")
            return 0
        console.print(row["summary"])
        return 0
    if args.memory_command == "refresh":
        if not repo:
            raise SystemExit("No repo selected. Use --repo or run inside an indexed repo.")
        summary = generate_repo_memory(conn, config, repo)
        store_repo_memory(conn, repo, summary)
        console.print(f"[green]Refreshed[/green] repo memory for {repo}")
        return 0
    if args.memory_command == "clear":
        if args.all:
            conn.execute("DELETE FROM repo_memory")
            conn.commit()
            console.print("[green]Cleared[/green] all repo memory")
            return 0
        if not repo:
            raise SystemExit("No repo selected. Use --repo, run inside an indexed repo, or use --all.")
        conn.execute("DELETE FROM repo_memory WHERE repo = ?", (repo,))
        conn.commit()
        console.print(f"[green]Cleared[/green] repo memory for {repo}")
        return 0
    if args.memory_command == "remember":
        memory_id = remember_memory(
            conn,
            repo,
            args.kind,
            args.subject,
            " ".join(args.value),
            global_scope=args.global_scope,
        )
        console.print(f"[green]Stored[/green] memory {memory_id}")
        return 0
    if args.memory_command == "notes":
        rows = list_memory_entries(
            conn,
            repo,
            kind=args.kind,
            limit=args.limit,
            scope=args.scope,
            status=args.status,
        )
        table = Table(title="RAG memory notes")
        table.add_column("id", justify="right")
        table.add_column("kind")
        table.add_column("subject")
        table.add_column("value")
        table.add_column("scope")
        table.add_column("status")
        for row in rows:
            table.add_row(
                str(row["memory_id"]),
                row["kind"],
                row["subject"],
                str(row["value"])[:80],
                row["repo"] or "global",
                row["status"],
            )
        console.print(table)
        return 0
    if args.memory_command == "conflicts":
        rows = detect_memory_conflicts(conn, repo, limit=args.limit)
        if not rows:
            console.print("[green]No memory conflicts detected.[/green]")
            return 0
        table = Table(title="RAG memory conflicts")
        table.add_column("kind")
        table.add_column("subject")
        table.add_column("scope")
        table.add_column("values")
        for row in rows:
            table.add_row(
                str(row["kind"]),
                str(row["subject"]),
                str(row["repo"] or "global"),
                " | ".join(str(value) for value in row["values"]),
            )
        console.print(table)
        return 0
    if args.memory_command == "compact":
        if args.session_id:
            row = compact_session(conn, args.session_id)
            if row is None:
                console.print(f"[yellow]Session {args.session_id} not found.[/yellow]")
                return 1
            console.print(row["summary"])
            return 0
        rows = conn.execute(
            "SELECT * FROM session_compactions"
            + (" WHERE repo = ?" if repo else "")
            + " ORDER BY updated_at DESC LIMIT ?",
            ([repo] if repo else []) + [args.limit],
        ).fetchall()
        table = Table(title="RAG session compactions")
        table.add_column("session")
        table.add_column("mode")
        table.add_column("summary")
        table.add_column("signals")
        for row in rows:
            details = session_compaction_details(row)
            signals = []
            for key in ("todos", "commands", "errors"):
                values = details.get(key) or []
                if values:
                    signals.append(f"{key}:{len(values)}")
            table.add_row(row["session_id"], row["mode"], row["summary"][:100], ", ".join(signals) or "-")
        console.print(table)
        return 0
    if args.memory_command == "pack":
        content, metadata = build_context_pack(conn, repo, args.name, agent_target=args.target_agent)
        store_context_pack(conn, repo, args.name, content, metadata, agent_target=args.target_agent)
        console.print(content)
        if args.write_file:
            if not repo:
                raise SystemExit("Use --repo or run inside an indexed repo to write a .context file.")
            root_row = conn.execute("SELECT root FROM indexed_repos WHERE repo = ?", (repo,)).fetchone()
            if root_row is None:
                raise SystemExit(f"Repo not indexed: {repo}")
            path = write_context_pack_file(Path(root_row["root"]), args.name, content)
            console.print(f"\n[green]Saved[/green] {path}")
        return 0
    if args.memory_command == "taxonomy":
        rows = list_tool_taxonomy(conn, domain=args.domain, query=args.query, limit=args.limit)
        if args.format == "yaml":
            grouped: dict[str, list[str]] = {}
            for row in rows:
                grouped.setdefault(str(row["domain"]), []).append(str(row["tool"]))
            for domain, tools in grouped.items():
                console.print(f"{domain}:\n  tools: [{', '.join(tools)}]")
            return 0
        table = Table(title="RAG tool taxonomy")
        table.add_column("domain")
        table.add_column("tool")
        table.add_column("aliases")
        table.add_column("description")
        for row in rows:
            table.add_row(row["domain"], row["tool"], row["aliases"], row["description"] or "-")
        console.print(table)
        return 0

    if args.memory_command == "extract":
        rows = list_session_compactions(conn, repo, limit=getattr(args, "limit", 20))
        if not rows:
            console.print("[yellow]No session compactions found.[/yellow]")
            return 0

        total_added = 0
        for row in rows:
            candidates = extract_memory_from_compaction(row)
            for c in candidates:
                if len(c["value"]) > 8:
                    try:
                        remember_memory(
                            conn,
                            repo if c["scope"] == "repo" else None,
                            c["kind"],
                            c["subject"],
                            c["value"],
                            global_scope=(c["scope"] == "global"),
                            source_session_id=row["session_id"],
                        )
                        total_added += 1
                    except Exception:
                        pass

        if getattr(args, "llm", False):
            system_prompt = (
                "You are extracting developer memory from a session log. "
                'Return ONLY a JSON array of objects: [{"kind": "convention|architecture|tool|pattern|warning", '
                '"subject": "<short label>", "value": "<fact>", "scope": "repo|global"}]. '
                "Extract at most 5 items. Omit trivial or duplicate items. Return [] if nothing useful."
            )
            for row in rows[:5]:
                details = session_compaction_details(row)
                context = f"Query: {row['summary']}\nDecisions: {details.get('decisions', [])}\nFacts: {details.get('useful_facts', [])}"
                try:
                    raw = complete_llm(config, system_prompt, context, max_tokens=400)
                    match = re.search(r'\[.*\]', raw, re.DOTALL)
                    if match:
                        items = json.loads(match.group())
                        for item in items[:5]:
                            if isinstance(item, dict) and item.get("value"):
                                remember_memory(
                                    conn,
                                    repo if item.get("scope") == "repo" else None,
                                    item.get("kind", "convention"),
                                    item.get("subject", "fact"),
                                    str(item["value"]),
                                    global_scope=(item.get("scope") == "global"),
                                    source_session_id=row["session_id"],
                                )
                                total_added += 1
                except Exception:
                    pass

        console.print(f"[green]Extracted[/green] {total_added} memory candidates from {len(rows)} sessions")
        return 0

    if args.memory_command == "consolidate":
        cutoff = time.time() - (90 * 86400)
        memory_columns = {row["name"] for row in conn.execute("PRAGMA table_info(developer_memory)").fetchall()}
        if "confidence_score" in memory_columns:
            result = conn.execute(
                """UPDATE developer_memory SET status = 'stale'
                   WHERE status = 'active' AND updated_at < ? AND confidence_score < 0.4""",
                (cutoff,),
            )
        else:
            now = time.time()
            result = conn.execute(
                """UPDATE developer_memory SET status = 'stale', updated_at = ?
                   WHERE status = 'active' AND updated_at < ?
                     AND source_session_id IS NOT NULL
                     AND COALESCE(last_used_at, updated_at) < ?""",
                (now, cutoff, cutoff),
            )
        expired = result.rowcount

        rows_dup = conn.execute(
            """SELECT kind, normalized_subject, repo, COUNT(*) as cnt
               FROM developer_memory WHERE status = 'active'
               GROUP BY kind, normalized_subject, repo HAVING cnt > 1"""
        ).fetchall()
        merged = 0
        for dup in rows_dup:
            entries = conn.execute(
                """SELECT memory_id FROM developer_memory
                   WHERE kind = ? AND normalized_subject = ?
                     AND ((repo IS NULL AND ? IS NULL) OR repo = ?)
                     AND status = 'active'
                   ORDER BY updated_at DESC""",
                (dup["kind"], dup["normalized_subject"], dup["repo"], dup["repo"]),
            ).fetchall()
            for entry in entries[1:]:
                conn.execute(
                    "UPDATE developer_memory SET status = 'stale' WHERE memory_id = ?",
                    (entry["memory_id"],),
                )
                merged += 1
        conn.commit()
        console.print(f"[green]Consolidated[/green] memory: expired {expired} old entries, merged {merged} duplicates")
        return 0

    if args.memory_command == "prune":
        limit_days = getattr(args, "days", 180)
        cutoff = time.time() - (limit_days * 86400)
        result = conn.execute(
            "DELETE FROM developer_memory WHERE status = 'stale' AND updated_at < ?",
            (cutoff,),
        )
        conn.commit()
        console.print(f"[green]Pruned[/green] {result.rowcount} stale memory entries older than {limit_days} days")
        return 0

    if args.memory_command == "promote":
        threshold = getattr(args, "threshold", 3)
        rows_candidates = conn.execute(
            """SELECT kind, normalized_subject, value, repo, COUNT(DISTINCT source_session_id) as seen_count
               FROM developer_memory
               WHERE status = 'active' AND source_session_id IS NOT NULL
               GROUP BY kind, normalized_subject, repo
               HAVING seen_count >= ?""",
            (threshold,),
        ).fetchall()
        promoted = 0
        memory_columns = {row["name"] for row in conn.execute("PRAGMA table_info(developer_memory)").fetchall()}
        for row in rows_candidates:
            if "confidence_score" in memory_columns:
                conn.execute(
                    """UPDATE developer_memory SET confidence_score = 0.9, status = 'active'
                       WHERE kind = ? AND normalized_subject = ?
                         AND ((repo IS NULL AND ? IS NULL) OR repo = ?)
                         AND status = 'active'""",
                    (row["kind"], row["normalized_subject"], row["repo"], row["repo"]),
                )
            else:
                now = time.time()
                conn.execute(
                    """UPDATE developer_memory SET status = 'active', updated_at = ?, last_used_at = ?
                       WHERE kind = ? AND normalized_subject = ?
                         AND ((repo IS NULL AND ? IS NULL) OR repo = ?)
                         AND status = 'active'""",
                    (now, now, row["kind"], row["normalized_subject"], row["repo"], row["repo"]),
                )
            promoted += 1
        conn.commit()
        console.print(f"[green]Promoted[/green] {promoted} memory groups (seen in ≥{threshold} sessions)")
        return 0

    raise SystemExit(f"Unknown memory command: {args.memory_command}")


def cmd_todo(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.todo_command == "list":
        rows = list_todos(conn, repo, args.status, args.limit)
        table = Table(title="RAG todos")
        table.add_column("id", justify="right")
        table.add_column("status")
        table.add_column("title")
        table.add_column("repo")
        for row in rows:
            table.add_row(str(row["todo_id"]), row["status"], row["title"], row["repo"] or "-")
        console.print(table)
        return 0
    if args.todo_command == "add":
        todo_id = add_todo(conn, repo, args.title, detail=args.detail, status=args.status)
        console.print(f"[green]Added[/green] todo {todo_id}")
        return 0
    if args.todo_command == "done":
        if not update_todo_status(conn, args.todo_id, "done"):
            console.print(f"[yellow]Todo {args.todo_id} not found.[/yellow]")
            return 1
        console.print(f"[green]Completed[/green] todo {args.todo_id}")
        return 0
    if args.todo_command == "start":
        if not update_todo_status(conn, args.todo_id, "in_progress"):
            console.print(f"[yellow]Todo {args.todo_id} not found.[/yellow]")
            return 1
        console.print(f"[green]Marked[/green] todo {args.todo_id} in progress")
        return 0
    raise SystemExit(f"Unknown todo command: {args.todo_command}")


def cmd_decision(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.decision_command == "list":
        rows = list_decisions(conn, repo, args.limit)
        table = Table(title="RAG decisions")
        table.add_column("id", justify="right")
        table.add_column("title")
        table.add_column("detail")
        table.add_column("repo")
        for row in rows:
            table.add_row(str(row["decision_id"]), row["title"], row["detail"][:100], row["repo"] or "-")
        console.print(table)
        return 0
    decision_id = add_decision(conn, repo, args.title, args.detail, rationale=args.rationale)
    console.print(f"[green]Added[/green] decision {decision_id}")
    return 0


def cmd_command_memory(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.command_memory_command == "list":
        rows = list_commands(conn, repo, args.limit)
        table = Table(title="RAG commands")
        table.add_column("id", justify="right")
        table.add_column("command")
        table.add_column("purpose")
        table.add_column("repo")
        for row in rows:
            table.add_row(str(row["command_id"]), row["command"], row["purpose"] or "-", row["repo"] or "-")
        console.print(table)
        return 0
    command_id = add_command(conn, repo, args.command_text, purpose=args.purpose, notes=args.notes)
    console.print(f"[green]Added[/green] command {command_id}")
    return 0


def cmd_error_memory(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.error_command == "list":
        rows = list_errors(conn, repo, args.limit)
        table = Table(title="RAG errors")
        table.add_column("id", justify="right")
        table.add_column("fingerprint")
        table.add_column("error")
        table.add_column("fix")
        table.add_column("repo")
        for row in rows:
            table.add_row(
                str(row["error_id"]),
                (row["fingerprint_hash"] or "-")[:16],
                row["error_text"][:80],
                (row["fix_text"] or "-")[:80],
                row["repo"] or "-",
            )
        console.print(table)
        return 0
    error_id = add_error(
        conn,
        repo,
        args.error_text,
        fix_text=args.fix,
        notes=args.notes,
        command=args.command_text,
        exit_code=args.exit_code,
    )
    console.print(f"[green]Added[/green] error {error_id}")
    return 0


def cmd_session(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.session_command == "list":
        rows = list_sessions(conn, repo, args.limit)
        table = Table(title="RAG sessions")
        table.add_column("id")
        table.add_column("mode")
        table.add_column("kind")
        table.add_column("query")
        for row in rows:
            table.add_row(row["session_id"], row["mode"], row["output_kind"], row["query"][:90])
        console.print(table)
        return 0
    row = get_session(conn, args.session_id)
    if row is None:
        console.print(f"[yellow]Session {args.session_id} not found.[/yellow]")
        return 1
    console.print(f"[bold]Session[/bold] {row['session_id']} [{row['mode']}]")
    console.print(f"Repo: {row['repo'] or 'unscoped'}")
    console.print(f"Reason: {row['route_reason']}")
    console.print("\n[bold]Query:[/bold]")
    console.print(row["query"])
    console.print("\n[bold]Output:[/bold]")
    console.print(row["output_text"])
    files = session_files(row)
    if files:
        console.print("\n[bold]Files:[/bold]")
        for item in files:
            console.print(f"- {item}")
    return 0


def cmd_facts(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.subject == "list":
        sql = "SELECT repo, path, kind, key, value, line FROM facts"
        params: list[str] = []
        clauses: list[str] = []
        if repo:
            clauses.append("repo = ?")
            params.append(repo)
        if args.kind:
            clauses.append("kind = ?")
            params.append(args.kind)
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY repo, path, line LIMIT 40"
        rows = conn.execute(sql, params).fetchall()
    else:
        if not args.query:
            raise SystemExit("Use `rag facts list` or `rag facts <kind> <query>`")
        query = " ".join(args.query)
        sql = "SELECT repo, path, kind, key, value, line FROM facts WHERE kind = ? AND (key LIKE ? OR value LIKE ?)"
        params = [args.subject, f"%{query}%", f"%{query}%"]
        if repo:
            sql += " AND repo = ?"
            params.append(repo)
        sql += " ORDER BY confidence DESC, updated_at DESC LIMIT 30"
        rows = conn.execute(sql, params).fetchall()
    table = Table(title="RAG facts")
    table.add_column("kind")
    table.add_column("key")
    table.add_column("value")
    table.add_column("file")
    for row in rows:
        table.add_row(row["kind"], row["key"], str(row["value"])[:80], f"{row['repo']}/{row['path']}:{row['line']}")
    console.print(table)
    return 0


def trace_fact_rows(
    conn: sqlite3.Connection,
    config: dict,
    kind: str,
    query: str,
    repo: str | None,
    limit: int,
) -> list[sqlite3.Row]:
    if kind == "keybind":
        plan = RetrievalPlan(query=query, repo=repo, rewrites=[], intent="keybind", mode="quick")
        return fact_hits(conn, plan, config)[:limit]
    if kind == "route":
        sql = """
            SELECT fact_id, repo, path, kind, key, value, line, confidence, updated_at
            FROM facts
            WHERE kind IN ('route-handler', 'route-controller')
              AND (key LIKE ? OR value LIKE ? OR path LIKE ?)
        """
        params: list[object] = [f"%{query}%", f"%{query}%", f"%{query}%"]
        if repo:
            sql += " AND repo = ?"
            params.append(repo)
        sql += " ORDER BY confidence DESC, updated_at DESC LIMIT ?"
        params.append(limit)
        return conn.execute(sql, params).fetchall()
    sql = """
        SELECT fact_id, repo, path, kind, key, value, line, confidence, updated_at
        FROM facts
        WHERE kind = ? AND (key LIKE ? OR value LIKE ? OR path LIKE ?)
    """
    params: list[object] = [kind, f"%{query}%", f"%{query}%", f"%{query}%"]
    if repo:
        sql += " AND repo = ?"
        params.append(repo)
    sql += " ORDER BY confidence DESC, updated_at DESC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()


def trace_nearby_chunks(
    conn: sqlite3.Connection,
    repo: str,
    path: str,
    line: int,
    limit: int = 2,
) -> list[sqlite3.Row]:
    return conn.execute(
        """
        SELECT repo, path, start_line, end_line, kind, language, symbol, content,
               CASE
                   WHEN start_line <= ? AND end_line >= ? THEN 0
                   ELSE MIN(ABS(start_line - ?), ABS(end_line - ?))
               END AS distance
        FROM chunks
        WHERE repo = ? AND path = ?
        ORDER BY distance ASC, start_line ASC
        LIMIT ?
        """,
        (line, line, line, line, repo, path, limit),
    ).fetchall()


def cmd_trace(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    query = " ".join(args.query)
    if args.kind == "symbol":
        rows = matching_symbol_rows(conn, repo, query, limit=args.limit)
        if not rows:
            console.print("[yellow]No matching symbols found.[/yellow]")
            return 1
        table = Table(title="RAG trace: symbol")
        table.add_column("#", justify="right")
        table.add_column("symbol")
        table.add_column("kind")
        table.add_column("file")
        for index, row in enumerate(rows, start=1):
            table.add_row(
                str(index),
                row["qualified_name"],
                row["kind"],
                f"{row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}",
            )
        console.print(table)
        for row in rows:
            console.print()
            console.print(f"[bold]{row['qualified_name']}[/bold] ({row['kind']})")
            console.print(f"file={row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}")
            chunks = trace_nearby_chunks(conn, row["repo"], row["path"], int(row["start_line"]))
            for chunk in chunks:
                console.print(
                    f"- {chunk['start_line']}-{chunk['end_line']} {chunk['kind']} {chunk['symbol'] or '-'}"
                )
                console.print(chunk["content"].strip())
        return 0
    rows = trace_fact_rows(conn, config, args.kind, query, repo, args.limit)
    if not rows:
        console.print("[yellow]No matching facts found.[/yellow]")
        return 1
    table = Table(title=f"RAG trace: {args.kind}")
    table.add_column("#", justify="right")
    table.add_column("key")
    table.add_column("value")
    table.add_column("file")
    for index, row in enumerate(rows, start=1):
        table.add_row(
            str(index),
            row["key"],
            str(row["value"])[:90],
            f"{row['repo']}/{row['path']}:{row['line']}",
        )
    console.print(table)
    for index, row in enumerate(rows, start=1):
        console.print()
        console.print(f"[bold]{index}. {row['repo']}/{row['path']}:{row['line']}[/bold]")
        console.print(f"kind={row['kind']} key={row['key']}")
        console.print(f"value={row['value']}")
        chunks = trace_nearby_chunks(conn, row["repo"], row["path"], int(row["line"]))
        if not chunks:
            continue
        console.print("[dim]Nearby evidence[/dim]")
        for chunk in chunks:
            console.print(
                f"- {chunk['start_line']}-{chunk['end_line']} {chunk['kind']} {chunk['symbol'] or '-'}"
            )
            console.print(chunk["content"].strip())
    return 0


def cmd_doctor(args: argparse.Namespace) -> int:
    table = Table(title="RAG doctor")
    table.add_column("check")
    table.add_column("status")
    table.add_column("detail")
    failed = False
    raw_config: dict = {}
    config: dict | None = None
    conn: sqlite3.Connection | None = None
    client = None
    github_context_count = 0

    if CONFIG_PATH.exists():
        try:
            loaded_raw = json.loads(CONFIG_PATH.read_text())
            if isinstance(loaded_raw, dict):
                raw_config = loaded_raw
                table.add_row("config file", "ok", str(CONFIG_PATH))
            else:
                failed = True
                table.add_row("config file", "fail", f"{CONFIG_PATH} must contain a JSON object")
        except (json.JSONDecodeError, OSError) as exc:
            failed = True
            table.add_row("config file", "fail", str(exc))
    else:
        failed = True
        table.add_row("config file", "fail", f"missing: {CONFIG_PATH}")

    try:
        config = load_config()
        table.add_row("config merge", "ok", "loaded defaults + overrides")
    except (json.JSONDecodeError, OSError, TypeError, ValueError) as exc:
        failed = True
        table.add_row("config merge", "fail", str(exc))
        console.print(table)
        return 1

    required_paths = required_config_key_paths()
    missing_paths = missing_required_config_keys(config, required_paths)
    if missing_paths:
        failed = True
        table.add_row("config keys", "fail", ", ".join(missing_paths[:10]))
    else:
        table.add_row("config keys", "ok", f"{len(required_paths)} required keys present")

    unknown_paths = unknown_config_keys(raw_config) if raw_config else []
    if unknown_paths:
        table.add_row("unknown config keys", "warn", ", ".join(unknown_paths[:10]))
    else:
        table.add_row("unknown config keys", "ok", "none")

    try:
        conn = connect_db()
        table.add_row("sqlite open", "ok", str(DB_PATH))
    except sqlite3.Error as exc:
        failed = True
        table.add_row("sqlite open", "fail", str(exc))

    repo_count = 0
    chunk_count = 0
    fact_count = 0
    summary_count = 0
    if conn is not None:
        required_tables = {
            "indexed_repos",
            "chunks",
            "chunks_fts",
            "facts",
            "file_summaries",
            "symbols",
            "symbols_fts",
            "semantic_lines",
            "semantic_lines_fts",
            "file_dependencies",
            "repo_memory",
            "task_todos",
            "task_decisions",
            "command_memory",
            "error_memory",
            "git_context",
            "github_context",
            "test_failure_memory",
            "task_sessions",
            "session_compactions",
            "context_packs",
            "eval_cases",
            "profiles",
            "profile_usage",
            "execution_runs",
            "memory_candidates",
            "_schema_migrations",
        }
        table_names = {
            row["name"]
            for row in conn.execute(
                "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"
            ).fetchall()
        }
        missing_tables = sorted(required_tables - table_names)
        if missing_tables:
            failed = True
            table.add_row("sqlite schema", "fail", ", ".join(missing_tables[:10]))
        else:
            table.add_row("sqlite schema", "ok", f"{len(required_tables)} required tables present")

        repo_count = int(conn.execute("SELECT COUNT(*) AS count FROM indexed_repos").fetchone()["count"])
        chunk_count = int(conn.execute("SELECT COUNT(*) AS count FROM chunks").fetchone()["count"])
        fact_count = int(conn.execute("SELECT COUNT(*) AS count FROM facts").fetchone()["count"])
        summary_count = int(conn.execute("SELECT COUNT(*) AS count FROM file_summaries").fetchone()["count"])
        memory_count = conn.execute("SELECT COUNT(*) AS count FROM repo_memory").fetchone()["count"]
        todo_count = conn.execute("SELECT COUNT(*) AS count FROM task_todos").fetchone()["count"]
        decision_count = conn.execute("SELECT COUNT(*) AS count FROM task_decisions").fetchone()["count"]
        session_count = conn.execute("SELECT COUNT(*) AS count FROM task_sessions").fetchone()["count"]
        memory_note_count = conn.execute("SELECT COUNT(*) AS count FROM developer_memory").fetchone()["count"]
        context_pack_count = conn.execute("SELECT COUNT(*) AS count FROM context_packs").fetchone()["count"]
        compaction_count = conn.execute("SELECT COUNT(*) AS count FROM session_compactions").fetchone()["count"]
        git_context_count = conn.execute("SELECT COUNT(*) AS count FROM git_context").fetchone()["count"]
        github_context_count = int(conn.execute("SELECT COUNT(*) AS count FROM github_context").fetchone()["count"])
        test_failure_count = conn.execute("SELECT COUNT(*) AS count FROM test_failure_memory").fetchone()["count"]
        eval_case_count = conn.execute("SELECT COUNT(*) AS count FROM eval_cases").fetchone()["count"]
        execution_count = conn.execute("SELECT COUNT(*) AS count FROM execution_runs").fetchone()["count"]
        candidate_count = conn.execute("SELECT COUNT(*) AS count FROM memory_candidates WHERE status = 'pending'").fetchone()["count"]
        migration_count = conn.execute("SELECT COUNT(*) AS count FROM _schema_migrations").fetchone()["count"]

        table.add_row("sqlite data", "ok", f"{repo_count} repos, {chunk_count} chunks")
        table.add_row(
            "memory/state",
            "ok",
            (
                f"{fact_count} facts, {summary_count} file summaries, {memory_count} repo memories, "
                f"{memory_note_count} memory notes, {context_pack_count} context packs, "
                f"{git_context_count} git snapshots, {github_context_count} GitHub refs, {test_failure_count} test failures, "
                f"{todo_count} todos, {decision_count} decisions, {session_count} sessions, "
                f"{compaction_count} compactions, {eval_case_count} eval cases, "
                f"{execution_count} execution runs, {candidate_count} pending candidates, {migration_count} migrations"
            ),
        )
        schema_drift = conn.execute(
            "SELECT COUNT(*) AS count FROM chunks WHERE index_schema != ? OR chunker != ?",
            (INDEX_SCHEMA, CHUNKER_NAME),
        ).fetchone()["count"]
        if schema_drift:
            failed = True
            table.add_row(
                "index schema/chunker",
                "fail",
                f"{schema_drift} chunks not on {INDEX_SCHEMA}/{CHUNKER_NAME}",
            )
        else:
            table.add_row("index schema/chunker", "ok", f"{INDEX_SCHEMA}/{CHUNKER_NAME}")

    try:
        client = get_qdrant(config)
        client.get_collections()
        table.add_row("qdrant", "ok", config["qdrant_url"])
    except Exception as exc:  # pragma: no cover
        failed = True
        table.add_row("qdrant", "fail", str(exc))

    if args.deep:
        table.add_row(
            "tree-sitter",
            "ok" if tree_sitter_available() else "warn",
            "available" if tree_sitter_available() else "not installed; regex fallback active",
        )

        expected_size: int | None = None
        try:
            embedder = get_embedder(config)
            expected_size = len(list(embedder.embed(["doctor vector size probe"]))[0])
            table.add_row("embedding model", "ok", f"{config['embedding_model']} ({expected_size} dims)")
        except Exception as exc:
            failed = True
            table.add_row("embedding model", "fail", str(exc))

        if client is not None and expected_size is not None:
            try:
                collection_name = config["qdrant_collection"]
                if not client.collection_exists(collection_name):
                    failed = True
                    table.add_row("collection", "fail", f"missing: {collection_name}")
                else:
                    collection = client.get_collection(collection_name)
                    points = str(collection.points_count)
                    actual_size = collection_vector_size(collection)
                    if actual_size != expected_size:
                        failed = True
                        table.add_row(
                            "collection vector size",
                            "fail",
                            f"{collection_name}: expected {expected_size}, got {actual_size}",
                        )
                    else:
                        table.add_row(
                            "collection vector size",
                            "ok",
                            f"{collection_name}: {actual_size} dims ({points} points)",
                        )
            except Exception as exc:
                failed = True
                table.add_row("collection vector size", "fail", str(exc))

        try:
            request = urllib.request.Request(
                models_url(config["answer_url"]),
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8") or "{}")
            model_ids = [entry.get("id", "") for entry in payload.get("data", []) if isinstance(entry, dict)]
            if config["answer_model"] in model_ids:
                table.add_row("llama /v1/models", "ok", f"model alias found: {config['answer_model']}")
            else:
                failed = True
                detail = f"alias not found: {config['answer_model']}"
                if model_ids:
                    detail += f" (available: {', '.join(model_ids[:6])})"
                table.add_row("llama /v1/models", "fail", detail)
        except Exception as exc:  # pragma: no cover
            failed = True
            table.add_row("llama /v1/models", "fail", str(exc))

        gh_path = shutil.which("gh")
        if github_context_count > 0:
            if gh_path:
                table.add_row("gh cli", "ok", gh_path)
            else:
                failed = True
                table.add_row("gh cli", "fail", "github context is populated but gh is missing")
        else:
            table.add_row("gh cli", "ok" if gh_path else "warn", gh_path or "optional (no GitHub context rows yet)")

        table.add_row("fts populated", "ok" if chunk_count else "warn", str(chunk_count))
        table.add_row("facts populated", "ok" if fact_count else "warn", str(fact_count))
        table.add_row("file summaries", "ok" if summary_count else "warn", str(summary_count))
    else:
        table.add_row("embedding model", "ok", config["embedding_model"])
    table.add_row(
        "reranker",
        "ok" if config["reranker"]["enabled"] else "off",
        f"{config['reranker']['mode']} (top {config['reranker']['top_k_output']})",
    )
    for executor_id, ok, reason in executor_matrix():
        table.add_row(f"executor:{executor_id}", "ok" if ok else "warn", reason)
    for role, ok, reason in model_role_matrix():
        table.add_row(f"model:{role}", "ok" if ok else "warn", reason)
    profile_name, _profile = get_index_profile(config, None)
    table.add_row("index profile", "ok", profile_name)
    table.add_row(
        "context budget",
        "ok",
        (
            f"total={config['context_budget']['total_tokens']} "
            f"memory={config['context_budget']['memory_tokens']} "
            f"facts={config['context_budget']['facts_tokens']} "
            f"summaries={config['context_budget']['file_summary_tokens']} "
            f"chunks={config['context_budget']['chunk_tokens']}"
        ),
    )
    memory_statuses = repo_memory_status_rows(conn) if conn is not None else []
    stale_count = sum(1 for row in memory_statuses if row["status"] == "stale")
    missing_count = sum(1 for row in memory_statuses if row["status"] == "missing")
    table.add_row("memory freshness", "ok" if not stale_count and not missing_count else "warn", f"{stale_count} stale, {missing_count} missing")
    if args.deep:
        try:
            response = ask_llm(config, "reply with ok", "<chunks>\nhealth check\n</chunks>", mode="quick")
            table.add_row("answer generation", "ok" if response else "warn", (response or "-")[:60])
        except Exception as exc:  # pragma: no cover
            failed = True
            table.add_row("answer generation", "fail", str(exc))
    console.print(table)
    return 1 if failed else 0


def build_parser() -> argparse.ArgumentParser:
    parser = SuggestingArgumentParser(prog="rag")
    parser.set_defaults(needs_qdrant=False, needs_llm=False)
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_query_parser(
        name: str,
        help_text: str,
        handler,
        *,
        include_mode_flag: bool = False,
        default_output_format: str = "answer",
    ) -> argparse.ArgumentParser:
        query_parser = subparsers.add_parser(name, help=help_text)
        query_parser.add_argument("query")
        query_parser.add_argument("--repo", help="Filter to a repo name")
        query_parser.add_argument(
            "--memory",
            action="store_true",
            help="Force repo memory into the packed context for this run.",
        )
        query_parser.add_argument(
            "--show-context",
            action="store_true",
            help="Print the packed retrieval context before the answer or handoff.",
        )
        rerank_group = query_parser.add_mutually_exclusive_group()
        rerank_group.add_argument(
            "--rerank",
            dest="rerank",
            action="store_true",
            default=None,
            help="Force the reranker on for this query.",
        )
        rerank_group.add_argument(
            "--no-rerank",
            dest="rerank",
            action="store_false",
            help="Skip the reranker for this query.",
        )
        if include_mode_flag:
            query_parser.add_argument(
                "--mode",
                choices=["auto", "quick", "deep", "agent"],
                default="auto",
                help="Routing mode for `rag ask` (defaults to config routing.default_mode / auto).",
            )
        if name == "agent":
            query_parser.add_argument(
                "--output-format",
                choices=["handoff", "answer"],
                default=default_output_format,
                help="Emit a coding-agent handoff or a direct answer.",
            )
            query_parser.add_argument(
                "--save-handoff",
                action="store_true",
                help="Persist the generated handoff under ~/ai-rag/projects/<repo>/handoffs/.",
            )
            query_parser.add_argument(
                "--target-agent",
                choices=["generic", "codex", "opencode", "copilot", "human"],
                default="generic",
                help="Format handoffs for a specific downstream agent or reviewer.",
            )
        else:
            query_parser.set_defaults(output_format=default_output_format, save_handoff=False, target_agent="generic")
        query_parser.set_defaults(
            func=handler,
            needs_qdrant=True,
            needs_llm=name in {"ask", "quick", "deep", "agent"},
        )
        return query_parser

    index_parser = subparsers.add_parser("index", help="Index a repo or folder")
    index_parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="Repo or folder to index (defaults to the current directory).",
    )
    index_parser.add_argument(
        "--changed-only",
        action="store_true",
        help="Skip files whose content hash has not changed.",
    )
    index_parser.add_argument(
        "--profile",
        choices=["fast", "balanced", "deep"],
        help="Indexing profile to use (defaults to config indexing.profile).",
    )
    index_parser.set_defaults(func=cmd_index, needs_qdrant=True)

    add_query_parser("ask", "Ask a question against the local index", cmd_ask, include_mode_flag=True)
    add_query_parser("quick", "Force the fast retrieval+answer path", cmd_quick)
    add_query_parser("deep", "Force the deeper retrieval+planning path", cmd_deep)
    add_query_parser(
        "agent",
        "Build a longer-form answer or coding-agent handoff with operational state",
        cmd_agent,
        default_output_format="handoff",
    )
    handoff_parser = subparsers.add_parser("handoff", help="Build a target-specific coding handoff packet")
    handoff_parser.add_argument("target", choices=["codex", "opencode", "copilot", "human"])
    handoff_parser.add_argument("query")
    handoff_parser.add_argument("--repo", help="Filter to a repo name")
    handoff_parser.add_argument(
        "--memory",
        action="store_true",
        help="Force repo memory into the packed context for this run.",
    )
    handoff_parser.add_argument(
        "--show-context",
        action="store_true",
        help="Print the packed retrieval context before the handoff.",
    )
    handoff_rerank_group = handoff_parser.add_mutually_exclusive_group()
    handoff_rerank_group.add_argument(
        "--rerank",
        dest="rerank",
        action="store_true",
        default=None,
        help="Force the reranker on for this query.",
    )
    handoff_rerank_group.add_argument(
        "--no-rerank",
        dest="rerank",
        action="store_false",
        help="Skip the reranker for this query.",
    )
    handoff_parser.add_argument(
        "--save-handoff",
        action="store_true",
        help="Persist the generated handoff under ~/ai-rag/projects/<repo>/handoffs/.",
    )
    handoff_parser.set_defaults(func=cmd_handoff, output_format="handoff", needs_qdrant=True, needs_llm=True)

    search_parser = subparsers.add_parser("search", help="Search indexed chunks")
    search_parser.add_argument("query")
    search_parser.add_argument("--repo", help="Filter to a repo name")
    search_parser.add_argument(
        "--explain",
        action="store_true",
        help="Show query rewrites and retrieval-stage counts before the results.",
    )
    search_rerank_group = search_parser.add_mutually_exclusive_group()
    search_rerank_group.add_argument(
        "--rerank",
        dest="rerank",
        action="store_true",
        default=None,
        help="Force the reranker on for this query.",
    )
    search_rerank_group.add_argument(
        "--no-rerank",
        dest="rerank",
        action="store_false",
        help="Skip the reranker for this query.",
    )
    search_parser.set_defaults(func=cmd_search, needs_qdrant=True)

    add_query_parser("inspect", "Inspect query rewrites, intent, and routing details", cmd_inspect, include_mode_flag=True)
    add_query_parser("missing", "Show missing-context detection for a query", cmd_missing, include_mode_flag=True)

    suggest_parser = subparsers.add_parser("suggest", help="Suggest useful RAG workflows and commands")
    suggest_parser.add_argument("query", nargs="?", help="Optional topic, such as setup, debug, memory, or handoff")
    suggest_parser.set_defaults(func=cmd_suggest)

    why_parser = subparsers.add_parser("why", help="Explain why a file did or did not match a query")
    why_parser.add_argument("query")
    why_parser.add_argument("path", help="Indexed file path to explain")
    why_parser.add_argument("--repo", help="Filter to a repo name")
    why_rerank_group = why_parser.add_mutually_exclusive_group()
    why_rerank_group.add_argument(
        "--rerank",
        dest="rerank",
        action="store_true",
        default=None,
        help="Force the reranker on for this query.",
    )
    why_rerank_group.add_argument(
        "--no-rerank",
        dest="rerank",
        action="store_false",
        help="Skip the reranker for this query.",
    )
    why_parser.add_argument(
        "--mode",
        choices=["auto", "quick", "deep", "agent"],
        default="auto",
        help="Routing mode for this explanation query.",
    )
    why_parser.set_defaults(func=cmd_why)

    graph_parser = subparsers.add_parser("graph", help="Show a lightweight dependency graph from a symbol, route, or database seed")
    graph_parser.add_argument("query", nargs="?", help="Symbol or path text to seed the graph")
    graph_parser.add_argument("--repo", help="Filter to a repo name")
    graph_parser.add_argument("--route", nargs="+", help="Seed the graph from a route path/method")
    graph_parser.add_argument("--db", help="Seed the graph from a database/table/entity name")
    graph_parser.set_defaults(func=cmd_graph)

    context_parser = subparsers.add_parser("context", help="Manage git, GitHub, and test-failure retrieval sources")
    context_subparsers = context_parser.add_subparsers(dest="context_command", required=True)

    context_git_parser = context_subparsers.add_parser("git", help="Show or refresh git diff/branch context")
    context_git_parser.add_argument("--repo", help="Target repo name")
    context_git_parser.add_argument("--refresh", action="store_true", help="Refresh the git snapshot before showing it")
    context_git_parser.set_defaults(func=cmd_context)

    context_github_parser = context_subparsers.add_parser("github", help="Ingest PR or issue context")
    context_github_parser.add_argument("ref_type", choices=["issue", "pr"])
    context_github_parser.add_argument("number", type=int)
    context_github_parser.add_argument("--repo", help="Target repo name")
    context_github_parser.add_argument("--manual", action="store_true", help="Store manual fields instead of calling gh")
    context_github_parser.add_argument("--title", help="Manual title")
    context_github_parser.add_argument("--body", help="Manual body")
    context_github_parser.add_argument("--changed-file", action="append", help="Manual changed file (repeatable)")
    context_github_parser.add_argument("--comment", action="append", help="Manual comment (repeatable)")
    context_github_parser.add_argument("--review-comment", action="append", help="Manual review comment (repeatable)")
    context_github_parser.add_argument("--ci-log", help="Manual CI log excerpt")
    context_github_parser.add_argument("--linked-issue", action="append", help="Manual linked issue or PR reference")
    context_github_parser.set_defaults(func=cmd_context)

    context_failure_parser = context_subparsers.add_parser("test-failure", help="Store or inspect test failure output")
    context_failure_subparsers = context_failure_parser.add_subparsers(dest="failure_command", required=True)
    context_failure_list = context_failure_subparsers.add_parser("list", help="List stored test failures")
    context_failure_list.add_argument("--repo", help="Target repo name")
    context_failure_list.add_argument("--limit", type=int, default=20)
    context_failure_list.set_defaults(func=cmd_context)
    context_failure_add = context_failure_subparsers.add_parser("add", help="Store a test failure transcript")
    context_failure_add.add_argument("command_text")
    context_failure_add.add_argument("--repo", help="Target repo name")
    context_failure_add.add_argument("--runner")
    context_failure_add.add_argument("--exit-code", type=int)
    context_failure_add.add_argument("--source", choices=["local", "ci"], default="local")
    output_group = context_failure_add.add_mutually_exclusive_group(required=True)
    output_group.add_argument("--output", help="Inline failure output text")
    output_group.add_argument("--output-file", help="Path to a failure output file")
    context_failure_add.set_defaults(func=cmd_context)

    context_system_parser = context_subparsers.add_parser("system", help="Gather project tool context (Makefile, npm scripts, etc.)")
    context_system_parser.add_argument("--repo", help="Target repo")
    context_system_parser.add_argument("--store", action="store_true", help="Store result in RAG DB")
    context_system_parser.set_defaults(func=cmd_context)

    context_tmux_parser = context_subparsers.add_parser("tmux", help="Capture active tmux pane output")
    context_tmux_parser.add_argument("--lines", type=int, default=50, help="Number of lines to capture")
    context_tmux_parser.add_argument("--repo", help="Target repo")
    context_tmux_parser.add_argument("--store", action="store_true", help="Store as test failure if errors detected")
    context_tmux_parser.set_defaults(func=cmd_context)

    context_devhealth_parser = context_subparsers.add_parser("devhealth", help="Run dev-health and store result")
    context_devhealth_parser.add_argument("--repo", help="Target repo")
    context_devhealth_parser.add_argument("--store", action="store_true", help="Store result in RAG DB")
    context_devhealth_parser.set_defaults(func=cmd_context)

    reindex_parser = subparsers.add_parser("reindex", help="Reindex changed files in previously indexed repos")
    reindex_parser.add_argument(
        "--profile",
        choices=["fast", "balanced", "deep"],
        help="Indexing profile to use (defaults to config indexing.profile).",
    )
    reindex_parser.set_defaults(func=cmd_reindex, needs_qdrant=True)

    summarize_files_parser = subparsers.add_parser(
        "summarize-files",
        help="Refresh file summaries from indexed chunks and facts",
    )
    summarize_files_parser.add_argument("--repo", help="Refresh summaries for one repo")
    summarize_files_parser.add_argument(
        "--changed-only",
        action="store_true",
        help="Only refresh summaries whose file hash no longer matches.",
    )
    summarize_files_parser.set_defaults(func=cmd_summarize_files)

    summarize_parser = subparsers.add_parser("summarize", help="Generate durable repo memory")
    summarize_parser.add_argument("--repo", help="Summarize one indexed repo")
    summarize_parser.set_defaults(func=cmd_summarize)

    memory_parser = subparsers.add_parser("memory", help="Inspect repo memory, notes, context packs, and taxonomy")
    memory_subparsers = memory_parser.add_subparsers(dest="memory_command", required=True)

    memory_status_parser = memory_subparsers.add_parser("status", help="Show repo memory freshness")
    memory_status_parser.add_argument("--repo", help="Target repo name")
    memory_status_parser.set_defaults(func=cmd_memory)

    memory_show_parser = memory_subparsers.add_parser("show", help="Show stored repo memory")
    memory_show_parser.add_argument("--repo", help="Target repo name")
    memory_show_parser.set_defaults(func=cmd_memory)

    memory_refresh_parser = memory_subparsers.add_parser("refresh", help="Refresh stored repo memory")
    memory_refresh_parser.add_argument("--repo", help="Target repo name")
    memory_refresh_parser.set_defaults(func=cmd_memory)

    memory_clear_parser = memory_subparsers.add_parser("clear", help="Clear stored repo memory")
    memory_clear_parser.add_argument("--repo", help="Target repo name")
    memory_clear_parser.add_argument("--all", action="store_true", help="Apply clear to all repos")
    memory_clear_parser.set_defaults(func=cmd_memory)

    memory_remember_parser = memory_subparsers.add_parser("remember", help="Store structured developer memory")
    memory_remember_parser.add_argument("kind", choices=[
        "project_facts",
        "developer_preferences",
        "known_stack",
        "tool_preferences",
        "hardware_profile",
        "repo_conventions",
        "convention",
        "architecture",
        "tool",
        "pattern",
        "warning",
    ])
    memory_remember_parser.add_argument("subject")
    memory_remember_parser.add_argument("value", nargs="+")
    memory_remember_parser.add_argument("--repo", help="Scope to one repo")
    memory_remember_parser.add_argument(
        "--global-scope",
        action="store_true",
        help="Store this memory globally instead of tying it to a repo.",
    )
    memory_remember_parser.set_defaults(func=cmd_memory)

    memory_notes_parser = memory_subparsers.add_parser("notes", help="List structured memory notes")
    memory_notes_parser.add_argument("--repo", help="Target repo name")
    memory_notes_parser.add_argument("--kind", help="Filter by memory kind")
    memory_notes_parser.add_argument("--scope", choices=["all", "repo", "global"], default="all")
    memory_notes_parser.add_argument("--status", choices=["active", "stale", "conflict", "all"], default="active")
    memory_notes_parser.add_argument("--limit", type=int, default=20)
    memory_notes_parser.set_defaults(func=cmd_memory)

    memory_conflicts_parser = memory_subparsers.add_parser("conflicts", help="Show conflicting memory notes")
    memory_conflicts_parser.add_argument("--repo", help="Target repo name")
    memory_conflicts_parser.add_argument("--limit", type=int, default=20)
    memory_conflicts_parser.set_defaults(func=cmd_memory)

    memory_compact_parser = memory_subparsers.add_parser("compact", help="List or refresh session compactions")
    memory_compact_parser.add_argument("--repo", help="Target repo name")
    memory_compact_parser.add_argument("--session-id", help="Compact one saved session immediately")
    memory_compact_parser.add_argument("--limit", type=int, default=10)
    memory_compact_parser.set_defaults(func=cmd_memory)

    memory_pack_parser = memory_subparsers.add_parser("pack", help="Build and optionally write a reusable context pack")
    memory_pack_parser.add_argument("name")
    memory_pack_parser.add_argument("--repo", help="Target repo name")
    memory_pack_parser.add_argument("--target-agent", choices=["generic", "codex", "opencode", "copilot", "human"], default="generic")
    memory_pack_parser.add_argument("--write-file", action="store_true", help="Write .context/<name>.toon in the repo root")
    memory_pack_parser.set_defaults(func=cmd_memory)

    memory_taxonomy_parser = memory_subparsers.add_parser("taxonomy", help="Inspect the personal tool taxonomy")
    memory_taxonomy_parser.add_argument("--domain", help="Filter one taxonomy domain")
    memory_taxonomy_parser.add_argument("--query", help="Search taxonomy domains and tools")
    memory_taxonomy_parser.add_argument("--format", choices=["table", "yaml"], default="table")
    memory_taxonomy_parser.add_argument("--limit", type=int, default=30)
    memory_taxonomy_parser.set_defaults(func=cmd_memory)

    memory_extract_parser = memory_subparsers.add_parser("extract", help="Extract memory from recent session compactions")
    memory_extract_parser.add_argument("--repo", help="Target repo")
    memory_extract_parser.add_argument("--limit", type=int, default=20, help="Max sessions to analyse")
    memory_extract_parser.add_argument("--llm", action="store_true", help="Also run LLM-based extraction (slower)")
    memory_extract_parser.set_defaults(func=cmd_memory)

    memory_consolidate_parser = memory_subparsers.add_parser("consolidate", help="Merge duplicates and expire stale memory")
    memory_consolidate_parser.add_argument("--repo", help="Target repo")
    memory_consolidate_parser.set_defaults(func=cmd_memory)

    memory_prune_parser = memory_subparsers.add_parser("prune", help="Delete old stale memory entries")
    memory_prune_parser.add_argument("--repo", help="Target repo")
    memory_prune_parser.add_argument("--days", type=int, default=180, help="Delete stale entries older than N days")
    memory_prune_parser.set_defaults(func=cmd_memory)

    memory_promote_parser = memory_subparsers.add_parser("promote", help="Promote facts seen across 3+ sessions")
    memory_promote_parser.add_argument("--repo", help="Target repo")
    memory_promote_parser.add_argument("--threshold", type=int, default=3, help="Min sessions to trigger promotion")
    memory_promote_parser.set_defaults(func=cmd_memory)

    todo_parser = subparsers.add_parser("todo", help="Manage structured RAG todos")
    todo_subparsers = todo_parser.add_subparsers(dest="todo_command", required=True)
    todo_list_parser = todo_subparsers.add_parser("list", help="List todos")
    todo_list_parser.add_argument("--repo", help="Filter to one repo")
    todo_list_parser.add_argument("--status", choices=["open", "in_progress", "done", "all"], default="open")
    todo_list_parser.add_argument("--limit", type=int, default=20)
    todo_list_parser.set_defaults(func=cmd_todo)
    todo_add_parser = todo_subparsers.add_parser("add", help="Add a todo")
    todo_add_parser.add_argument("title")
    todo_add_parser.add_argument("--repo", help="Scope to one repo")
    todo_add_parser.add_argument("--detail")
    todo_add_parser.add_argument("--status", choices=["open", "in_progress", "done"], default="open")
    todo_add_parser.set_defaults(func=cmd_todo)
    todo_done_parser = todo_subparsers.add_parser("done", help="Mark a todo done")
    todo_done_parser.add_argument("todo_id", type=int)
    todo_done_parser.set_defaults(func=cmd_todo)
    todo_start_parser = todo_subparsers.add_parser("start", help="Mark a todo in progress")
    todo_start_parser.add_argument("todo_id", type=int)
    todo_start_parser.set_defaults(func=cmd_todo)

    decision_parser = subparsers.add_parser("decision", help="Manage structured engineering decisions")
    decision_subparsers = decision_parser.add_subparsers(dest="decision_command", required=True)
    decision_list_parser = decision_subparsers.add_parser("list", help="List decisions")
    decision_list_parser.add_argument("--repo", help="Filter to one repo")
    decision_list_parser.add_argument("--limit", type=int, default=20)
    decision_list_parser.set_defaults(func=cmd_decision)
    decision_add_parser = decision_subparsers.add_parser("add", help="Record a decision")
    decision_add_parser.add_argument("title")
    decision_add_parser.add_argument("detail")
    decision_add_parser.add_argument("--repo", help="Scope to one repo")
    decision_add_parser.add_argument("--rationale")
    decision_add_parser.set_defaults(func=cmd_decision)

    command_parser = subparsers.add_parser("command", help="Remember useful commands")
    command_subparsers = command_parser.add_subparsers(dest="command_memory_command", required=True)
    command_list_parser = command_subparsers.add_parser("list", help="List remembered commands")
    command_list_parser.add_argument("--repo", help="Filter to one repo")
    command_list_parser.add_argument("--limit", type=int, default=20)
    command_list_parser.set_defaults(func=cmd_command_memory)
    command_add_parser = command_subparsers.add_parser("add", help="Store a useful command")
    command_add_parser.add_argument("command_text")
    command_add_parser.add_argument("--repo", help="Scope to one repo")
    command_add_parser.add_argument("--purpose")
    command_add_parser.add_argument("--notes")
    command_add_parser.set_defaults(func=cmd_command_memory)

    error_parser = subparsers.add_parser("error", help="Remember recurring errors and fixes")
    error_subparsers = error_parser.add_subparsers(dest="error_command", required=True)
    error_list_parser = error_subparsers.add_parser("list", help="List remembered errors")
    error_list_parser.add_argument("--repo", help="Filter to one repo")
    error_list_parser.add_argument("--limit", type=int, default=20)
    error_list_parser.set_defaults(func=cmd_error_memory)
    error_add_parser = error_subparsers.add_parser("add", help="Store an error/fix pair")
    error_add_parser.add_argument("error_text")
    error_add_parser.add_argument("--repo", help="Scope to one repo")
    error_add_parser.add_argument("--fix")
    error_add_parser.add_argument("--notes")
    error_add_parser.add_argument("--command", dest="command_text", help="Command that produced the error")
    error_add_parser.add_argument("--exit-code", type=int, help="Exit code for the failing command")
    error_add_parser.set_defaults(func=cmd_error_memory)

    session_parser = subparsers.add_parser("session", help="Inspect saved RAG sessions")
    session_subparsers = session_parser.add_subparsers(dest="session_command", required=True)
    session_list_parser = session_subparsers.add_parser("list", help="List saved sessions")
    session_list_parser.add_argument("--repo", help="Filter to one repo")
    session_list_parser.add_argument("--limit", type=int, default=20)
    session_list_parser.set_defaults(func=cmd_session)
    session_show_parser = session_subparsers.add_parser("show", help="Show one saved session")
    session_show_parser.add_argument("session_id")
    session_show_parser.set_defaults(func=cmd_session)

    facts_parser = subparsers.add_parser("facts", help="List or query structured facts")
    facts_parser.add_argument("subject", help="Use `list` or a fact kind like alias, keybind, env, tool, sql-object")
    facts_parser.add_argument("query", nargs="*", help="Search text when querying a fact kind")
    facts_parser.add_argument("--repo", help="Filter to one repo")
    facts_parser.add_argument("--kind", help="Fact kind filter when using `rag facts list`")
    facts_parser.set_defaults(func=cmd_facts)

    trace_parser = subparsers.add_parser("trace", help="Trace facts back to nearby indexed evidence")
    trace_parser.add_argument("kind", help="Fact kind to trace, like keybind, tool, alias, env, or sql-object")
    trace_parser.add_argument("query", nargs="+", help="Search text for the trace query")
    trace_parser.add_argument("--repo", help="Filter to one repo")
    trace_parser.add_argument("--limit", type=int, default=5, help="Maximum fact matches to trace")
    trace_parser.set_defaults(func=cmd_trace)

    status_parser = subparsers.add_parser("status", help="Show quick local RAG status")
    status_parser.set_defaults(func=cmd_status)

    route_parser = subparsers.add_parser("route", help="Show model routing decision for a query")
    route_parser.add_argument("query", help="Query to diagnose")
    route_parser.add_argument("--context", default="", help="Optional context text to simulate")
    route_parser.set_defaults(func=cmd_route, needs_qdrant=False, needs_llm=False)

    clean_parser = subparsers.add_parser("clean", help="Clear repo-specific or full local RAG state")
    clean_scope = clean_parser.add_mutually_exclusive_group(required=True)
    clean_scope.add_argument("--repo", help="Clear one indexed repo by name")
    clean_scope.add_argument("--all", action="store_true", help="Clear the whole local RAG index")
    clean_parser.set_defaults(func=cmd_clean, needs_qdrant=True)

    doctor_parser = subparsers.add_parser("doctor", help="Check local RAG health")
    doctor_parser.add_argument(
        "--deep",
        action="store_true",
        help="Run deeper health checks (config/schema drift, vector sizing, /v1/models alias checks, gh/tree-sitter, and answer probe).",
    )
    doctor_parser.set_defaults(func=cmd_doctor, needs_qdrant=False)

    learn_parser = subparsers.add_parser("learn", help="Review pending memory candidates")
    learn_parser.add_argument("--status", choices=["pending", "accepted", "rejected", "edited", "all"], default="pending")
    learn_parser.add_argument("--limit", type=int, default=20)
    learn_parser.add_argument("--candidate-id")
    learn_parser.add_argument("--review-status", choices=["accepted", "rejected", "edited"])
    learn_parser.add_argument("--content", help="Replacement content when marking a candidate edited")
    learn_parser.set_defaults(func=cmd_learn)

    skill_parser = subparsers.add_parser("skill", help="Manage and generate OpenCode skills")
    skill_subparsers = skill_parser.add_subparsers(dest="skill_command", required=True)

    skill_list_parser = skill_subparsers.add_parser("list", help="List all repo and auto-generated skills")
    skill_list_parser.set_defaults(func=cmd_skill, needs_qdrant=False, needs_llm=False)

    skill_gen_parser = skill_subparsers.add_parser("generate", help="Generate skills from session patterns")
    skill_gen_parser.add_argument("--repo", help="Limit to one repo (omit for current repo)")
    skill_gen_parser.add_argument("--global", dest="global_scope", action="store_true", help="Analyse all repos")
    skill_gen_parser.add_argument("--force", action="store_true", help="Overwrite existing auto-generated skills")
    skill_gen_parser.set_defaults(func=cmd_skill, needs_qdrant=False, needs_llm=True)

    mcp_parser = subparsers.add_parser("mcp", help="Run the local RAG MCP-style stdio tool server")
    mcp_parser.set_defaults(func=cmd_mcp)

    task_parser = subparsers.add_parser("task", help="Manage .agent/ task workflow files")
    task_subparsers = task_parser.add_subparsers(dest="task_command", required=True)

    task_init_parser = task_subparsers.add_parser("init", help="Initialize a new task in .agent/")
    task_init_parser.add_argument("description", help="Task description")
    task_init_parser.add_argument("--timestamped", action="store_true", help="Create a timestamped task file (task-YYYYMMDD-HHMMSS.md)")
    task_init_parser.set_defaults(func=cmd_task, needs_qdrant=False, needs_llm=False)

    task_context_parser = task_subparsers.add_parser("context", help="Refresh context and build agent handoff")
    task_context_parser.add_argument("--target-agent", default="opencode", choices=["opencode", "codex", "copilot", "generic"])
    task_context_parser.set_defaults(func=cmd_task, needs_qdrant=True, needs_llm=True)

    task_done_parser = task_subparsers.add_parser("done", help="Mark current task complete")
    task_done_parser.add_argument("--summary", help="Completion summary")
    task_done_parser.set_defaults(func=cmd_task, needs_qdrant=False, needs_llm=False)

    task_list_parser = task_subparsers.add_parser("list", help="List task files in .agent/")
    task_list_parser.set_defaults(func=cmd_task, needs_qdrant=False, needs_llm=False)

    serve_parser = subparsers.add_parser("serve", help="Run local RAG integration servers")
    serve_parser.add_argument("--http", action="store_true", help="Run the HTTP JSON endpoint server")
    serve_parser.add_argument("--host", default="127.0.0.1")
    serve_parser.add_argument("--port", type=int, default=7433)
    serve_parser.set_defaults(func=cmd_serve)
    return parser


LEGACY_COMMANDS = {
    "agent",
    "ask",
    "clean",
    "command",
    "context",
    "decision",
    "deep",
    "doctor",
    "error",
    "facts",
    "graph",
    "handoff",
    "index",
    "inspect",
    "learn",
    "memory",
    "missing",
    "mcp",
    "quick",
    "reindex",
    "route",
    "search",
    "serve",
    "session",
    "skill",
    "status",
    "suggest",
    "summarize",
    "summarize-files",
    "task",
    "todo",
    "trace",
    "why",
}


def _parse_public_invocation(flag: str, rest: list[str]) -> argparse.Namespace:
    dry_run = False
    repo: str | None = None
    remaining: list[str] = []
    index = 0
    while index < len(rest):
        item = rest[index]
        if item == "--dry-run":
            dry_run = True
        elif item == "--repo" and index + 1 < len(rest):
            repo = rest[index + 1]
            index += 1
        else:
            remaining.append(item)
        index += 1
    query = " ".join(remaining).strip()
    if not query:
        raise SystemExit(f"{flag} requires a task string")
    target = flag.removeprefix("--")
    if target == "plan":
        return argparse.Namespace(query=query, repo=repo, target=None, func=cmd_v7_plan, needs_qdrant=False, needs_llm=False)
    if target == "context":
        return argparse.Namespace(query=query, repo=repo, target=None, rerank=None, func=cmd_v7_context, needs_qdrant=True, needs_llm=False)
    return argparse.Namespace(query=query, repo=repo, target=target, rerank=None, dry_run=dry_run, func=cmd_v7_execute, needs_qdrant=True, needs_llm=False)


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        from .tui import run_tui

        return run_tui()
    if argv[0] == "debug":
        if len(argv) == 1:
            raise SystemExit("Use `rag debug <legacy-command> ...`.")
        argv = argv[1:]
    if argv[0] == "--doctor":
        argv = ["doctor", *argv[1:]]
    elif argv[0] == "--learn":
        argv = ["learn", *argv[1:]]
    elif argv[0] in {"--plan", "--context", "--codex", "--opencode", "--aider"}:
        args = _parse_public_invocation(argv[0], argv[1:])
        try:
            ensure_local_runtime(args)
            return args.func(args)
        except KeyboardInterrupt:
            console.print("[yellow]Cancelled.[/yellow]")
            return 130
    elif argv[0] not in LEGACY_COMMANDS and not argv[0].startswith("-"):
        args = argparse.Namespace(
            query=" ".join(argv),
            repo=None,
            target=None,
            rerank=None,
            dry_run=True,
            func=cmd_v7_execute,
            needs_qdrant=True,
            needs_llm=False,
        )
        try:
            ensure_local_runtime(args)
            return args.func(args)
        except KeyboardInterrupt:
            console.print("[yellow]Cancelled.[/yellow]")
            return 130
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        ensure_local_runtime(args)
        return args.func(args)
    except KeyboardInterrupt:
        console.print("[yellow]Cancelled.[/yellow]")
        return 130
    except sqlite3.OperationalError as exc:
        if "database is locked" in str(exc).lower():
            console.print(
                "[yellow]RAG database is busy.[/yellow] Another rag command is already using the local index. "
                "Wait for it to finish or stop it, then retry."
            )
            return 1
        raise
