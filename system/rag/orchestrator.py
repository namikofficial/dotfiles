from __future__ import annotations

import json
import re
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from .agent_support import build_edit_scope, missing_context_payload, render_agent_context_markdown, related_tests
from .commands import command_plan_for_subtask
from .profile import learn_profile_from_run, profile_show
from .retrieval import gather_context, reranker_enabled, retrieve
from .run_trace import write_task_run_export
from .settings import get_mode_profile, load_config
from .state import (
    get_task_run,
    latest_task_run,
    list_task_outcomes,
    list_task_outcomes_for_run,
    list_task_outcomes_for_task,
    record_task_outcome,
    record_task_lesson,
    record_task_run,
    redact_sensitive_text,
    task_run_payload,
    update_task_run_status,
    update_task_subtask_status,
)
from .storage import connect_db, get_qdrant, infer_repo_filter
from .task_graph import Subtask, SubtaskOutcome, SubtaskStatus, SubtaskType, TaskGraph
from .workflow_policy import probe_runtime, workflow_policy_for_task


@contextmanager
def db_conn():
    conn = connect_db()
    try:
        yield conn
    finally:
        conn.close()


TASK_RESEARCH_TEMPLATE = "Understand current architecture and locate relevant files for: {task}"
TASK_SCOPE_TEMPLATE = "Identify the edit scope, entrypoints, and adjacent tests for: {task}"
TASK_EDIT_TEMPLATE = "Implement the smallest safe change for: {task}"
TASK_TEST_TEMPLATE = "Add or update focused tests and validation for: {task}"
TASK_CHECK_TEMPLATE = "Run and interpret the checks that prove: {task}"
TASK_LEARN_TEMPLATE = "Capture docs, memory, and follow-up lessons for: {task}"


def repo_root() -> Path:
    current = Path.cwd()
    while current != current.parent:
        if (current / ".git").exists() or (current / ".agent").exists():
            return current
        current = current.parent
    return Path.cwd()


def agent_root(root: Path | None = None) -> Path:
    return (root or repo_root()) / ".agent"


def task_graph_path(root: Path | None = None) -> Path:
    return agent_root(root) / "task-graph.json"


def task_markdown_path(root: Path | None = None) -> Path:
    return agent_root(root) / "task.md"


def task_context_path(root: Path | None = None) -> Path:
    return agent_root(root) / "context.md"


def task_handoff_path(root: Path | None = None) -> Path:
    return agent_root(root) / "handoff.md"


def subtask_dir(root: Path | None = None) -> Path:
    return agent_root(root) / "subtasks"


def _unique(items: list[str]) -> list[str]:
    return [item for item in dict.fromkeys(item for item in items if item)]


def _task_words(task: str) -> list[str]:
    return [word for word in re.split(r"\s+", task.strip()) if word]


def _explicit_paths(task: str) -> list[str]:
    pattern = r"(?<![A-Za-z0-9_])([~./A-Za-z0-9_-][A-Za-z0-9_./-]*\.[A-Za-z0-9]{1,8})"
    return _unique([match.group(1).strip() for match in re.finditer(pattern, task)])


def _is_tiny_task(task: str) -> bool:
    words = _task_words(task)
    lowered = task.lower()
    if len(words) <= 10 and _explicit_paths(task):
        return True
    if len(words) <= 8:
        return True
    tiny_markers = ("typo", "rename", "format", "read", "explain", "show", "list", "status")
    if len(words) <= 14 and any(marker in lowered for marker in tiny_markers):
        return True
    return False


def _infer_subtask_type(task: str, phase: str) -> SubtaskType:
    lowered = task.lower()
    if phase == "research":
        return SubtaskType.research
    if phase == "scope":
        return SubtaskType.research
    if phase == "edit":
        if any(marker in lowered for marker in ("refactor", "rewrite", "cleanup")):
            return SubtaskType.refactor if "refactor" in lowered else SubtaskType.cleanup
        if any(marker in lowered for marker in ("debug", "fix", "bug", "error", "fail")):
            return SubtaskType.debug
        return SubtaskType.edit
    if phase == "test":
        return SubtaskType.test
    if phase == "check":
        return SubtaskType.test
    return SubtaskType.docs


def _risk_level(task: str, phase: str) -> str:
    lowered = task.lower()
    if phase in {"edit", "check"} and any(marker in lowered for marker in ("migrate", "schema", "auth", "mcp", "cli", "deploy")):
        return "high"
    if any(marker in lowered for marker in ("refactor", "rewrite", "cleanup")):
        return "medium"
    return "low" if phase in {"research", "docs"} else "medium"


def _expected_files(task: str, profile: dict[str, Any]) -> list[str]:
    paths = _explicit_paths(task)
    if paths:
        return paths[:6]
    boosted = list(profile.get("boost_paths", []))
    important = list(profile.get("important_dirs", []))
    paths.extend(boosted[:3])
    paths.extend(important[:2])
    return _unique(paths)[:6]


def _missing_dependencies(graph: TaskGraph, subtask: Subtask) -> list[str]:
    return [dep for dep in subtask.depends_on if graph.get_subtask(dep) is None]


