from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .state import redact_sensitive_text


def agent_runtime_root(root: Path) -> Path:
    return root / ".agent"


def task_run_dir(root: Path) -> Path:
    return agent_runtime_root(root) / "rag-runs"


def task_run_path(root: Path, run_id: str) -> Path:
    return task_run_dir(root) / f"{run_id}.json"


def write_task_run_export(root: Path, payload: dict[str, Any]) -> Path:
    task_run_dir(root).mkdir(parents=True, exist_ok=True)
    path = task_run_path(root, str(payload["run_id"]))
    redacted = json.loads(redact_sensitive_text(json.dumps(payload, sort_keys=True)))
    with path.open("w", encoding="utf-8") as handle:
        json.dump(redacted, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return path


def load_task_run_export(root: Path, run_id: str) -> dict[str, Any] | None:
    path = task_run_path(root, run_id)
    if not path.exists():
        return None
    return json.loads(path.read_text())


def list_task_run_exports(root: Path) -> list[Path]:
    run_dir = task_run_dir(root)
    if not run_dir.is_dir():
        return []
    return sorted(run_dir.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True)
