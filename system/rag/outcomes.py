from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from .run_trace import write_task_run_export
from .state import record_task_outcome
from .task_graph import SubtaskOutcome


def record_subtask_outcome(
    conn,
    *,
    repo: str | None,
    task_id: str,
    task: str,
    outcome: SubtaskOutcome,
    run_id: str | None = None,
    export_root: Path | None = None,
) -> dict[str, Any]:
    payload = record_task_outcome(
        conn,
        repo=repo,
        task_id=task_id,
        task=task,
        subtask_id=outcome.subtask_id,
        status=outcome.status.value,
        retrieved_files=outcome.retrieved_files,
        edited_files=outcome.edited_files,
        missed_files=outcome.missed_files,
        useless_files=outcome.useless_files,
        checks_run=outcome.checks_run,
        passed=outcome.passed,
        notes=outcome.notes,
        run_id=run_id or outcome.run_id,
        attempt=outcome.attempt,
    )
    if export_root is not None:
        write_task_run_export(
            export_root,
            {
                "run_id": run_id or outcome.run_id or f"task-run-{int(time.time())}",
                "task_id": task_id,
                "task": task,
                "repo": repo,
                "outcome": outcome.to_dict(),
                "record": payload,
            },
        )
    return payload


def summarize_outcome(outcome: SubtaskOutcome) -> str:
    parts = [
        f"subtask={outcome.subtask_id}",
        f"status={outcome.status.value}",
        f"passed={'yes' if outcome.passed else 'no'}",
    ]
    if outcome.edited_files:
        parts.append(f"edited={len(outcome.edited_files)}")
    if outcome.missed_files:
        parts.append(f"missed={len(outcome.missed_files)}")
    return ", ".join(parts)


def outcome_jsonl_line(payload: dict[str, Any]) -> str:
    return json.dumps(payload, sort_keys=True)