def _deps_satisfied(graph: TaskGraph, subtask: Subtask) -> bool:
    if _missing_dependencies(graph, subtask):
        return False
    return all((graph.get_subtask(dep) and graph.get_subtask(dep).status == SubtaskStatus.done) for dep in subtask.depends_on)


def _base_subtask_specs(task: str) -> list[dict[str, Any]]:
    return [
        {
            "phase": "research",
            "title": TASK_RESEARCH_TEMPLATE.format(task=task),
            "description": "Read the current implementation, file summaries, and adjacent entry points.",
            "retrieval_query": f"{task}\narchitecture current files entrypoints summaries",
            "success_check": "Relevant files and architecture are identified.",
        },
        {
            "phase": "scope",
            "title": TASK_SCOPE_TEMPLATE.format(task=task),
            "description": "Narrow the edit scope and confirm tests or configs that are likely coupled.",
            "retrieval_query": f"{task}\nedit scope tests configs dependencies",
            "success_check": "Edit scope and validation targets are clear.",
        },
        {
            "phase": "edit",
            "title": TASK_EDIT_TEMPLATE.format(task=task),
            "description": "Apply the smallest code change that satisfies the request.",
            "retrieval_query": f"{task}\nimplementation edit smallest change",
            "success_check": "The minimal change is implemented.",
        },
        {
            "phase": "test",
            "title": TASK_TEST_TEMPLATE.format(task=task),
            "description": "Add or update focused tests around the changed behavior.",
            "retrieval_query": f"{task}\ntests regression coverage focused checks",
            "success_check": "Targeted tests cover the change.",
        },
        {
            "phase": "check",
            "title": TASK_CHECK_TEMPLATE.format(task=task),
            "description": "Run the smallest useful checks and fix any failures.",
            "retrieval_query": f"{task}\nvalidation commands lint typecheck test failures",
            "success_check": "Checks pass or failing output is understood.",
        },
        {
            "phase": "learn",
            "title": TASK_LEARN_TEMPLATE.format(task=task),
            "description": "Record durable learnings, docs updates, and profile hints.",
            "retrieval_query": f"{task}\nlessons docs memory profile",
            "success_check": "Outcome and durable lessons are recorded.",
        },
    ]


def _decompose_task(task: str, max_subtasks: int, profile: dict[str, Any]) -> list[Subtask]:
    task = task.strip()
    specs = [_base_subtask_specs(task)[0]] if _is_tiny_task(task) else _base_subtask_specs(task)
    if "docs" not in task.lower() and len(specs) > 5 and max_subtasks < 5:
        specs = specs[:max_subtasks]
    if max_subtasks < len(specs):
        specs = specs[:max_subtasks]
    if _is_tiny_task(task):
        specs = [
            {
                "phase": "edit",
                "title": TASK_EDIT_TEMPLATE.format(task=task),
                "description": "Inspect the relevant code and make the smallest change.",
                "retrieval_query": f"{task}\nsmall focused files tests",
                "success_check": "The change is applied and verified.",
            }
        ]

    explicit_files = _expected_files(task, profile)
    subtasks: list[Subtask] = []
    for index, spec in enumerate(specs, start=1):
        subtask_id = f"T{index}"
        depends_on = [] if index == 1 else [f"T{index - 1}"]
        subtask_type = _infer_subtask_type(task, spec["phase"])
        status = SubtaskStatus.ready if index == 1 else SubtaskStatus.pending
        if _is_tiny_task(task):
            depends_on = []
        expected_files = list(explicit_files)
        if spec["phase"] in {"test", "check"}:
            expected_files = [path for path in explicit_files if any(marker in path for marker in ("test", "spec", "src", "system", "configs"))]
        subtasks.append(
            Subtask(
                id=subtask_id,
                title=spec["title"],
                description=spec["description"],
                type=subtask_type,
                status=status,
                depends_on=depends_on,
                retrieval_query=spec["retrieval_query"],
                expected_files=expected_files,
                success_check=spec["success_check"],
                risk_level=_risk_level(task, spec["phase"]),
            )
        )
    return subtasks


def load_task_graph(root: Path | None = None) -> TaskGraph | None:
    path = task_graph_path(root)
    if not path.exists():
        return None
    return TaskGraph.from_dict(json.loads(path.read_text()))


def _task_graph_markdown(graph: TaskGraph) -> str:
    lines = [
        "# Current Task",
        "",
        "## Task",
        graph.task,
        "",
        "## Progress",
    ]
    for subtask in graph.subtasks:
        marker = "x" if subtask.status == SubtaskStatus.done else " "
        current = " <- current" if graph.current_subtask_id == subtask.id else ""
        lines.append(f"- [{marker}] {subtask.id} {subtask.title} ({subtask.status.value}){current}")
    lines.extend(
        [
            "",
            "## Constraints",
            "- Keep changes minimal.",
            "- Prefer existing project patterns.",
            "- Do not rewrite unrelated code.",
            "- Run checks before final response.",
            "",
            "## Current Subtask",
            graph.current_subtask_id or "-",
            "",
            "## Notes",
            graph.summary or "- none",
        ]
    )
    return "\n".join(lines).strip() + "\n"


