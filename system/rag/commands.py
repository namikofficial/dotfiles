from __future__ import annotations

from pathlib import Path
from typing import Any

from .agent_support import suggest_commands
from .profiles import load_repo_profile
from .task_graph import Subtask


def command_plan_for_task(root: Path, task: str, selected_files: list[str], profile: dict[str, Any] | None = None) -> list[str]:
    profile = profile or load_repo_profile(root)
    commands = suggest_commands(root, selected_files, task, profile)
    lowered = task.lower()
    if "test" in lowered and not any("test" in command for command in commands):
        commands.append("python -m unittest discover -s tests -p 'test_*.py'")
    return list(dict.fromkeys(commands))


def command_plan_for_subtask(
    root: Path,
    subtask: Subtask,
    selected_files: list[str],
    profile: dict[str, Any] | None = None,
) -> list[str]:
    return command_plan_for_task(root, subtask.title + "\n" + subtask.description, selected_files, profile)

