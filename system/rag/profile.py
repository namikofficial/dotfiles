from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .profiles import (
    DEFAULT_REPO_PROFILE,
    init_repo_profile,
    load_repo_profile,
    repo_profile_path,
    save_repo_profile,
    validate_repo_profile,
)


def profile_json_path(root: Path | None = None) -> Path:
    return repo_profile_path(root)


def profile_show(root: Path | None = None) -> dict[str, Any]:
    return load_repo_profile(root)


def profile_validate(root: Path | None = None) -> list[str]:
    return validate_repo_profile(load_repo_profile(root))


def profile_init(root: Path | None = None) -> tuple[Path, dict[str, Any]]:
    return init_repo_profile(root)


def _unique(values: list[str]) -> list[str]:
    return [value for value in dict.fromkeys(value for value in values if value)]


def learn_profile_from_run(run_payload: dict[str, Any], root: Path | None = None) -> tuple[Path, dict[str, Any]]:
    repo_root = root or Path.cwd()
    profile = load_repo_profile(repo_root)
    outcome = run_payload.get("outcome", {})
    task = str(run_payload.get("task", ""))
    edited_files = [str(item) for item in outcome.get("edited_files", [])]
    retrieved_files = [str(item) for item in outcome.get("retrieved_files", [])]
    missed_files = [str(item) for item in outcome.get("missed_files", [])]
    checks_run = [str(item) for item in outcome.get("checks_run", [])]

    important_dirs = list(profile.get("important_dirs", []))
    important_dirs.extend(Path(path).parts[0] for path in edited_files if Path(path).parts)
    profile["important_dirs"] = _unique(important_dirs)

    boost_paths = list(profile.get("boost_paths", []))
    boost_paths.extend(edited_files + missed_files)
    profile["boost_paths"] = _unique(boost_paths)

    test_patterns = list(profile.get("test_patterns", []))
    for command in checks_run:
        if "pytest" in command and "tests/**" not in test_patterns:
            test_patterns.append("tests/**")
        if "unittest" in command and "**/test_*.py" not in test_patterns:
            test_patterns.append("**/test_*.py")
    profile["test_patterns"] = _unique(test_patterns)

    learned_file_patterns = list(profile.get("learned_file_patterns", []))
    for path in edited_files:
        suffix = Path(path).suffix
        if suffix:
            learned_file_patterns.append(f"*{suffix}")
    profile["learned_file_patterns"] = _unique(learned_file_patterns)

    learned_task_patterns = list(profile.get("learned_task_patterns", []))
    for token in task.lower().split():
        if len(token) > 4 and token not in learned_task_patterns:
            learned_task_patterns.append(token)
    profile["learned_task_patterns"] = _unique(learned_task_patterns)

    check_commands = list(profile.get("check_commands", []))
    check_commands.extend(checks_run)
    profile["check_commands"] = _unique(check_commands)

    profile.setdefault("repo_type", DEFAULT_REPO_PROFILE["repo_type"])
    profile.setdefault("ignore_dirs", list(DEFAULT_REPO_PROFILE["ignore_dirs"]))
    profile.setdefault("entrypoint_patterns", list(DEFAULT_REPO_PROFILE["entrypoint_patterns"]))
    profile.setdefault("generated_patterns", list(DEFAULT_REPO_PROFILE["generated_patterns"]))
    profile.setdefault("package_manager", DEFAULT_REPO_PROFILE["package_manager"])

    path = save_repo_profile(profile, repo_root)
    return path, profile


def profile_to_json(profile: dict[str, Any]) -> str:
    return json.dumps(profile, indent=2, sort_keys=True) + "\n"