def _subtask_markdown(graph: TaskGraph, subtask: Subtask) -> str:
    lines = [
        f"# {subtask.id}: {subtask.title}",
        "",
        "## Description",
        subtask.description,
        "",
        "## Type",
        subtask.type.value,
        "",
        "## Status",
        subtask.status.value,
        "",
        "## Retrieval Query",
        f"`{subtask.retrieval_query}`",
        "",
        "## Expected Files",
        *(f"- {path}" for path in (subtask.expected_files or ["- none"])),
        "",
        "## Success Check",
        subtask.success_check,
        "",
        "## Depends On",
        ", ".join(subtask.depends_on) if subtask.depends_on else "-",
        "",
        "## Graph Task",
        graph.task,
    ]
    return "\n".join(lines).strip() + "\n"


def _write_runtime_files(graph: TaskGraph, root: Path | None = None) -> None:
    root = root or repo_root()
    agent_root(root).mkdir(parents=True, exist_ok=True)
    subtask_dir(root).mkdir(parents=True, exist_ok=True)
    task_graph_path(root).write_text(json.dumps(graph.to_dict(), indent=2, sort_keys=True) + "\n")
    expected_names = {f"{subtask.id}.md" for subtask in graph.subtasks}
    for existing in subtask_dir(root).glob("*.md"):
        if existing.name not in expected_names:
            existing.unlink()
    task_markdown_path(root).write_text(_task_graph_markdown(graph))
    for subtask in graph.subtasks:
        (subtask_dir(root) / f"{subtask.id}.md").write_text(_subtask_markdown(graph, subtask))
    current = graph.active_subtask()
    context_lines = [
        "# Context",
        "",
        f"Task: {graph.task}",
        f"Graph: {graph.task_id}",
        f"Current subtask: {current.id if current else '-'}",
        f"Next tool: {'rag_next_subtask' if current else 'rag_task_status'}",
    ]
    task_context_path(root).write_text("\n".join(context_lines) + "\n")
    handoff_lines = [
        "# Handoff",
        "",
        f"Task: {graph.task}",
        f"Graph: {graph.task_id}",
        f"Current subtask: {current.id if current else '-'}",
        f"Current status: {current.status.value if current else 'idle'}",
    ]
    task_handoff_path(root).write_text("\n".join(handoff_lines) + "\n")


def _append_outcome_jsonl(root: Path, payload: dict[str, Any]) -> None:
    out_path = agent_root(root) / "outcomes.jsonl"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    redacted = redact_sensitive_text(json.dumps(payload, sort_keys=True))
    with out_path.open("a", encoding="utf-8") as handle:
        handle.write(redacted + "\n")


def _outcome_scoring(retrieved_files: list[str], edited_files: list[str], checks_run: list[str], passed: bool) -> dict[str, Any]:
    retrieved = _unique(retrieved_files)
    edited = _unique(edited_files)
    edited_count = len(edited)
    retrieved_count = len(retrieved)
    checks_count = len(_unique(checks_run))
    hits = sum(1 for path in edited if path in set(retrieved))
    missed_file_count = max(0, edited_count - hits)
    return {
        "retrieval_hit_rate": round((hits / edited_count), 4) if edited_count else 1.0,
        "missed_file_count": missed_file_count,
        "retrieved_file_count": retrieved_count,
        "edited_file_count": edited_count,
        "checks_count": checks_count,
        "passed": bool(passed),
    }


def plan_task(task: str, repo: str | None = None, max_subtasks: int = 8) -> TaskGraph:
    with db_conn() as conn:
        resolved_repo = infer_repo_filter(conn, repo)
        run_id = str(uuid.uuid4())
    root = repo_root()
    profile = profile_show(root)
    bounded_max_subtasks = max(1, min(int(max_subtasks), 8))
    graph = TaskGraph(
        task_id=f"task-{uuid.uuid4().hex[:12]}",
        task=redact_sensitive_text(task).strip(),
        repo=resolved_repo,
        mode="auto",
        max_subtasks=bounded_max_subtasks,
        subtasks=_decompose_task(task, bounded_max_subtasks, profile),
    )
    graph.current_subtask_id = graph.subtasks[0].id if graph.subtasks else None
    now = time.time()
    graph.created_at = now
    graph.updated_at = now
    if graph.subtasks:
        graph.subtasks[0].status = SubtaskStatus.ready
        graph.subtasks[0].updated_at = now
    _write_runtime_files(graph, root)
    graph.run_id = run_id
    with db_conn() as conn:
        record_task_run(
            conn,
            run_id=run_id,
            repo=resolved_repo,
            task=graph.task,
            graph=graph.to_dict(),
            mode=graph.mode,
            max_subtasks=graph.max_subtasks,
            status="active",
            current_subtask_id=graph.current_subtask_id,
        )
    _write_runtime_files(graph, root)
    write_task_run_export(root, {"run_id": run_id, "task_id": graph.task_id, "task": graph.task, "repo": resolved_repo, "graph": graph.to_dict(), "action": "plan"})
    return graph


