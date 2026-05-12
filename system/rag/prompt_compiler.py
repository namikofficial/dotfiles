from __future__ import annotations

from .contracts import AgentPlan, CompiledPrompt
from .profiles import profile_by_id
from .retrieval import approx_tokens


def _truncate_context(context_pack: str, token_ceiling: int) -> tuple[str, bool]:
    if approx_tokens(context_pack) <= token_ceiling:
        return context_pack, False
    lines = context_pack.splitlines()
    kept: list[str] = []
    for line in lines:
        candidate = "\n".join([*kept, line])
        if approx_tokens(candidate) > token_ceiling:
            break
        kept.append(line)
    return "\n".join(kept), True


class PromptCompiler:
    def compile(self, plan: AgentPlan, context_pack: str, profile: dict | None = None) -> CompiledPrompt:
        profile_config = profile or profile_by_id(plan.profile)
        prompt_config = profile_config.get("prompt", {})
        profile_prefix = prompt_config.get("system_prefix", "")
        context_text, truncated = _truncate_context(context_pack, plan.context.token_ceiling)
        system_parts = [
            "You are running inside Namik's local rag operating shell.",
            "Stay grounded in the provided local context and cite file paths when possible.",
        ]
        if profile_prefix:
            system_parts.append(profile_prefix)
        user_parts = [
            "# Task",
            plan.task,
            "",
            "# AgentPlan",
            f"- repo: {plan.repo}",
            f"- intent: {plan.intent}",
            f"- mode: {plan.mode}",
            f"- profile: {plan.profile}",
            f"- target: {plan.target}",
            f"- risk: {plan.risk_level}",
            "",
            "# Context",
            context_text or "No context was packed.",
        ]
        system = "\n".join(system_parts)
        user = "\n".join(user_parts)
        return CompiledPrompt(
            system=system,
            user=user,
            token_count=approx_tokens(system) + approx_tokens(user),
            context_summary=(
                f"repo={plan.repo} mode={plan.mode} profile={plan.profile} "
                f"target={plan.target} tokens~{approx_tokens(context_text)}"
            ),
            truncated=truncated,
        )


def compile_prompt(plan: AgentPlan, context_pack: str) -> CompiledPrompt:
    return PromptCompiler().compile(plan, context_pack)
