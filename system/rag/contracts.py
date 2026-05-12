from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Literal


Intent = Literal["question", "plan", "implement", "review", "debug", "ops"]
Mode = Literal["quick", "deep", "agent"]
Target = Literal["local-answer", "codex", "opencode", "aider", "copy", "file"]
Sandbox = Literal["none", "workspace-write", "read-only"]
RiskLevel = Literal["low", "medium", "high"]


@dataclass(frozen=True)
class ContextPlan:
    include_git: bool
    include_github: bool
    include_test_failures: bool
    include_recent_errors: bool
    include_memory: bool
    include_repo_rules: bool
    semantic_budget: int
    keyword_budget: int
    summary_budget: int
    token_ceiling: int

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class AgentPlan:
    task: str
    repo: str
    session_id: str
    intent: Intent
    mode: Mode
    profile: str
    target: Target
    confidence: float
    context: ContextPlan
    retrieval_semantic_limit: int
    retrieval_keyword_limit: int
    use_model_reranker: bool
    allow_shell: bool
    require_approval: bool
    sandbox: Sandbox
    risk_level: RiskLevel
    likely_files: list[str] = field(default_factory=list)
    destructive_risk: bool = False
    top_profiles: list[tuple[str, float]] = field(default_factory=list)
    route_reason: str = ""
    context_classes_excluded: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["top_profiles"] = [
            {"profile": profile, "score": score} for profile, score in self.top_profiles
        ]
        return payload


@dataclass(frozen=True)
class CompiledPrompt:
    system: str
    user: str
    token_count: int
    context_summary: str
    truncated: bool

    def text(self) -> str:
        return f"{self.system.strip()}\n\n{self.user.strip()}".strip()

    def to_dict(self) -> dict:
        return asdict(self)


@dataclass(frozen=True)
class ExecutionResult:
    success: bool
    stdout: str
    stderr: str
    exit_code: int
    duration_ms: int
    files_modified: list[str]

    def to_dict(self) -> dict:
        return asdict(self)