def _refresh_blocking(graph: TaskGraph) -> None:
    done_ids = {subtask.id for subtask in graph.subtasks if subtask.status == SubtaskStatus.done}
    for subtask in graph.subtasks:
        missing = _missing_dependencies(graph, subtask)
        if missing and subtask.status not in {SubtaskStatus.done, SubtaskStatus.failed, SubtaskStatus.skipped}:
            subtask.status = SubtaskStatus.blocked
            subtask.last_error = f"missing dependencies: {', '.join(missing)}"
            continue
        if subtask.status in {SubtaskStatus.pending, SubtaskStatus.ready}:
            if _deps_satisfied(graph, subtask):
                subtask.status = SubtaskStatus.ready
        if subtask.status == SubtaskStatus.pending and any(dep not in done_ids for dep in subtask.depends_on):
            subtask.status = SubtaskStatus.blocked
        if subtask.status == SubtaskStatus.blocked and _deps_satisfied(graph, subtask):
            subtask.status = SubtaskStatus.ready
            subtask.last_error = None


def next_subtask(task_graph: TaskGraph | None = None) -> Subtask | None:
    graph = task_graph or load_task_graph()
    if graph is None:
        return None
    _refresh_blocking(graph)
    for subtask in graph.subtasks:
        if subtask.status == SubtaskStatus.ready and _deps_satisfied(graph, subtask):
            graph.current_subtask_id = subtask.id
            graph.updated_at = time.time()
            _write_runtime_files(graph)
            if graph.run_id:
                with db_conn() as conn:
                    update_task_run_status(conn, graph.run_id, "active", current_subtask_id=subtask.id)
            return subtask
    for subtask in graph.subtasks:
        if subtask.status == SubtaskStatus.failed and subtask.attempts < 3:
            if _deps_satisfied(graph, subtask):
                subtask.status = SubtaskStatus.ready
                subtask.updated_at = time.time()
                graph.current_subtask_id = subtask.id
                graph.updated_at = time.time()
                _write_runtime_files(graph)
                if graph.run_id:
                    with db_conn() as conn:
                        update_task_run_status(conn, graph.run_id, "active", current_subtask_id=subtask.id)
                return subtask
    return None


def mark_subtask_running(task_graph: TaskGraph, subtask_id: str) -> TaskGraph:
    subtask = task_graph.get_subtask(subtask_id)
    if subtask is None:
        raise ValueError(f"Unknown subtask: {subtask_id}")
    subtask.status = SubtaskStatus.running
    subtask.attempts += 1
    subtask.updated_at = time.time()
    task_graph.current_subtask_id = subtask_id
    task_graph.updated_at = time.time()
    _write_runtime_files(task_graph)
    if task_graph.run_id:
        with db_conn() as conn:
            update_task_subtask_status(conn, task_graph.run_id, subtask_id, SubtaskStatus.running.value, current_subtask_id=subtask_id)
    return task_graph


def mark_subtask_done(
    task_graph: TaskGraph,
    subtask_id: str,
    *,
    retrieved_files: list[str] | None = None,
    edited_files: list[str] | None = None,
    checks_run: list[str] | None = None,
    passed: bool = True,
    notes: str | None = None,
    run_id: str | None = None,
) -> TaskGraph:
    if not passed:
        raise ValueError("passed=false should use rag_subtask_failed")
    subtask = task_graph.get_subtask(subtask_id)
    if subtask is None:
        raise ValueError(f"Unknown subtask: {subtask_id}")
    subtask.status = SubtaskStatus.done
    subtask.updated_at = time.time()
    task_graph.current_subtask_id = subtask_id
    task_graph.updated_at = time.time()
    with db_conn() as conn:
        outcome = record_task_outcome(
            conn,
            repo=task_graph.repo,
            task_id=task_graph.task_id,
            task=task_graph.task,
            subtask_id=subtask_id,
            subtask_title=subtask.title,
            subtask_type=subtask.type.value,
            status=SubtaskStatus.done.value,
            retrieved_files=retrieved_files or [],
            edited_files=edited_files or [],
            missed_files=[path for path in (edited_files or []) if path not in set(retrieved_files or [])],
            useless_files=[],
            checks_run=checks_run or [],
            passed=passed,
            notes=notes,
            run_id=run_id or task_graph.run_id,
            attempt=subtask.attempts,
        )
    score = _outcome_scoring(retrieved_files or [], edited_files or [], checks_run or [], passed)
    task_graph.summary = f"Completed {subtask_id}: {subtask.title}"
    _refresh_blocking(task_graph)
    next_ready = None
    for candidate in task_graph.subtasks:
        if candidate.status == SubtaskStatus.ready and _deps_satisfied(task_graph, candidate):
            next_ready = candidate.id
            break
    task_graph.current_subtask_id = next_ready
    _write_runtime_files(task_graph)
    if task_graph.run_id:
        with db_conn() as conn:
            update_task_subtask_status(conn, task_graph.run_id, subtask_id, SubtaskStatus.done.value, current_subtask_id=next_ready)
            if all(item.status == SubtaskStatus.done for item in task_graph.subtasks):
                update_task_run_status(conn, task_graph.run_id, "complete", current_subtask_id=next_ready, finished_at=time.time())
            else:
                update_task_run_status(conn, task_graph.run_id, "active", current_subtask_id=next_ready)
    _append_outcome_jsonl(
        repo_root(),
        {
            "task_id": task_graph.task_id,
            "task": task_graph.task,
            "subtask_id": subtask_id,
            "status": "done",
            "passed": passed,
            "retrieved_files": retrieved_files or [],
            "edited_files": edited_files or [],
            "checks_run": checks_run or [],
            "notes": notes,
            "score": score,
            "outcome_id": outcome.get("outcome_id"),
        },
    )
    return task_graph


