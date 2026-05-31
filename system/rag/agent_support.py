from __future__ import annotations

import fnmatch
import json
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

from .profiles import load_repo_profile
from .retrieval import approx_tokens, gather_context, retrieve, reranker_enabled
from .router import build_agent_plan
from .settings import get_mode_profile, load_config
from .state import (
    format_operational_state,
    list_git_contexts,
    list_retrieval_cache,
    list_retrieval_outcomes,
    load_operational_state,
    record_retrieval_run,
    record_retrieval_outcome,
)
from .storage import connect_db, get_qdrant, git_branch_for, infer_repo_filter


def repo_root() -> Path:
    current = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists() or (current / ".agent").exists():
            return current
        current = current.parent
    return Path.cwd()


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


def _unique(items: list[str]) -> list[str]:
    return [item for item in dict.fromkeys(item for item in items if item)]


def _query_terms(text: str) -> set[str]:
    return {token for token in text.lower().replace("/", " ").replace("_", " ").split() if len(token) > 2}


def _runtime_ranking_hints(conn: sqlite3.Connection, repo: str | None, query: str) -> dict[str, Any]:
    profile = load_repo_profile(repo_root())
    boost_paths = list(profile.get("boost_paths", []))
    missed_paths: list[str] = []
    query_terms = _query_terms(query)
    for row in list_retrieval_outcomes(conn, repo, limit=60):
        task_terms = _query_terms(row["task"])
        overlap = len(query_terms & task_terms)
        if not query_terms or overlap == 0:
            continue
        edited = json.loads(row["edited_files_json"] or "[]")
        missed = json.loads(row["missed_files_json"] or "[]")
        boost_paths.extend(edited[:4])
        missed_paths.extend(missed[:4])
    hot_paths = [row["path"] for row in list_retrieval_cache(conn, repo, limit=25) if row["kind"] in {"hot", "edited"}]
    return {
        "repo_profile": profile,
        "adaptive_ranking": {
            "boost_paths": _unique(boost_paths + hot_paths),
            "missed_paths": _unique(missed_paths),
            "avoid_patterns": list(profile.get("generated_patterns", [])),
            "hot_paths": _unique(hot_paths),
        },
    }


def runtime_config(base_config: dict, conn: sqlite3.Connection, repo: str | None, query: str) -> dict:
    config = json.loads(json.dumps(base_config))
    hints = _runtime_ranking_hints(conn, repo, query)
    config.update(hints)
    return config


def related_tests(conn: sqlite3.Connection, repo: str | None, path: str, limit: int = 6) -> list[dict[str, Any]]:
    if not repo:
        return []
    stem = Path(path).stem.replace(".spec", "").replace(".test", "")
    candidates = conn.execute(
        """
        SELECT DISTINCT path
        FROM file_summaries
        WHERE repo = ?
          AND path != ?
          AND (
            path LIKE '%test%'
            OR path LIKE '%spec%'
            OR path LIKE 'tests/%'
            OR path LIKE '%/tests/%'
          )
        ORDER BY path
        """,
        (repo, path),
    ).fetchall()
    matches: list[dict[str, Any]] = []
    for row in candidates:
        candidate = row["path"]
        confidence = 0.35
        reason = "nearby indexed test"
        if stem and stem in Path(candidate).stem:
            confidence = 0.84
            reason = "same stem + nearby spec"
        elif Path(path).parent == Path(candidate).parent.parent:
            confidence = 0.62
            reason = "same module area"
        matches.append({"path": candidate, "confidence": round(confidence, 2), "reason": reason})
    matches.sort(key=lambda item: item["confidence"], reverse=True)
    return matches[:limit]


def suggest_commands(root: Path, selected_files: list[str], task: str, profile: dict | None = None) -> list[str]:
    profile = profile or load_repo_profile(root)
    commands = list(profile.get("check_commands", []))
    if any(path.endswith((".sh", ".zsh")) for path in selected_files) and (root / "setup" / "check-shell.sh").exists():
        shell_targets = " ".join(path for path in selected_files[:8] if path.endswith((".sh", ".zsh")))
        commands.append(f"bash setup/check-shell.sh {shell_targets}".strip())
    if any(path.startswith(("system/rag/", "tests/rag/")) for path in selected_files) or "rag" in task.lower():
        commands.append("python -m unittest discover -s tests/rag -p 'test_*.py'")
    return _unique(commands)


