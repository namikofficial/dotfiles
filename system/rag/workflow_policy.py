from __future__ import annotations

import re
import subprocess
import time
from dataclasses import dataclass, asdict
from typing import Any


@dataclass(frozen=True)
class WorkflowPolicy:
    use_task_graph: bool
    max_subtasks: int
    retrieval_mode: str
    context_format: str
    run_checks_each_subtask: bool
    collect_context_now: bool
    reasons: list[str]

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def _words(task: str) -> list[str]:
    return [token for token in re.split(r"\s+", task.strip()) if token]


def _looks_tiny(task: str) -> bool:
    words = _words(task)
    lowered = task.lower()
    if len(words) <= 8:
        return True
    if len(words) <= 12 and any(marker in lowered for marker in ("typo", "rename", "format", "docs", "read", "show")):
        return True
    return False


def _looks_large(task: str) -> bool:
    lowered = task.lower()
    return any(marker in lowered for marker in ("refactor", "rewrite", "migration", "architecture", "across", "multiple"))


def _looks_debug(task: str) -> bool:
    lowered = task.lower()
    return any(marker in lowered for marker in ("fix", "bug", "error", "failing", "regression", "crash"))


def probe_runtime() -> dict[str, bool]:
    # Keep this intentionally lightweight and robust to environments where local-ai-runtime is absent.
    runtime: dict[str, bool] = {"qdrant_ready": False, "llm_ready": False}
    checks = [
        ("qdrant_ready", ["local-ai-runtime", "ensure-qdrant"]),
        ("llm_ready", ["local-ai-runtime", "ensure-llm"]),
    ]
    for key, cmd in checks:
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=6)
            runtime[key] = proc.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            runtime[key] = False
    return runtime


_RUNTIME_PROBE_CACHE: dict[str, Any] = {"ts": 0.0, "value": None}


def cached_probe_runtime(ttl_seconds: float = 15.0) -> dict[str, bool]:
    now = time.time()
    cached = _RUNTIME_PROBE_CACHE.get("value")
    if isinstance(cached, dict) and (now - float(_RUNTIME_PROBE_CACHE.get("ts", 0.0))) < ttl_seconds:
        return dict(cached)
    value = probe_runtime()
    _RUNTIME_PROBE_CACHE["ts"] = now
    _RUNTIME_PROBE_CACHE["value"] = dict(value)
    return dict(value)


def workflow_policy_for_task(task: str, *, runtime: dict[str, bool] | None = None) -> WorkflowPolicy:
    runtime = runtime or {"qdrant_ready": True, "llm_ready": True}
    reasons: list[str] = []

    if _looks_tiny(task):
        reasons.append("tiny_task_detected")
        return WorkflowPolicy(
            use_task_graph=False,
            max_subtasks=1,
            retrieval_mode="quick",
            context_format="compact",
            run_checks_each_subtask=False,
            collect_context_now=runtime.get("qdrant_ready", False),
            reasons=reasons,
        )

    max_subtasks = 5
    retrieval_mode = "agent"
    run_checks_each_subtask = True
    if _looks_debug(task):
        reasons.append("debug_task_detected")
        max_subtasks = 4
        retrieval_mode = "deep"
    if _looks_large(task):
        reasons.append("large_task_detected")
        max_subtasks = 8
        retrieval_mode = "agent"

    if not runtime.get("qdrant_ready", False):
        reasons.append("qdrant_not_ready")
    if not runtime.get("llm_ready", False):
        reasons.append("llm_not_ready")
    collect_context_now = runtime.get("qdrant_ready", False) and runtime.get("llm_ready", False)

    return WorkflowPolicy(
        use_task_graph=True,
        max_subtasks=max_subtasks,
        retrieval_mode=retrieval_mode,
        context_format="compact",
        run_checks_each_subtask=run_checks_each_subtask,
        collect_context_now=collect_context_now,
        reasons=reasons,
    )