def mark_subtask_failed(
    task_graph: TaskGraph,
    subtask_id: str,
    *,
    retrieved_files: list[str] | None = None,
    edited_files: list[str] | None = None,
    checks_run: list[str] | None = None,
    notes: str | None = None,
    run_id: str | None = None,
) -> TaskGraph:
    subtask = task_graph.get_subtask(subtask_id)
    if subtask is None:
        raise ValueError(f"Unknown subtask: {subtask_id}")
    subtask.status = SubtaskStatus.failed
    subtask.last_error = redact_sensitive_text(notes or "subtask failed")
    subtask.updated_at = time.time()
    task_graph.current_subtask_id = subtask_id
    task_graph.updated_at = time.time()
    with db_conn() as conn:
        outcome = record_task_outcome(
            conn,
            repo=task_graph.repo,
            task_id=task_graph.task_id,
            task=task_graph.task,
            subtask_id=subtask_id,
            subtask_title=subtask.title,
            subtask_type=subtask.type.value,
            status=SubtaskStatus.failed.value,
            retrieved_files=retrieved_files or [],
            edited_files=edited_files or [],
            missed_files=[path for path in (edited_files or []) if path not in set(retrieved_files or [])],
            useless_files=[],
            checks_run=checks_run or [],
            passed=False,
            notes=notes,
            run_id=run_id or task_graph.run_id,
            attempt=subtask.attempts,
        )
    score = _outcome_scoring(retrieved_files or [], edited_files or [], checks_run or [], False)
    _refresh_blocking(task_graph)
    next_ready = None
    for candidate in task_graph.subtasks:
        if candidate.status == SubtaskStatus.ready and _deps_satisfied(task_graph, candidate):
            next_ready = candidate.id
            break
    retryable = subtask.attempts < 3 and _deps_satisfied(task_graph, subtask)
    task_graph.current_subtask_id = subtask_id if retryable else next_ready
    if task_graph.run_id:
        with db_conn() as conn:
            update_task_subtask_status(conn, task_graph.run_id, subtask_id, SubtaskStatus.failed.value, current_subtask_id=task_graph.current_subtask_id)
    _append_outcome_jsonl(
        repo_root(),
        {
            "task_id": task_graph.task_id,
            "task": task_graph.task,
            "subtask_id": subtask_id,
            "status": "failed",
            "retrieved_files": retrieved_files or [],
            "edited_files": edited_files or [],
            "checks_run": checks_run or [],
            "notes": notes,
            "score": score,
            "outcome_id": outcome.get("outcome_id"),
        },
    )
    _write_runtime_files(task_graph)
    return task_graph


def compact_completed_subtasks(task_graph: TaskGraph | None = None) -> TaskGraph | None:
    graph = task_graph or load_task_graph()
    if graph is None:
        return None
    done = graph.done_subtasks()
    if done:
        graph.summary = "\n".join(f"- {subtask.id}: {subtask.title}" for subtask in done)
    graph.updated_at = time.time()
    _write_runtime_files(graph)
    return graph


def task_graph_status(task_graph: TaskGraph | None = None) -> dict[str, Any]:
    graph = task_graph or load_task_graph()
    if graph is None:
        return {"active": False, "task": None, "subtasks": [], "counts": {}}
    _refresh_blocking(graph)
    counts = {
        "total": len(graph.subtasks),
        "done": sum(1 for subtask in graph.subtasks if subtask.status == SubtaskStatus.done),
        "running": sum(1 for subtask in graph.subtasks if subtask.status == SubtaskStatus.running),
        "ready": sum(1 for subtask in graph.subtasks if subtask.status == SubtaskStatus.ready),
        "blocked": sum(1 for subtask in graph.subtasks if subtask.status == SubtaskStatus.blocked),
        "failed": sum(1 for subtask in graph.subtasks if subtask.status == SubtaskStatus.failed),
        "pending": sum(1 for subtask in graph.subtasks if subtask.status == SubtaskStatus.pending),
    }
    next_item = None
    for subtask in graph.subtasks:
        if subtask.status == SubtaskStatus.ready and _deps_satisfied(graph, subtask):
            next_item = subtask
            break
    return {
        "active": True,
        "task_id": graph.task_id,
        "task": graph.task,
        "repo": graph.repo,
        "mode": graph.mode,
        "current_subtask_id": graph.current_subtask_id,
        "next_subtask": next_item.to_dict() if next_item else None,
        "subtasks": [subtask.to_dict() for subtask in graph.subtasks],
        "counts": counts,
        "summary": graph.summary,
    }


