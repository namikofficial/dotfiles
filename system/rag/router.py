from __future__ import annotations

import uuid
from pathlib import Path

from .context_planner import build_context_plan, excluded_context_classes
from .contracts import AgentPlan, Intent, Mode, Target
from .profiles import load_profiles, profile_by_id, score_profiles
from .storage import git_root_for, infer_repo_filter


INTENT_MARKERS: dict[Intent, tuple[str, ...]] = {
    "implement": ("implement", "build", "add", "wire", "create", "fix", "complete"),
    "plan": ("plan", "design", "architecture", "roadmap", "spec"),
    "review": ("review", "audit", "check", "risk", "regression"),
    "debug": ("debug", "failing", "broken", "error", "traceback", "why"),
    "ops": ("deploy", "runtime", "model", "llama", "qdrant", "doctor", "health"),
    "question": ("what", "where", "how", "explain", "show"),
}


def classify_intent(task: str) -> tuple[Intent, float, str]:
    lowered = task.lower()
    scores: dict[Intent, int] = {}
    for intent, markers in INTENT_MARKERS.items():
        scores[intent] = sum(1 for marker in markers if marker in lowered)
    selected = max(scores, key=lambda intent: scores[intent])
    if scores[selected] == 0:
        return "question", 0.55, "defaulted to question intent"
    confidence = min(0.95, 0.6 + scores[selected] * 0.1)
    return selected, confidence, f"matched {selected} intent markers"


def select_mode(intent: Intent, task: str, profile: dict) -> Mode:
    preferred = profile.get("routing", {}).get("preferred_mode")
    if preferred in {"quick", "deep", "agent"} and intent in {"implement", "ops"}:
        return preferred
    if intent == "question" and len(task) < 120:
        return "quick"
    if intent in {"implement", "ops"}:
        return "agent"
    return "deep"


def select_target(explicit_target: Target | None, intent: Intent, profile: dict) -> Target:
    if explicit_target:
        return explicit_target
    profile_target = profile.get("routing", {}).get("default_target")
    allowed = set(profile.get("execution", {}).get("allowed_executors", []))
    if profile_target in allowed:
        return profile_target
    if intent in {"question", "review", "plan", "debug"}:
        return "local-answer"
    return "copy"


def assess_risk(task: str, target: Target) -> tuple[str, bool]:
    lowered = task.lower()
    destructive = any(marker in lowered for marker in ("delete", "remove", "reset", "drop", "wipe", "prune"))
    if destructive:
        return "high", True
    if target in {"codex", "opencode", "aider"} or any(marker in lowered for marker in ("implement", "refactor", "migration")):
        return "medium", False
    return "low", False


def likely_files_from_task(task: str) -> list[str]:
    return [
        token.strip(".,:;()[]{}")
        for token in task.split()
        if "/" in token or token.endswith((".py", ".ts", ".tsx", ".js", ".rs", ".md", ".sh"))
    ][:8]


def build_agent_plan(
    task: str,
    *,
    conn,
    repo: str | None = None,
    explicit_target: Target | None = None,
    cwd: Path | None = None,
) -> AgentPlan:
    resolved_repo = infer_repo_filter(conn, repo)
    if resolved_repo is None:
        root = git_root_for(cwd or Path.cwd())
        resolved_repo = root.name if root else "unscoped"
    intent, intent_confidence, intent_reason = classify_intent(task)
    repo_signals = [resolved_repo]
    profile_matches = score_profiles(task, repo_signals)
    selected_profile_id = profile_matches[0].profile_id if profile_matches else "repo-review"
    selected_profile = profile_by_id(selected_profile_id)
    mode = select_mode(intent, task, selected_profile)
    target = select_target(explicit_target, intent, selected_profile)
    context = build_context_plan(mode, selected_profile)
    risk_level, destructive_risk = assess_risk(task, target)
    execution = selected_profile.get("execution", {})
    confidence = min(intent_confidence, profile_matches[0].score if profile_matches else 0.55)
    draft = AgentPlan(
        task=task,
        repo=resolved_repo,
        session_id=str(uuid.uuid4()),
        intent=intent,
        mode=mode,
        profile=selected_profile_id,
        target=target,
        confidence=round(confidence, 3),
        context=context,
        retrieval_semantic_limit=context.semantic_budget,
        retrieval_keyword_limit=context.keyword_budget,
        use_model_reranker=False,
        allow_shell=bool(execution.get("allow_shell", False)),
        require_approval=bool(execution.get("require_approval", True)),
        sandbox=execution.get("sandbox", "workspace-write"),
        risk_level=risk_level,
        likely_files=likely_files_from_task(task),
        destructive_risk=destructive_risk,
        top_profiles=[(match.profile_id, round(match.score, 3)) for match in profile_matches[:3]],
        route_reason=f"{intent_reason}; selected {selected_profile_id} profile",
        context_classes_excluded=[],
    )
    return AgentPlan(
        **{
            **draft.__dict__,
            "context_classes_excluded": excluded_context_classes(draft),
        }
    )


def target_from_flag(flag: str | None) -> Target | None:
    mapping: dict[str, Target] = {
        "codex": "codex",
        "opencode": "opencode",
        "aider": "aider",
        "copy": "copy",
        "file": "file",
        "local-answer": "local-answer",
    }
    return mapping.get(flag or "")
