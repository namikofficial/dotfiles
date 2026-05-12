from __future__ import annotations

import json
import urllib.request
from dataclasses import dataclass
from pathlib import Path

from .llm import models_url
from .runtime import CONFIG_PATH
from .settings import load_config


MODEL_CONFIG_PATH = Path("~/.config/rag/models.json").expanduser()


@dataclass(frozen=True)
class ModelRole:
    role: str
    provider: str
    model_id: str
    path: str | None = None
    endpoint: str | None = None
    enabled: bool = True
    fallback_role: str | None = None


class ModelRegistry:
    def __init__(self, config_path: Path = MODEL_CONFIG_PATH) -> None:
        self.config_path = config_path
        self.roles = self._load_roles()

    def _load_roles(self) -> dict[str, ModelRole]:
        config = load_config(CONFIG_PATH)
        defaults = {
            "answer_model": ModelRole("answer_model", "openai_compat", config["answer_model"], endpoint=config["answer_url"]),
            "embedding_model": ModelRole("embedding_model", "fastembed", config["embedding_model"]),
            "reranker_model": ModelRole("reranker_model", "heuristic", config.get("reranker", {}).get("mode", "heuristic"), enabled=bool(config.get("reranker", {}).get("enabled", True))),
            "query_expansion_model": ModelRole("query_expansion_model", "rules", "developer-lexicon", enabled=False),
            "summarizer_model": ModelRole("summarizer_model", "openai_compat", config["answer_model"], endpoint=config["answer_url"], fallback_role="answer_model"),
            "code_model": ModelRole("code_model", "openai_compat", config["answer_model"], endpoint=config["answer_url"], fallback_role="answer_model"),
        }
        if not self.config_path.exists():
            return defaults
        try:
            raw = json.loads(self.config_path.read_text())
        except (json.JSONDecodeError, OSError):
            return defaults
        roles = dict(defaults)
        for role, value in raw.get("roles", {}).items():
            if isinstance(value, dict):
                roles[role] = ModelRole(
                    role=role,
                    provider=str(value.get("provider", defaults.get(role, ModelRole(role, "unknown", "")).provider)),
                    model_id=str(value.get("model_id", value.get("model", ""))),
                    path=value.get("path"),
                    endpoint=value.get("endpoint"),
                    enabled=bool(value.get("enabled", True)),
                    fallback_role=value.get("fallback_role"),
                )
        return roles

    def get(self, role: str) -> ModelRole | None:
        return self.roles.get(role)

    def all_roles(self) -> list[ModelRole]:
        return list(self.roles.values())

    def available(self, role: str) -> tuple[bool, str]:
        model = self.get(role)
        if model is None:
            return False, "role is not configured"
        if not model.enabled:
            return False, "role is disabled"
        if model.path and not Path(model.path).expanduser().exists():
            return False, f"missing model path: {model.path}"
        if model.endpoint and role == "answer_model":
            try:
                request = urllib.request.Request(models_url(model.endpoint))
                with urllib.request.urlopen(request, timeout=3) as response:
                    response.read(1)
                return True, model.endpoint
            except Exception as exc:
                return False, str(exc)
        return True, model.provider


def model_role_matrix() -> list[tuple[str, bool, str]]:
    registry = ModelRegistry()
    rows: list[tuple[str, bool, str]] = []
    for role in registry.all_roles():
        ok, reason = registry.available(role.role)
        rows.append((role.role, ok, reason))
    return rows