def _build_retrieval_context(task_text: str, repo: str | None, *, mode: str = "agent") -> dict[str, Any]:
    with db_conn() as conn:
        resolved_repo = infer_repo_filter(conn, repo)
        config = load_config()
        effective_config = get_mode_profile(config, mode)
        effective_config = json.loads(json.dumps(effective_config))
        # Reuse the runtime ranking hints already embedded in runtime_config by agent_support.
        from .agent_support import runtime_config  # local import to avoid a cycle

        effective_config = runtime_config(effective_config, conn, resolved_repo, task_text)
        result = retrieve(
            conn,
            get_qdrant(effective_config),
            effective_config,
            task_text,
            resolved_repo,
            reranker_enabled(effective_config, None),
            mode=mode,
        )
        context, files = gather_context(
            result.rows,
            effective_config,
            facts=result.facts,
            summaries=result.summaries,
            context_sources=result.context_sources,
            memory=result.memory["summary"] if result.memory else None,
        )
        return {
            "repo": resolved_repo,
            "config": effective_config,
            "result": result,
            "context": context,
            "files": files,
            "edit_scope": build_edit_scope(conn, resolved_repo, result.rows, result.summaries, task_text, effective_config.get("repo_profile")),
            "missing_context": missing_context_payload(result, files),
            "commands": command_plan_for_subtask(repo_root(), Subtask(
                id="preview",
                title=task_text,
                description=task_text,
                type=SubtaskType.research,
                status=SubtaskStatus.ready,
            ), files, effective_config.get("repo_profile")),
        }


def subtask_context(task_graph: TaskGraph | None, subtask_id: str, *, output_format: str = "compact") -> dict[str, Any]:
    graph = task_graph or load_task_graph()
    if graph is None:
        raise ValueError("No task graph available")
    subtask = graph.get_subtask(subtask_id)
    if subtask is None:
        raise ValueError(f"Unknown subtask: {subtask_id}")
    if subtask.status == SubtaskStatus.ready:
        mark_subtask_running(graph, subtask.id)
        subtask = graph.get_subtask(subtask.id) or subtask
    policy = workflow_policy_for_task(graph.task, runtime=probe_runtime())
    retrieval_mode = policy.retrieval_mode if subtask.type == SubtaskType.research else "agent"
    payload = _build_retrieval_context(subtask.retrieval_query or subtask.title, graph.repo, mode=retrieval_mode)
    root = repo_root()
    selected_files = payload["files"]
    commands = command_plan_for_subtask(root, subtask, selected_files, payload["config"].get("repo_profile"))
    run_id = f"{graph.task_id}-{subtask.id}-{uuid.uuid4().hex[:8]}"
    with db_conn() as conn:
        record_task_run(
            conn,
            run_id=run_id,
            repo=graph.repo,
            task=redact_sensitive_text(graph.task),
            graph=graph.to_dict(),
            mode="agent",
            max_subtasks=graph.max_subtasks,
            status="context",
            current_subtask_id=subtask.id,
        )
    write_task_run_export(
        root,
        {
            "run_id": run_id,
            "task_id": graph.task_id,
            "subtask_id": subtask.id,
            "task": graph.task,
            "repo": graph.repo,
            "context": {
                "task": subtask.title,
                "edit_scope": payload["edit_scope"],
                "evidence": payload["files"],
                "missing_context": payload["missing_context"],
                "suggested_commands": commands,
            },
        },
    )
    _write_runtime_files(graph)
    response = {
        "task": graph.task,
        "task_id": graph.task_id,
        "subtask": subtask.to_dict(),
        "edit_scope": payload["edit_scope"],
        "evidence": payload["files"],
        "missing_context": payload["missing_context"],
        "suggested_commands": commands,
        "grounding_rules": [
            "Stay inside edit scope unless direct inspection proves otherwise.",
            "Do not claim checks passed unless command output confirms it.",
        ],
        "next_mcp_tool": "rag_subtask_done",
        "must_inspect_first": payload["files"][:6],
        "current_subtask_id": subtask.id,
        "ready_to_edit": bool(payload["edit_scope"].get("likely_edit")),
        "run_id": run_id,
        "policy": policy.to_dict(),
    }
    if output_format == "full":
        response["context"] = payload["context"]
    return response


