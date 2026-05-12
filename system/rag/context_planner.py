from __future__ import annotations

from .contracts import AgentPlan, ContextPlan, Mode


DEFAULT_CONTEXT_BY_MODE: dict[Mode, ContextPlan] = {
    "quick": ContextPlan(
        include_git=False,
        include_github=False,
        include_test_failures=False,
        include_recent_errors=False,
        include_memory=False,
        include_repo_rules=True,
        semantic_budget=12,
        keyword_budget=12,
        summary_budget=4,
        token_ceiling=5000,
    ),
    "deep": ContextPlan(
        include_git=True,
        include_github=True,
        include_test_failures=True,
        include_recent_errors=True,
        include_memory=True,
        include_repo_rules=True,
        semantic_budget=30,
        keyword_budget=30,
        summary_budget=10,
        token_ceiling=12000,
    ),
    "agent": ContextPlan(
        include_git=True,
        include_github=True,
        include_test_failures=True,
        include_recent_errors=True,
        include_memory=True,
        include_repo_rules=True,
        semantic_budget=36,
        keyword_budget=36,
        summary_budget=12,
        token_ceiling=14000,
    ),
}


def build_context_plan(mode: Mode, profile_config: dict | None = None) -> ContextPlan:
    base = DEFAULT_CONTEXT_BY_MODE[mode]
    retrieval = (profile_config or {}).get("retrieval", {})
    return ContextPlan(
        include_git=bool(retrieval.get("include_git", base.include_git)),
        include_github=bool(retrieval.get("include_github", base.include_github)),
        include_test_failures=bool(retrieval.get("include_test_failures", base.include_test_failures)),
        include_recent_errors=bool(retrieval.get("include_recent_errors", base.include_recent_errors)),
        include_memory=bool(retrieval.get("include_memory", base.include_memory)),
        include_repo_rules=bool(retrieval.get("include_repo_rules", base.include_repo_rules)),
        semantic_budget=int(retrieval.get("semantic_limit", base.semantic_budget)),
        keyword_budget=int(retrieval.get("keyword_limit", base.keyword_budget)),
        summary_budget=int(retrieval.get("summary_limit", base.summary_budget)),
        token_ceiling=int(retrieval.get("token_ceiling", base.token_ceiling)),
    )


def excluded_context_classes(plan: AgentPlan) -> list[str]:
    context = plan.context
    excluded: list[str] = []
    for attr, label in (
        ("include_git", "git"),
        ("include_github", "github"),
        ("include_test_failures", "test_failures"),
        ("include_recent_errors", "recent_errors"),
        ("include_memory", "memory"),
        ("include_repo_rules", "repo_rules"),
    ):
        if not getattr(context, attr):
            excluded.append(label)
    return excluded