def build_edit_scope(
    conn: sqlite3.Connection,
    repo: str | None,
    rows: list[sqlite3.Row],
    summaries: list[sqlite3.Row],
    query: str,
    profile: dict | None = None,
) -> dict[str, list[dict[str, Any]]]:
    profile = profile or load_repo_profile(repo_root())
    likely_edit: list[dict[str, Any]] = []
    read_only: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in rows[:8]:
        path = row["path"]
        if path in seen:
            continue
        seen.add(path)
        entry = {
            "path": path,
            "reason": f"top ranked {row['kind']} chunk for the task",
            "confidence": 0.9 if len(likely_edit) < 3 else 0.72,
            "source_channels": ["semantic", "keyword", "rerank"],
        }
        if any(marker in path for marker in ("/tests/", "tests/", ".spec.", ".test.")):
            read_only.append({**entry, "reason": "test evidence selected for inspection"})
        elif row["kind"] in {"docs", "text"}:
            read_only.append({**entry, "reason": "supporting documentation context"})
        else:
            likely_edit.append(entry)
    summary_paths = {row["path"] for row in summaries[:8]}
    for path in summary_paths:
        if path in seen:
            continue
        if any(marker in path for marker in ("/docs/", "README", ".md")):
            read_only.append(
                {
                    "path": path,
                    "reason": "supporting docs or repo memory summary",
                    "confidence": 0.55,
                    "source_channels": ["summaries"],
                }
            )
    likely_tests: list[dict[str, Any]] = []
    for item in likely_edit[:4]:
        for test in related_tests(conn, repo, item["path"], limit=2):
            likely_tests.append(
                {
                    "path": test["path"],
                    "reason": test["reason"],
                    "confidence": test["confidence"],
                    "source_channels": ["summaries", "path-pattern"],
                }
            )
    avoid = [
        {
            "path": pattern,
            "reason": "generated or ignored path from repo profile",
            "confidence": 0.92,
            "source_channels": ["repo-profile"],
        }
        for pattern in _unique(list(profile.get("ignore_dirs", [])) + list(profile.get("generated_patterns", [])))[:8]
    ]
    return {
        "likely_edit": likely_edit[:6],
        "likely_tests": _unique_dicts(likely_tests)[:6],
        "read_only": _unique_dicts(read_only)[:6],
        "avoid": avoid,
    }


def _unique_dicts(items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[str] = set()
    unique: list[dict[str, Any]] = []
    for item in items:
        key = item.get("path", "") + ":" + item.get("reason", "")
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)
    return unique


def missing_context_payload(result, selected_files: list[str] | None = None) -> dict[str, Any]:
    debug = result.debug
    return {
        "sufficient": not bool(debug.get("missing_context_remaining")),
        "missing": list(debug.get("missing_context_remaining", [])),
        "desired": list(debug.get("missing_context_desired", [])),
        "added": list(debug.get("missing_context_added", [])),
        "selected_files": selected_files or [row["path"] for row in result.rows[:8]],
        "followup_queries": [
            f"inspect {humanize_missing_label(label)} for {result.plan.query}"
            for label in list(debug.get("missing_context_remaining", []))[:3]
        ],
    }


