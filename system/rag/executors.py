from __future__ import annotations

import shutil
import subprocess
import time
from pathlib import Path
from typing import Protocol

from .contracts import AgentPlan, CompiledPrompt, ExecutionResult


class Executor(Protocol):
    id: str

    def available(self) -> tuple[bool, str]: ...

    def dry_run(self, prompt: CompiledPrompt, plan: AgentPlan) -> str: ...

    def run(self, prompt: CompiledPrompt, plan: AgentPlan) -> ExecutionResult: ...


class CommandExecutor:
    def __init__(self, executor_id: str, binary: str, args: list[str]) -> None:
        self.id = executor_id
        self.binary = binary
        self.args = args

    def available(self) -> tuple[bool, str]:
        path = shutil.which(self.binary)
        if path is None:
            return False, f"{self.binary} not found in PATH"
        try:
            result = subprocess.run([path, "--version"], text=True, capture_output=True, timeout=5)
        except Exception as exc:
            return False, str(exc)
        version = (result.stdout or result.stderr).strip().splitlines()
        if result.returncode != 0:
            return False, version[0] if version else f"{self.binary} --version exited {result.returncode}"
        return True, version[0] if version else path

    def dry_run(self, prompt: CompiledPrompt, plan: AgentPlan) -> str:
        return " ".join([self.binary, *self.args, "<compiled-prompt>"])

    def run(self, prompt: CompiledPrompt, plan: AgentPlan) -> ExecutionResult:
        started = time.monotonic()
        before = _git_dirty_files()
        command = [self.binary, *self.args, prompt.text()]
        result = subprocess.run(command, text=True, capture_output=True)
        after = _git_dirty_files()
        return ExecutionResult(
            success=result.returncode == 0,
            stdout=result.stdout,
            stderr=result.stderr,
            exit_code=result.returncode,
            duration_ms=int((time.monotonic() - started) * 1000),
            files_modified=sorted(after - before),
        )


class LocalAnswerExecutor:
    id = "local-answer"

    def available(self) -> tuple[bool, str]:
        return True, "local answer executor is built in"

    def dry_run(self, prompt: CompiledPrompt, plan: AgentPlan) -> str:
        return "local-answer <compiled-prompt>"

    def run(self, prompt: CompiledPrompt, plan: AgentPlan) -> ExecutionResult:
        return ExecutionResult(True, prompt.text(), "", 0, 0, [])


class CopyExecutor(LocalAnswerExecutor):
    id = "copy"

    def available(self) -> tuple[bool, str]:
        return True, "copy target prints the compiled prompt"


class FileExecutor(LocalAnswerExecutor):
    id = "file"

    def available(self) -> tuple[bool, str]:
        return True, "file target writes only when an output path is supplied by caller"


def _git_dirty_files() -> set[str]:
    try:
        result = subprocess.run(["git", "status", "--short"], text=True, capture_output=True, timeout=5)
    except Exception:
        return set()
    files: set[str] = set()
    for line in result.stdout.splitlines():
        if len(line) > 3:
            files.add(line[3:].strip())
    return files


def get_executor(executor_id: str) -> Executor:
    if executor_id == "codex":
        return CommandExecutor("codex", "codex", ["exec", "--sandbox", "workspace-write", "--ask-for-approval", "on-request"])
    if executor_id == "opencode":
        return CommandExecutor("opencode", "opencode", [])
    if executor_id == "aider":
        return CommandExecutor("aider", "aider", ["--message"])
    if executor_id == "copy":
        return CopyExecutor()
    if executor_id == "file":
        return FileExecutor()
    return LocalAnswerExecutor()


def executor_matrix() -> list[tuple[str, bool, str]]:
    rows: list[tuple[str, bool, str]] = []
    for executor_id in ("local-answer", "codex", "opencode", "aider", "copy", "file"):
        ok, reason = get_executor(executor_id).available()
        rows.append((executor_id, ok, reason))
    return rows
