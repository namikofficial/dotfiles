from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from .storage import git_root_for


BUILTIN_PROFILES: dict[str, dict] = {
    "rag-engineer": {
        "id": "rag-engineer",
        "name": "RAG Engineer",
        "description": "Improve the local RAG CLI, retrieval, memory, TUI, and agent workflows.",
        "routing": {
            "trigger_keywords": ["rag", "retrieval", "qdrant", "sqlite", "memory", "context", "tui", "codex", "opencode"],
            "preferred_mode": "agent",
            "default_target": "codex",
        },
        "retrieval": {"semantic_limit": 36, "keyword_limit": 36, "summary_limit": 12, "include_git": True},
        "prompt": {
            "system_prefix": "Preserve the public CLI name as rag. Prefer intent-oriented workflows over command sprawl.",
            "inject_repo_rules": True,
        },
        "execution": {"allowed_executors": ["codex", "opencode", "local-answer", "copy", "file"], "allow_shell": False, "require_approval": True, "sandbox": "workspace-write"},
        "memory": {"candidate_kinds": ["convention", "error_fix", "preference", "command"]},
    },
    "safe-shell": {
        "id": "safe-shell",
        "name": "Safe Shell",
        "description": "Shell and workstation operations with conservative execution policy.",
        "routing": {"trigger_keywords": ["shell", "script", "systemctl", "hyprctl", "logs"], "preferred_mode": "deep", "default_target": "local-answer"},
        "retrieval": {"semantic_limit": 24, "keyword_limit": 24, "include_git": True, "include_recent_errors": True},
        "prompt": {"system_prefix": "Prefer inspection before mutation. Ask before destructive workstation changes.", "inject_repo_rules": True},
        "execution": {"allowed_executors": ["local-answer", "copy", "file"], "allow_shell": False, "require_approval": True, "sandbox": "read-only"},
        "memory": {"candidate_kinds": ["command", "error_fix", "preference"]},
    },
    "repo-review": {
        "id": "repo-review",
        "name": "Repo Review",
        "description": "Review code, plans, diffs, and architecture with repo context.",
        "routing": {"trigger_keywords": ["review", "audit", "risk", "regression", "architecture"], "preferred_mode": "deep", "default_target": "local-answer"},
        "retrieval": {"semantic_limit": 30, "keyword_limit": 30, "include_git": True, "include_test_failures": True},
        "prompt": {"system_prefix": "Lead with concrete findings, risks, and missing tests.", "inject_repo_rules": True},
        "execution": {"allowed_executors": ["local-answer", "copy", "file"], "allow_shell": False, "require_approval": True, "sandbox": "read-only"},
        "memory": {"candidate_kinds": ["convention", "error_fix"]},
    },
    "codex-handoff": {
        "id": "codex-handoff",
        "name": "Codex Handoff",
        "description": "Compile implementation-ready prompts for Codex.",
        "routing": {"trigger_keywords": ["codex", "handoff", "implement", "fix", "build"], "preferred_mode": "agent", "default_target": "codex"},
        "retrieval": {"semantic_limit": 36, "keyword_limit": 36, "summary_limit": 12, "include_git": True, "include_test_failures": True},
        "prompt": {"system_prefix": "Produce a concrete implementation handoff grounded in local repo evidence.", "inject_repo_rules": True},
        "execution": {"allowed_executors": ["codex", "copy", "file"], "allow_shell": False, "require_approval": True, "sandbox": "workspace-write"},
        "memory": {"candidate_kinds": ["preference", "command", "error_fix"]},
    },
    "local-model-ops": {
        "id": "local-model-ops",
        "name": "Local Model Ops",
        "description": "Manage llama.cpp, llama-swap, local models, and RAG runtime health.",
        "routing": {"trigger_keywords": ["llama", "llama.cpp", "llama-swap", "model", "qdrant", "embedding", "reranker"], "preferred_mode": "deep", "default_target": "local-answer"},
        "retrieval": {"semantic_limit": 24, "keyword_limit": 24, "include_recent_errors": True},
        "prompt": {"system_prefix": "Prefer package-managed CUDA paths and config-driven model roles.", "inject_repo_rules": True},
        "execution": {"allowed_executors": ["local-answer", "codex", "copy"], "allow_shell": False, "require_approval": True, "sandbox": "workspace-write"},
        "memory": {"candidate_kinds": ["command", "error_fix", "preference"]},
    },
    "hyprland-debug": {
        "id": "hyprland-debug",
        "name": "Hyprland Debug",
        "description": "Hyprland, Wayle, shell, and desktop configuration debugging.",
        "routing": {"trigger_keywords": ["hypr", "hyprland", "wayle", "keybind", "workspace", "launcher"], "preferred_mode": "deep", "default_target": "local-answer"},
        "retrieval": {"semantic_limit": 28, "keyword_limit": 28, "include_git": True, "include_recent_errors": True},
        "prompt": {"system_prefix": "Validate against installed behavior and preserve existing workflows.", "inject_repo_rules": True},
        "execution": {"allowed_executors": ["local-answer", "codex", "copy"], "allow_shell": False, "require_approval": True, "sandbox": "workspace-write"},
        "memory": {"candidate_kinds": ["preference", "command", "error_fix"]},
    },
    "nestjs-backend": {
        "id": "nestjs-backend",
        "name": "NestJS Backend",
        "description": "TypeScript NestJS backend workflows.",
        "routing": {"trigger_keywords": ["controller", "service", "module", "dto", "guard", "interceptor", "nestjs"], "preferred_mode": "deep", "default_target": "opencode"},
        "retrieval": {"semantic_limit": 24, "keyword_limit": 24, "include_git": True, "include_test_failures": True},
        "prompt": {"system_prefix": "Follow NestJS DI patterns. Avoid any unless the existing code requires it.", "inject_repo_rules": True},
        "execution": {"allowed_executors": ["opencode", "codex", "aider", "local-answer", "copy"], "allow_shell": False, "require_approval": True, "sandbox": "workspace-write"},
        "memory": {"candidate_kinds": ["convention", "error_fix", "preference"]},
    },
}


