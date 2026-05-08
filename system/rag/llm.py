from __future__ import annotations

import json
import urllib.request


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
    with urllib.request.urlopen(request, timeout=240) as response:
        body = json.load(response)
    return body.get("choices", [{}])[0].get("message", {}).get("content", "").strip()


def ask_llm(config: dict, question: str, context: str, mode: str = "quick") -> str:
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
        return complete_llm(config, system_prompt, user_prompt)
    system_prompt = (
        "You are a repo-aware local coding assistant. Use the supplied context first, stay concrete, "
        "prefer code and runtime config over prose docs when they disagree, and cite file paths with "
        "line ranges in your answer when possible."
    )
    user_prompt = f"Question:\n{question}\n\nContext:\n{context}\n\nReturn a concise answer and cite files."
    return complete_llm(config, system_prompt, user_prompt)


def models_url(answer_url: str) -> str:
    return answer_url.replace("/chat/completions", "/models")