def reflect_run(task_graph: TaskGraph | None = None) -> dict[str, Any]:
    graph = task_graph or load_task_graph()
    if graph is None:
        return {"active": False, "summary": "No task graph."}
    with db_conn() as conn:
        if graph.run_id:
            outcomes = list_task_outcomes_for_run(conn, graph.run_id, limit=50)
        else:
            outcomes = list_task_outcomes_for_task(conn, graph.task_id, limit=50)
    failed = [row for row in outcomes if row["passed"] == 0]
    missed = _unique([path for row in outcomes for path in json.loads(row["missed_files_json"] or "[]")])
    useful = _unique([path for row in outcomes for path in json.loads(row["edited_files_json"] or "[]")])
    return {
        "active": True,
        "task_id": graph.task_id,
        "task": graph.task,
        "completed_subtasks": [subtask.id for subtask in graph.done_subtasks()],
        "failed_subtasks": [subtask.id for subtask in graph.subtasks if subtask.status == SubtaskStatus.failed],
        "missed_files": missed,
        "useful_files": useful,
        "failure_count": len(failed),
        "summary": graph.summary or "No summary recorded.",
    }


def learn_from_task_outcome(run_id: str | None = None, root: Path | None = None) -> dict[str, Any]:
    root = root or repo_root()
    with db_conn() as conn:
        row = get_task_run(conn, run_id) if run_id else None
        if row is None:
            row = latest_task_run(conn, infer_repo_filter(conn, None))
        if row is None:
            raise ValueError("No task run available to learn from")
        payload = task_run_payload(row)
    with db_conn() as conn:
        if payload.get("run_id"):
            outcomes = list_task_outcomes_for_run(conn, payload["run_id"], limit=20)
        elif payload.get("task_id"):
            outcomes = list_task_outcomes_for_task(conn, payload["task_id"], limit=20)
        else:
            outcomes = list_task_outcomes(conn, payload.get("repo"), limit=20)
        aggregate_outcome = {
            "edited_files": _unique([path for row in outcomes for path in json.loads(row["edited_files_json"] or "[]")]),
            "retrieved_files": _unique([path for row in outcomes for path in json.loads(row["retrieved_files_json"] or "[]")]),
            "missed_files": _unique([path for row in outcomes for path in json.loads(row["missed_files_json"] or "[]")]),
            "checks_run": _unique([path for row in outcomes for path in json.loads(row["checks_run_json"] or "[]")]),
            "passed": all(bool(row["passed"]) for row in outcomes) if outcomes else False,
        }
        learning_payload = {**payload, "outcome": aggregate_outcome}
    path, profile = learn_profile_from_run(learning_payload, root)
    with db_conn() as conn:
        task_lessons: list[dict[str, Any]] = []
        for outcome in outcomes:
            lesson = {
                "task_id": payload.get("task_id"),
                "subtask_id": outcome["subtask_id"],
                "lesson_kind": "file-pattern",
                "retrieved_files": json.loads(outcome["retrieved_files_json"] or "[]"),
                "edited_files": json.loads(outcome["edited_files_json"] or "[]"),
                "missed_files": json.loads(outcome["missed_files_json"] or "[]"),
                "checks_run": json.loads(outcome["checks_run_json"] or "[]"),
                "passed": bool(outcome["passed"]),
            }
            record_task_lesson(
                conn,
                repo=payload.get("repo"),
                run_id=payload.get("run_id"),
                task_id=payload.get("task_id") or payload.get("run_id"),
                lesson_kind="file-pattern",
                lesson=lesson,
            )
            task_lessons.append(lesson)

    memory_path = root / ".agent" / "memory.md"
    memory_path.parent.mkdir(parents=True, exist_ok=True)
    existing = memory_path.read_text() if memory_path.exists() else "# Project Memory\n\n"
    summary_lines = [
        "## Learned from run",
        f"- run: {payload.get('run_id')}",
        f"- task: {payload.get('task')}",
        f"- edited files: {', '.join(_unique([path for lesson in task_lessons for path in lesson['edited_files']])) or '-'}",
        f"- missed files: {', '.join(_unique([path for lesson in task_lessons for path in lesson['missed_files']])) or '-'}",
    ]
    memory_path.write_text(existing.rstrip() + "\n\n" + "\n".join(summary_lines) + "\n")
    return {
        "path": str(path),
        "profile": profile,
        "run_id": payload["run_id"],
        "task_id": payload.get("task_id"),
        "task_lessons": task_lessons,
        "memory_path": str(memory_path),
    }