@dataclass(frozen=True)
class ProfileMatch:
    profile_id: str
    score: float


def load_profiles(_user_dir: Path | None = None) -> dict[str, dict]:
    # Built-ins are intentionally plain dicts for zero-dependency startup. User YAML loading can
    # be layered on top once the public contracts are stable.
    return {profile_id: dict(profile) for profile_id, profile in BUILTIN_PROFILES.items()}


def profile_by_id(profile_id: str) -> dict:
    return load_profiles().get(profile_id, BUILTIN_PROFILES["repo-review"])


def score_profiles(task: str, repo_signals: list[str] | None = None) -> list[ProfileMatch]:
    lowered = task.lower()
    signals = " ".join(repo_signals or []).lower()
    matches: list[ProfileMatch] = []
    for profile_id, profile in load_profiles().items():
        keywords = profile.get("routing", {}).get("trigger_keywords", [])
        hits = sum(1 for keyword in keywords if keyword.lower() in lowered or keyword.lower() in signals)
        score = min(1.0, 0.25 + hits * 0.15)
        if profile_id == "repo-review" and any(word in lowered for word in ("review", "audit", "risk")):
            score += 0.25
        matches.append(ProfileMatch(profile_id, min(score, 1.0)))
    return sorted(matches, key=lambda match: match.score, reverse=True)


DEFAULT_REPO_PROFILE = {
    "repo_type": "generic",
    "important_dirs": [],
    "ignore_dirs": ["node_modules", ".git", ".venv", ".rag", ".agent", "__pycache__"],
    "boost_paths": [],
    "test_patterns": ["tests/**", "**/test_*.py", "**/*_test.py", "**/*.spec.*", "**/*.test.*"],
    "entrypoint_patterns": [],
    "generated_patterns": ["dist/**", "build/**", ".next/**", "coverage/**", "**/*.generated.*"],
    "package_manager": "unknown",
    "check_commands": [],
    "learned_file_patterns": [],
    "learned_task_patterns": [],
}


def repo_profile_path(root: Path | None = None) -> Path:
    repo_root = root or git_root_for(Path.cwd()) or Path.cwd()
    return repo_root / ".rag" / "profile.json"


def infer_repo_profile(root: Path | None = None) -> dict:
    repo_root = root or git_root_for(Path.cwd()) or Path.cwd()
    profile = json.loads(json.dumps(DEFAULT_REPO_PROFILE))
    if (repo_root / "package.json").exists():
        profile["repo_type"] = "node"
        if (repo_root / "pnpm-lock.yaml").exists():
            profile["package_manager"] = "pnpm"
            profile["check_commands"] = ["pnpm typecheck", "pnpm test"]
        elif (repo_root / "package-lock.json").exists():
            profile["package_manager"] = "npm"
            profile["check_commands"] = ["npm run typecheck", "npm test"]
    elif (repo_root / "Cargo.toml").exists():
        profile["repo_type"] = "rust"
        profile["package_manager"] = "cargo"
        profile["check_commands"] = ["cargo test"]
    elif (repo_root / "pyproject.toml").exists():
        profile["repo_type"] = "python"
        profile["package_manager"] = "python"
        profile["check_commands"] = ["python -m unittest discover -s tests -p 'test_*.py'"]
    if (repo_root / "tests").exists():
        profile["important_dirs"].append("tests")
    if (repo_root / "system").exists():
        profile["important_dirs"].append("system")
    if (repo_root / "src").exists():
        profile["important_dirs"].append("src")
    if (repo_root / "setup").exists():
        profile["important_dirs"].append("setup")
    if (repo_root / "configs").exists():
        profile["important_dirs"].append("configs")
    if (repo_root / "app.py").exists():
        profile["entrypoint_patterns"].append("app.py")
    return profile


def validate_repo_profile(profile: dict) -> list[str]:
    required = set(DEFAULT_REPO_PROFILE)
    problems: list[str] = []
    for key in sorted(required):
        if key not in profile:
            problems.append(f"missing {key}")
    for key in sorted(profile):
        if key not in DEFAULT_REPO_PROFILE:
            problems.append(f"unknown {key}")
    for key in (
        "important_dirs",
        "ignore_dirs",
        "boost_paths",
        "test_patterns",
        "entrypoint_patterns",
        "generated_patterns",
        "check_commands",
    ):
        if key in profile and not isinstance(profile[key], list):
            problems.append(f"{key} must be a list")
    return problems


def load_repo_profile(root: Path | None = None) -> dict:
    path = repo_profile_path(root)
    if not path.exists():
        return infer_repo_profile(path.parent.parent if path.parent.name == ".rag" else path.parent)
    data = json.loads(path.read_text())
    profile = json.loads(json.dumps(DEFAULT_REPO_PROFILE))
    profile.update(data)
    return profile


def save_repo_profile(profile: dict, root: Path | None = None) -> Path:
    path = repo_profile_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(profile, indent=2, sort_keys=True) + "\n")
    return path


def init_repo_profile(root: Path | None = None) -> tuple[Path, dict]:
    profile = infer_repo_profile(root)
    path = save_repo_profile(profile, root)
    return path, profile
