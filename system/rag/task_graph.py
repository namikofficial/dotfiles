from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any


class _StrEnum(str, Enum):
    def __str__(self) -> str:  # pragma: no cover - trivial
        return str(self.value)


class SubtaskStatus(_StrEnum):
    pending = "pending"
    ready = "ready"
    running = "running"
    blocked = "blocked"
    done = "done"
    failed = "failed"
    skipped = "skipped"


class SubtaskType(_StrEnum):
    research = "research"
    edit = "edit"
    test = "test"
    docs = "docs"
    refactor = "refactor"
    debug = "debug"
    cleanup = "cleanup"


@dataclass
class SubtaskOutcome:
    subtask_id: str
    status: SubtaskStatus
    retrieved_files: list[str] = field(default_factory=list)
    edited_files: list[str] = field(default_factory=list)
    missed_files: list[str] = field(default_factory=list)
    useless_files: list[str] = field(default_factory=list)
    checks_run: list[str] = field(default_factory=list)
    passed: bool = False
    notes: str | None = None
    run_id: str | None = None
    attempt: int = 0
    created_at: float = field(default_factory=time.time)

    def to_dict(self) -> dict[str, Any]:
        return {
            "subtask_id": self.subtask_id,
            "status": self.status.value,
            "retrieved_files": list(self.retrieved_files),
            "edited_files": list(self.edited_files),
            "missed_files": list(self.missed_files),
            "useless_files": list(self.useless_files),
            "checks_run": list(self.checks_run),
            "passed": bool(self.passed),
            "notes": self.notes,
            "run_id": self.run_id,
            "attempt": int(self.attempt),
            "created_at": self.created_at,
        }

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "SubtaskOutcome":
        return cls(
            subtask_id=str(payload["subtask_id"]),
            status=SubtaskStatus(str(payload.get("status", SubtaskStatus.failed.value))),
            retrieved_files=list(payload.get("retrieved_files", [])),
            edited_files=list(payload.get("edited_files", [])),
            missed_files=list(payload.get("missed_files", [])),
            useless_files=list(payload.get("useless_files", [])),
            checks_run=list(payload.get("checks_run", [])),
            passed=bool(payload.get("passed", False)),
            notes=payload.get("notes"),
            run_id=payload.get("run_id"),
            attempt=int(payload.get("attempt", 0)),
            created_at=float(payload.get("created_at", time.time())),
        )


@dataclass
class Subtask:
    id: str
    title: str
    description: str
    type: SubtaskType
    status: SubtaskStatus
    depends_on: list[str] = field(default_factory=list)
    retrieval_query: str = ""
    expected_files: list[str] = field(default_factory=list)
    success_check: str = ""
    risk_level: str = "medium"
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    attempts: int = 0
    last_error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "type": self.type.value,
            "status": self.status.value,
            "depends_on": list(self.depends_on),
            "retrieval_query": self.retrieval_query,
            "expected_files": list(self.expected_files),
            "success_check": self.success_check,
            "risk_level": self.risk_level,
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "attempts": self.attempts,
            "last_error": self.last_error,
        }

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "Subtask":
        return cls(
            id=str(payload["id"]),
            title=str(payload.get("title", "")),
            description=str(payload.get("description", "")),
            type=SubtaskType(str(payload.get("type", SubtaskType.research.value))),
            status=SubtaskStatus(str(payload.get("status", SubtaskStatus.pending.value))),
            depends_on=[str(item) for item in payload.get("depends_on", [])],
            retrieval_query=str(payload.get("retrieval_query", "")),
            expected_files=[str(item) for item in payload.get("expected_files", [])],
            success_check=str(payload.get("success_check", "")),
            risk_level=str(payload.get("risk_level", "medium")),
            created_at=float(payload.get("created_at", time.time())),
            updated_at=float(payload.get("updated_at", time.time())),
            attempts=int(payload.get("attempts", 0)),
            last_error=payload.get("last_error"),
        )


@dataclass
class TaskGraph:
    task_id: str
    task: str
    repo: str | None
    mode: str
    max_subtasks: int
    subtasks: list[Subtask] = field(default_factory=list)
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    current_subtask_id: str | None = None
    run_id: str | None = None
    summary: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "task": self.task,
            "repo": self.repo,
            "mode": self.mode,
            "max_subtasks": self.max_subtasks,
            "subtasks": [subtask.to_dict() for subtask in self.subtasks],
            "created_at": self.created_at,
            "updated_at": self.updated_at,
            "current_subtask_id": self.current_subtask_id,
            "run_id": self.run_id,
            "summary": self.summary,
        }

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "TaskGraph":
        return cls(
            task_id=str(payload.get("task_id") or f"task-{uuid.uuid4().hex[:12]}"),
            task=str(payload.get("task", "")),
            repo=payload.get("repo"),
            mode=str(payload.get("mode", "auto")),
            max_subtasks=int(payload.get("max_subtasks", 8)),
            subtasks=[Subtask.from_dict(item) for item in payload.get("subtasks", [])],
            created_at=float(payload.get("created_at", time.time())),
            updated_at=float(payload.get("updated_at", time.time())),
            current_subtask_id=payload.get("current_subtask_id"),
            run_id=payload.get("run_id"),
            summary=payload.get("summary"),
        )

    def get_subtask(self, subtask_id: str) -> Subtask | None:
        for subtask in self.subtasks:
            if subtask.id == subtask_id:
                return subtask
        return None

    def ready_subtasks(self) -> list[Subtask]:
        ready: list[Subtask] = []
        done_ids = {subtask.id for subtask in self.subtasks if subtask.status == SubtaskStatus.done}
        for subtask in self.subtasks:
            if any(self.get_subtask(dep) is None for dep in subtask.depends_on):
                continue
            if subtask.status == SubtaskStatus.ready:
                if all(dep in done_ids for dep in subtask.depends_on):
                    ready.append(subtask)
            elif subtask.status == SubtaskStatus.pending and all(dep in done_ids for dep in subtask.depends_on):
                ready.append(subtask)
        return ready

    def blocked_subtasks(self) -> list[Subtask]:
        return [subtask for subtask in self.subtasks if subtask.status == SubtaskStatus.blocked]

    def done_subtasks(self) -> list[Subtask]:
        return [subtask for subtask in self.subtasks if subtask.status == SubtaskStatus.done]

    def active_subtask(self) -> Subtask | None:
        if self.current_subtask_id:
            current = self.get_subtask(self.current_subtask_id)
            if current is not None and current.status not in {SubtaskStatus.done, SubtaskStatus.failed, SubtaskStatus.skipped}:
                return current
        for subtask in self.subtasks:
            if subtask.status == SubtaskStatus.running:
                return subtask
        ready = self.ready_subtasks()
        return ready[0] if ready else None