def file_card(conn: sqlite3.Connection, repo: str | None, path: str, why_selected: str | None = None) -> dict[str, Any]:
    summary_row = None
    if repo:
        summary_row = conn.execute(
            "SELECT * FROM file_summaries WHERE repo = ? AND path = ?",
            (repo, path),
        ).fetchone()
    symbols = []
    imports = []
    if repo:
        symbols = [
            row["name"]
            for row in conn.execute(
                "SELECT name FROM symbols WHERE repo = ? AND path = ? ORDER BY exported DESC, start_line ASC LIMIT 8",
                (repo, path),
            ).fetchall()
        ]
        imports = [
            row["dependency"]
            for row in conn.execute(
                "SELECT dependency FROM file_dependencies WHERE repo = ? AND source_path = ? ORDER BY updated_at DESC LIMIT 8",
                (repo, path),
            ).fetchall()
        ]
    tests = related_tests(conn, repo, path, limit=4)
    risk_level = "low"
    lowered = path.lower()
    if any(marker in lowered for marker in ("migration", "config", ".env", "mcp_server", "cli.py")):
        risk_level = "high"
    elif any(marker in lowered for marker in ("service", "router", "executor")):
        risk_level = "medium"
    purpose = "Indexed file"
    if summary_row and summary_row["summary"]:
        purpose = str(summary_row["summary"]).split(".")[0]
    return {
        "path": path,
        "purpose": purpose,
        "exports": symbols[:5],
        "imports": imports[:5],
        "main_symbols": symbols[:8],
        "related_tests": tests,
        "risk_level": risk_level,
        "why_selected": why_selected or "Selected by retrieval ranking and supporting summaries.",
    }


def perf_report_from_result(result, packed_tokens: int) -> dict[str, Any]:
    debug = result.debug
    candidate_counts = {
        "semantic": debug.get("semantic_hits", 0),
        "keyword": debug.get("keyword_hits", 0),
        "semantic_lines": debug.get("semantic_line_hits", 0),
        "symbol": debug.get("symbol_hits", 0),
        "recent": debug.get("recent_hits", 0),
        "facts": debug.get("fact_hits", 0),
        "summaries": debug.get("file_summary_hits", 0),
        "github": debug.get("github_refs", 0),
        "test_failures": debug.get("test_failures", 0),
        "errors": debug.get("error_matches", 0),
    }
    timings = debug.get("timings_ms", {})
    slow_stages = [stage for stage, value in timings.items() if float(value) >= 150.0]
    recommendations: list[str] = []
    if result.plan.mode == "quick" and any(stage in slow_stages for stage in ("github", "test_failures", "errors")):
        recommendations.append("keep quick mode on cheap channels only")
    if packed_tokens > 10000:
        recommendations.append("trim packed context or rely more on file summaries")
    return {
        "slow_stages": slow_stages,
        "candidate_counts": candidate_counts,
        "packed_tokens": packed_tokens,
        "recommendations": recommendations,
    }


def git_state_markdown(conn: sqlite3.Connection, repo: str | None) -> str:
    rows = list_git_contexts(conn, repo, limit=1)
    if not rows:
        return "- no git context captured"
    row = rows[0]
    changed = json.loads(row["changed_files_json"] or "[]")
    return (
        f"- branch: {row['branch']}\n"
        f"- dirty: {'yes' if row['dirty'] else 'no'}\n"
        f"- changed: {', '.join(changed[:6]) or '-'}"
    )


def _record_run(
    conn: sqlite3.Connection,
    repo: str | None,
    task: str,
    plan,
    result,
    context: str,
    edit_scope: dict[str, Any],
    commands: list[str],
) -> dict[str, Any]:
    run_id = str(uuid.uuid4())
    selected_files = _unique([row["path"] for row in result.rows[:10]] + [row["path"] for row in result.summaries[:10]])
    candidate_counts = {
        "semantic": int(result.debug.get("semantic_hits", 0)),
        "keyword": int(result.debug.get("keyword_hits", 0)),
        "semantic_lines": int(result.debug.get("semantic_line_hits", 0)),
        "symbol": int(result.debug.get("symbol_hits", 0)),
        "recent": int(result.debug.get("recent_hits", 0)),
        "facts": int(result.debug.get("fact_hits", 0)),
        "summaries": int(result.debug.get("file_summary_hits", 0)),
        "github": int(result.debug.get("github_refs", 0)),
        "test_failures": int(result.debug.get("test_failures", 0)),
        "errors": int(result.debug.get("error_matches", 0)),
    }
    return record_retrieval_run(
        conn,
        run_id=run_id,
        repo=repo,
        branch=git_branch_for(repo_root()),
        query=task,
        mode=plan.mode,
        intent=plan.intent,
        plan=plan.to_dict(),
        rewrites=list(result.debug.get("rewrites", [])),
        candidate_counts=candidate_counts,
        selected_files=selected_files,
        edit_scope=edit_scope,
        missing_context=missing_context_payload(result, selected_files),
        packed_context_token_estimate=approx_tokens(context),
        timings_ms=result.debug.get("timings_ms", {}),
        metadata={
            "suggested_commands": commands,
            "context_sources": [source.title for source in result.context_sources],
        },
        export_root=repo_root(),
    )