def task_step(task: str | None = None) -> dict[str, Any]:
    policy = workflow_policy_for_task(task or "", runtime=probe_runtime()) if task else None
    def _router(
        state: str,
        next_tool: str,
        reason: str,
        *,
        task_id: str | None,
        current_subtask_id: str | None,
        subtask: dict[str, Any] | None,
        recommended_call: dict[str, Any],
    ) -> dict[str, Any]:
        return {
            "state": state,
            "next_tool": next_tool,
            "reason": reason,
            "task_id": task_id,
            "current_subtask_id": current_subtask_id,
            "subtask": subtask,
            "policy": policy.to_dict() if policy else None,
            "recommended_call": recommended_call,
        }

    graph = load_task_graph()
    if graph is None:
        return _router(
            "needs_plan",
            "rag_plan_task",
            "No active task graph. Plan the task first.",
            task_id=None,
            current_subtask_id=None,
            subtask=None,
            recommended_call={"tool": "rag_plan_task", "arguments": {"task": task} if task else {}},
        )
    policy = workflow_policy_for_task(graph.task, runtime=probe_runtime())
    _refresh_blocking(graph)
    if all(item.status == SubtaskStatus.done for item in graph.subtasks):
        return _router(
            "complete",
            "rag_learn_from_outcome",
            "Task graph complete.",
            task_id=graph.task_id,
            current_subtask_id=graph.current_subtask_id,
            subtask=None,
            recommended_call={"tool": "rag_learn_from_outcome", "arguments": {"run_id": graph.run_id} if graph.run_id else {}},
        )
    active = graph.active_subtask()
    if active and active.status == SubtaskStatus.running:
        return _router(
            "ready_for_work",
            "rag_subtask_done",
            "Subtask is running. Complete it or mark it failed.",
            task_id=graph.task_id,
            current_subtask_id=active.id,
            subtask=active.to_dict(),
            recommended_call={
                "tool": "rag_subtask_done",
                "arguments": {
                    "subtask_id": active.id,
                    "retrieved_files": [],
                    "edited_files": [],
                    "checks_run": [],
                    "notes": "",
                },
            },
        )
    ready = next((s for s in graph.subtasks if s.status == SubtaskStatus.ready and _deps_satisfied(graph, s)), None)
    if ready:
        return _router(
            "needs_context",
            "rag_subtask_context",
            "Subtask is ready. Fetch compact context before editing.",
            task_id=graph.task_id,
            current_subtask_id=ready.id,
            subtask=ready.to_dict(),
            recommended_call={"tool": "rag_subtask_context", "arguments": {"subtask_id": ready.id, "format": "compact"}},
        )
    retryable = next((s for s in graph.subtasks if s.status == SubtaskStatus.failed and s.attempts < 3 and _deps_satisfied(graph, s)), None)
    if retryable:
        return _router(
            "needs_context",
            "rag_subtask_context",
            "Retryable failed subtask is available. Rebuild compact context.",
            task_id=graph.task_id,
            current_subtask_id=retryable.id,
            subtask=retryable.to_dict(),
            recommended_call={"tool": "rag_subtask_context", "arguments": {"subtask_id": retryable.id, "format": "compact"}},
        )
    has_terminal_failures = any(
        s.status == SubtaskStatus.failed and (s.attempts >= 3 or not _deps_satisfied(graph, s))
        for s in graph.subtasks
    )
    if has_terminal_failures:
        return _router(
            "failed",
            "rag_reflect_run",
            "Task has failed subtasks with no retries left.",
            task_id=graph.task_id,
            current_subtask_id=graph.current_subtask_id,
            subtask=None,
            recommended_call={"tool": "rag_reflect_run", "arguments": {}},
        )
    return _router(
        "blocked",
        "rag_task_status",
        "No runnable subtasks. Inspect task status.",
        task_id=graph.task_id,
        current_subtask_id=graph.current_subtask_id,
        subtask=None,
        recommended_call={"tool": "rag_task_status", "arguments": {}},
    )


def task_continue(task: str | None = None) -> dict[str, Any]:
    step = task_step(task)
    response: dict[str, Any] = {"step": step, "context": {}, "next_action": "call_tool"}
    if step.get("state") == "needs_context":
        subtask_id = (step.get("recommended_call", {}).get("arguments", {}) or {}).get("subtask_id")
        graph = load_task_graph()
        if graph is not None and subtask_id:
            response["context"] = subtask_context(graph, subtask_id, output_format="compact")
            response["next_action"] = "edit"
        return response
    if step.get("state") in {"complete", "failed", "blocked"}:
        response["next_action"] = "stop" if step["state"] in {"complete", "failed"} else "call_tool"
    return response


def reset_task(root: Path | None = None) -> dict[str, Any]:
    root = root or repo_root()
    agent = agent_root(root)
    archive = agent / "archive" / time.strftime("%Y%m%d-%H%M%S")
    to_archive = [
        task_graph_path(root),
        task_markdown_path(root),
        task_context_path(root),
        task_handoff_path(root),
    ]
    archived: list[str] = []
    for path in to_archive:
        if path.exists():
            archive.mkdir(parents=True, exist_ok=True)
            target = archive / path.name
            target.write_text(path.read_text())
            path.unlink()
            archived.append(str(path.relative_to(root)))
    subtasks_path = subtask_dir(root)
    if subtasks_path.exists():
        archive_subtasks = archive / "subtasks"
        archive_subtasks.mkdir(parents=True, exist_ok=True)
        for md in subtasks_path.glob("*.md"):
            target = archive_subtasks / md.name
            target.write_text(md.read_text())
            md.unlink()
            archived.append(str(md.relative_to(root)))
        try:
            subtasks_path.rmdir()
        except OSError:
            pass
    return {
        "ok": True,
        "archived": archived,
        "archive_dir": str(archive.relative_to(root)) if archived else None,
        "preserved": [".agent/memory.md"],
        "message": "Task files reset. .agent/memory.md was preserved.",
    }
