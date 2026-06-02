from __future__ import annotations

import json
import urllib.request
import urllib.error


_CODE_SIGNALS = ("def ", "class ", "function ", "import ", "require(", "fn ", "async fn")
_LONG_CONTEXT_THRESHOLD = 18_000
_SIMPLE_THRESHOLD = 2_000


def _approx_tokens(text: str) -> int:
    return max(1, len(text) // 4)


def _task_complexity(question: str, context: str) -> str:
    """Estimate task complexity to guide model selection.

    Returns "simple", "medium", or "long".
    """
    total = _approx_tokens(question + context)
    if total >= _LONG_CONTEXT_THRESHOLD:
        return "long"
    has_code = any(sig in context for sig in _CODE_SIGNALS)
    if total <= _SIMPLE_THRESHOLD and not has_code:
        return "simple"
    return "medium"


def _select_model(config: dict, complexity: str) -> tuple[str, str]:
    """Return (model_id, endpoint) for the given complexity level.

    Falls through roles: long -> long_context_model -> code_model -> answer_model.
    The answer_model is always the final fallback.
    """
    try:
        from .model_registry import ModelRegistry
        registry = ModelRegistry()
        role_chain = {
            "long": ["long_context_model", "code_model", "answer_model"],
            "medium": ["code_model", "answer_model"],
            "simple": ["summarizer_model", "answer_model"],
        }
        for role in role_chain.get(complexity, ["answer_model"]):
            m = registry.get(role)
            if m and m.enabled and m.endpoint:
                return m.model_id, m.endpoint
    except Exception:  # noqa: BLE001
        pass
    return config["answer_model"], config["answer_url"]


def complete_llm(config: dict, system_prompt: str, user_prompt: str, max_tokens: int | None = None) -> str:
    payload = json.dumps(
        {
            "model": config["answer_model"],
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.1,
            "stream": False,
            "max_tokens": max_tokens or config["answer_max_tokens"],
        }
    ).encode()
    request = urllib.request.Request(
        config["answer_url"],
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            body = json.load(response)
    except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as exc:
        raise RuntimeError(f"LLM request failed: {exc}") from exc
    return body.get("choices", [{}])[0].get("message", {}).get("content", "").strip()


def _complete_routed(config: dict, system_prompt: str, user_prompt: str, model_id: str, endpoint: str, max_tokens: int) -> str:
    payload = json.dumps(
        {
            "model": model_id,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.1,
            "stream": False,
            "max_tokens": max_tokens,
        }
    ).encode()
    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=240) as response:
            body = json.load(response)
    except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as exc:
        raise RuntimeError(f"LLM request failed: {exc}") from exc
    return body.get("choices", [{}])[0].get("message", {}).get("content", "").strip()


def ask_llm(config: dict, question: str, context: str, mode: str = "quick") -> str:
    max_tokens = int(config.get("answer", {}).get("max_tokens", config["answer_max_tokens"]))

    complexity = _task_complexity(question, context)
    model_id, endpoint = _select_model(config, complexity)

    if mode == "deep":
        system_prompt = (
            "You are a repo-aware local coding assistant. Use the supplied context first, stay concrete, "
            "prefer code and runtime config over prose docs when they disagree, and cite file paths with "
            "line ranges when possible. For deeper tasks, return markdown with sections: Answer, Plan, Risks, "
            "and Missing Context. Keep the plan actionable and grounded in the provided files."
        )
        user_prompt = (
            f"Task:\n{question}\n\nContext:\n{context}\n\n"
            "Return a grounded engineering analysis with the required sections and concise bullets."
        )
    else:
        system_prompt = (
            "You are a repo-aware local coding assistant. Use the supplied context first, stay concrete, "
            "prefer code and runtime config over prose docs when they disagree, and cite file paths with "
            "line ranges in your answer when possible."
        )
        user_prompt = f"Question:\n{question}\n\nContext:\n{context}\n\nReturn a concise answer and cite files."

    return _complete_routed(config, system_prompt, user_prompt, model_id, endpoint, max_tokens)


def models_url(answer_url: str) -> str:
    return answer_url.replace("/chat/completions", "/models")