def describe_task(task: str, *, repo: str | None = None, target_agent: str = "opencode") -> dict[str, Any]:
    conn = connect_db()
    resolved_repo = infer_repo_filter(conn, repo)
    base_config = load_config()
    plan = build_agent_plan(task, conn=conn, repo=resolved_repo)
    effective_config = runtime_config(get_mode_profile(base_config, "agent"), conn, resolved_repo, task)
    result = retrieve(
        conn,
        get_qdrant(effective_config),
        effective_config,
        task,
        resolved_repo,
        reranker_enabled(effective_config, None),
        mode="agent",
    )
    state_text = format_operational_state(load_operational_state(conn, resolved_repo))
    memory_text = result.memory["summary"] if result.memory else ""
    context, files = gather_context(
        result.rows,
        effective_config,
        facts=result.facts,
        summaries=result.summaries,
        context_sources=result.context_sources,
        memory=memory_text,
        operational_state=state_text,
        operational_state_tokens=int(effective_config["answer"]["operational_state_tokens"]),
    )
    edit_scope = build_edit_scope(conn, resolved_repo, result.rows, result.summaries, task, effective_config.get("repo_profile"))
    commands = suggest_commands(repo_root(), files, task, effective_config.get("repo_profile"))
    run_payload = _record_run(conn, resolved_repo, task, plan, result, context, edit_scope, commands)
    missing = missing_context_payload(result, files)
    ready = bool(edit_scope["likely_edit"]) and len(missing["missing"]) <= 1
    evidence = _unique(files + [row["path"] for row in result.summaries[:6]])
    return {
        "task": task,
        "repo": resolved_repo,
        "target_agent": target_agent,
        "plan": plan.to_dict(),
        "result": result,
        "context": context,
        "files": files,
        "edit_scope": edit_scope,
        "missing_context": missing,
        "suggested_commands": commands,
        "project_memory": memory_text,
        "git_state": git_state_markdown(conn, resolved_repo),
        "evidence": evidence,
        "run": run_payload,
        "ready_to_edit": ready,
        "perf_report": perf_report_from_result(result, approx_tokens(context)),
    }


def render_agent_context_markdown(payload: dict[str, Any]) -> str:
    edit_scope = payload["edit_scope"]
    missing = payload["missing_context"]
    current_subtask = payload.get("current_subtask")
    edit_lines = [f"- edit: {item['path']} ({item['reason']})" for item in edit_scope["likely_edit"]]
    test_lines = [f"- tests: {item['path']} ({item['reason']})" for item in edit_scope["likely_tests"]]
    read_only_lines = [f"- read-only: {item['path']} ({item['reason']})" for item in edit_scope["read_only"]]
    avoid_lines = [f"- avoid: {item['path']} ({item['reason']})" for item in edit_scope["avoid"]]
    inspect_lines = [f"- {item}" for item in payload["files"][:6]]
    evidence_lines = [f"- {item}" for item in payload["evidence"][:8]]
    missing_lines = [f"- {humanize_missing_label(item)}" for item in missing["missing"]]
    command_lines = [f"- `{item}`" for item in payload["suggested_commands"]]
    next_tool = payload.get("next_mcp_tool") or ("rag_subtask_context" if payload["ready_to_edit"] else "rag_missing_context")
    sections = [
        "# Agent context",
        "",
        "## Task",
        payload["task"],
        "",
        "## Verdict",
        f"ready_to_edit: {'yes' if payload['ready_to_edit'] else 'no'}",
        "",
        "## Current Subtask",
        current_subtask["id"] if isinstance(current_subtask, dict) and current_subtask.get("id") else (current_subtask or "-"),
        "",
        "## Edit Scope",
        *(edit_lines or ["- none"]),
        *test_lines,
        *read_only_lines,
        *avoid_lines,
        "",
        "## Must Inspect First",
        *(inspect_lines or ["- none"]),
        "",
        "## Project Memory",
        payload["project_memory"] or "- no stored repo memory",
        "",
        "## Git State",
        payload["git_state"],
        "",
        "## Evidence",
        *(evidence_lines or ["- none"]),
        "",
        "## Missing Context",
        *(missing_lines or ["- no major gaps detected"]),
        "",
        "## Suggested Commands",
        *(command_lines or ["- none"]),
        "",
        "## Grounding Rules",
        "- Stay inside the suggested edit scope unless direct file inspection disproves it.",
        "- Re-open the cited files before editing and treat docs/tests as evidence, not assumptions.",
        "- Do not claim checks passed unless command output confirms it.",
        "",
        "## Next MCP Tool To Call",
        next_tool,
        "",
        f"run_id: {payload['run']['run_id']}",
    ]
    return "\n".join(sections).strip()


def evaluate_query(query: str, *, repo: str | None = None, mode: str = "deep") -> dict[str, Any]:
    conn = connect_db()
    resolved_repo = infer_repo_filter(conn, repo)
    config = runtime_config(get_mode_profile(load_config(), mode), conn, resolved_repo, query)
    started = time.perf_counter()
    result = retrieve(
        conn,
        get_qdrant(config),
        config,
        query,
        resolved_repo,
        reranker_enabled(config, None),
        mode=mode,
    )
    context, files = gather_context(
        result.rows,
        config,
        facts=result.facts,
        summaries=result.summaries,
        context_sources=result.context_sources,
        memory=result.memory["summary"] if result.memory else None,
    )
    latency_ms = (time.perf_counter() - started) * 1000
    packed_tokens = approx_tokens(context)
    warnings = [humanize_missing_label(item) for item in result.debug.get("missing_context_remaining", [])]
    candidate_counts = {
        "semantic": int(result.debug.get("semantic_hits", 0)),
        "keyword": int(result.debug.get("keyword_hits", 0)),
        "semantic_lines": int(result.debug.get("semantic_line_hits", 0)),
        "symbol": int(result.debug.get("symbol_hits", 0)),
        "recent": int(result.debug.get("recent_hits", 0)),
        "facts": int(result.debug.get("fact_hits", 0)),
        "summaries": int(result.debug.get("file_summary_hits", 0)),
        "github": int(result.debug.get("github_refs", 0)),
        "test_failures": int(result.debug.get("test_failures", 0)),
        "errors": int(result.debug.get("error_matches", 0)),
    }
    return {
        "query": query,
        "top_files": files[:10],
        "coverage": {
            "selected_chunks": len(result.rows),
            "summaries": len(result.summaries),
            "missing_context": list(result.debug.get("missing_context_remaining", [])),
        },
        "warnings": warnings,
        "latency_ms": round(latency_ms, 2),
        "packed_token_count": packed_tokens,
        "candidate_counts_by_channel": candidate_counts,
        "edit_scope": build_edit_scope(conn, resolved_repo, result.rows, result.summaries, query, config.get("repo_profile")),
        "result": result,
    }


def record_outcome(
    *,
    repo: str | None,
    task: str,
    retrieved_files: list[str],
    edited_files: list[str],
    checks_run: list[str],
    passed: bool,
    notes: str | None = None,
    run_id: str | None = None,
) -> int:
    conn = connect_db()
    return record_retrieval_outcome(
        conn,
        repo=repo,
        task=task,
        retrieved_files=retrieved_files,
        edited_files=edited_files,
        checks_run=checks_run,
        passed=passed,
        notes=notes,
        run_id=run_id,
    )
