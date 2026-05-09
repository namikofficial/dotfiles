from __future__ import annotations

import json
from pathlib import Path

from .runtime import CONFIG_PATH

DEFAULT_CONFIG = {
    "qdrant_url": "http://127.0.0.1:6333",
    "qdrant_collection": "local-rag-chunks",
    "answer_url": "http://127.0.0.1:8080/v1/chat/completions",
    "answer_model": "local",
    "embedding_model": "BAAI/bge-small-en-v1.5",
    "retrieval_context_tokens": 12000,
    "answer_max_tokens": 2500,
    "key_aliases": {
        "mod": "SUPER",
        "mainmod": "SUPER",
        "win": "SUPER",
        "windows": "SUPER",
        "cmd": "SUPER",
        "ctrl": "CTRL",
        "control": "CTRL",
    },
    "retrieval": {
        "max_chunks_per_file": 3,
        "max_fact_files": 8,
        "max_summary_files": 8,
        "max_context_sources": 6,
    },
    "retrieval_pipeline": {
        "rewrite_limit": 3,
        "semantic_limit": 10,
        "keyword_limit": 10,
        "recent_limit": 10,
        "definition_limit": 8,
        "graph_seed_limit": 6,
        "graph_limit": 8,
        "neighbor_limit": 6,
        "use_qdrant_query_api": True,
        "use_definition_first": True,
        "use_graph_expansion": True,
        "use_neighbor_chunks": True,
        "use_database_routing": True,
        "use_config_trace": True,
    },
    "query_intelligence": {
        "abbreviations": {
            "api": ["api", "endpoint", "route", "controller"],
            "auth": ["auth", "authentication", "authorization", "login", "token"],
            "cfg": ["config", "configuration", "settings"],
            "cli": ["cli", "command", "shell", "tool"],
            "db": ["database", "sql", "query", "schema", "table"],
            "env": ["env", "environment", "variable"],
            "fn": ["function", "method"],
            "impl": ["implementation"],
            "svc": ["service"],
            "ui": ["ui", "component", "layout", "view"],
        },
        "developer_lexicon": {
            "bug": ["bug", "error", "failure", "broken"],
            "compose": ["docker", "compose", "container"],
            "k8s": ["kubernetes", "cluster", "deployment"],
            "perf": ["performance", "latency", "optimize", "cache"],
            "repo": ["repository", "project", "codebase"],
        },
        "intent_markers": {
            "keybind": ["super", "alt", "ctrl", "shift", "keybind", "shortcut", "xf86"],
            "tool": ["command", "cli tool", "binary", "docker", "gh", "opencode", "just", "script"],
            "symbol": ["function", "method", "class", "symbol", "import", "interface", "type", "hook"],
            "path": ["path", "file", "folder", "directory", "module", "under", "inside", "src/", "tests/"],
            "config": ["config", "configuration", "setting", "settings", "env", "variable", "flag", "option"],
            "config_trace": ["trace", "flow", "where", "used", "loaded", "read", "resolved", "wire", "wiring"],
            "database": ["database", "db", "postgres", "postgresql", "mysql", "sqlite", "mssql", "mongo", "mongodb", "redis", "schema", "table", "column", "entity", "migration", "orm", "repository", "collection", "query"],
            "sql": ["sql", "query", "table", "column", "index", "migration", "schema", "postgres", "postgresql", "mysql", "sqlite", "mssql", "mongo", "mongodb", "redis"],
            "error": ["error", "exception", "traceback", "stack trace", "failed", "failure", "undefined", "panic", "enoent"],
        },
        "file_type_hints": {
            "typescript": {
                "terms": ["ts", "tsx", "typescript", "nestjs", "react"],
                "languages": ["typescript"],
                "kinds": ["code"],
                "paths": ["src", "app", "components"],
                "extensions": [".ts", ".tsx"],
            },
            "javascript": {
                "terms": ["js", "jsx", "javascript", "node"],
                "languages": ["javascript"],
                "kinds": ["code"],
                "paths": ["src", "scripts"],
                "extensions": [".js", ".jsx", ".mjs", ".cjs"],
            },
            "shell": {
                "terms": ["shell", "bash", "zsh", "sh", "alias"],
                "languages": ["shell"],
                "kinds": ["code", "config"],
                "paths": ["bin", "scripts", "shell", "zsh"],
                "extensions": [".sh", ".zsh"],
            },
            "sql": {
                "terms": ["sql", "postgres", "postgresql", "mysql", "sqlite", "mssql", "migration"],
                "languages": ["sql"],
                "kinds": ["code", "config"],
                "paths": ["sql", "db", "migrations"],
                "extensions": [".sql"],
            },
            "docker": {
                "terms": ["docker", "compose", "container"],
                "languages": ["yaml", "shell"],
                "kinds": ["config"],
                "paths": ["docker", "compose"],
                "extensions": [".yml", ".yaml"],
            },
            "config": {
                "terms": ["config", "yaml", "yml", "json", "toml"],
                "languages": ["yaml", "json", "toml"],
                "kinds": ["config"],
                "paths": ["config", "configs", ".config"],
                "extensions": [".json", ".yaml", ".yml", ".toml", ".ini"],
            },
            "docs": {
                "terms": ["doc", "docs", "readme", "markdown"],
                "languages": ["markdown"],
                "kinds": ["docs", "text"],
                "paths": ["docs"],
                "extensions": [".md"],
            },
            "hyprland": {
                "terms": ["hypr", "hyprland", "keybind"],
                "languages": ["hyprland"],
                "kinds": ["config"],
                "paths": ["hypr"],
                "extensions": [".conf"],
            },
        },
        "intent_fact_kinds": {
            "config": ["config-key", "config-section", "env", "compose-config", "compose-env", "package-field", "package-script", "tsconfig-option", "tsconfig-alias", "tool-config", "tool-alias"],
            "database": ["sql-object", "entity", "repository", "mongo-collection", "redis-key", "compose-service", "config-key"],
            "error": ["package-script", "compose-service", "tool", "tool-config"],
            "path": ["config-key", "config-section", "route-handler", "route-controller", "frontend-route", "package-script", "tsconfig-alias", "tool-alias"],
            "sql": ["sql-object", "entity", "repository"],
            "symbol": ["function", "service", "entity", "module", "route-controller", "route-handler", "component", "hook", "page", "layout", "frontend-provider", "guard", "interceptor", "pipe", "dto", "repository"],
            "tool": ["tool", "alias", "package-script", "compose-service", "tool-config", "tool-alias"],
        },
        "typo_tolerance": {
            "enabled": True,
            "min_token_length": 4,
            "candidate_limit": 4000,
            "cutoff": 0.82,
            "max_length_delta": 2,
        },
        "boosts": {
            "path_weight": 0.08,
            "symbol_weight": 0.08,
            "file_type_weight": 0.05,
            "recency_weight": 0.02,
            "fact_kind_weight": 1.4,
            "summary_kind_weight": 1.0,
        },
    },
    "context_budget": {
        "total_tokens": 12000,
        "memory_tokens": 1800,
        "context_source_tokens": 2400,
        "facts_tokens": 1800,
        "file_summary_tokens": 2200,
        "chunk_tokens": 6000,
        "reserved_answer_tokens": 2200,
    },
    "context_pack_order": {
        "quick": ["facts", "chunks", "file_summaries"],
        "deep": ["operational_state", "context_sources", "facts", "repo_memory", "chunks", "file_summaries"],
        "agent": ["operational_state", "context_sources", "facts", "repo_memory", "chunks", "file_summaries"],
    },
    "routing": {
        "default_mode": "auto",
    },
    "mode_profiles": {
        "quick": {
            "retrieval_pipeline": {
                "rewrite_limit": 2,
                "semantic_limit": 12,
                "keyword_limit": 12,
                "recent_limit": 6,
            },
            "retrieval": {
                "max_chunks_per_file": 2,
                "max_fact_files": 4,
                "max_summary_files": 4,
            },
            "reranker": {
                "top_k_input": 12,
                "top_k_output": 6,
            },
            "answer": {
                "use_memory": False,
                "use_operational_state": False,
                "operational_state_tokens": 0,
                "style": "quick",
            },
        },
        "deep": {
            "retrieval_pipeline": {
                "rewrite_limit": 4,
                "semantic_limit": 30,
                "keyword_limit": 30,
                "recent_limit": 12,
            },
            "retrieval": {
                "max_chunks_per_file": 3,
                "max_fact_files": 10,
                "max_summary_files": 10,
            },
            "reranker": {
                "top_k_input": 30,
                "top_k_output": 10,
            },
            "answer": {
                "use_memory": True,
                "use_operational_state": True,
                "operational_state_tokens": 1200,
                "style": "deep",
            },
        },
        "agent": {
            "retrieval_pipeline": {
                "rewrite_limit": 5,
                "semantic_limit": 36,
                "keyword_limit": 36,
                "recent_limit": 14,
            },
            "retrieval": {
                "max_chunks_per_file": 4,
                "max_fact_files": 12,
                "max_summary_files": 12,
            },
            "reranker": {
                "top_k_input": 36,
                "top_k_output": 12,
            },
            "answer": {
                "use_memory": True,
                "use_operational_state": True,
                "operational_state_tokens": 1600,
                "style": "agent",
            },
        },
    },
    "developer_profile": {
        "languages": ["typescript", "javascript", "python", "rust", "go", "c", "sql", "shell"],
        "frameworks": ["nestjs", "express", "react", "vite", "mikroorm"],
        "databases": ["postgres", "mssql", "mongodb", "redis"],
        "infra": ["docker", "systemd", "grafana", "prometheus", "caddy"],
        "os": ["arch", "hyprland", "wayland", "nvidia"],
    },
    "indexing": {
        "profile": "balanced",
        "prefer_tree_sitter": True,
        "semantic_line_limit": 800,
    },
    "index_profiles": {
        "fast": {
            "facts": True,
            "file_summaries": False,
            "repo_memory": False,
        },
        "balanced": {
            "facts": True,
            "file_summaries": True,
            "repo_memory": False,
        },
        "deep": {
            "facts": True,
            "file_summaries": True,
            "repo_memory": True,
        },
    },
    "reranker": {
        "enabled": True,
        "mode": "heuristic",
        "top_k_input": 30,
        "top_k_output": 12,
        "content_weight": 0.03,
        "path_weight": 0.02,
        "symbol_weight": 0.02,
        "model_name": "",
        "model_device": "cpu",
        "model_weight": 0.2,
        "fallback_to_heuristic": True,
        "explain_top_n": 5,
    },
    "ranking_profiles": {
        "default": {
            "definition_bonus": 0.12,
            "graph_bonus": 0.08,
            "neighbor_bonus": 0.03,
            "fact_path_bonus": 0.18,
            "summary_path_bonus": 0.1,
            "config_bonus": 0.0,
            "database_bonus": 0.0,
            "docs_bonus": 0.0,
        },
        "symbol": {
            "definition_bonus": 0.32,
            "graph_bonus": 0.12,
        },
        "path": {
            "definition_bonus": 0.22,
            "graph_bonus": 0.1,
            "neighbor_bonus": 0.05,
        },
        "config": {
            "config_bonus": 0.22,
            "graph_bonus": 0.14,
        },
        "database": {
            "definition_bonus": 0.24,
            "graph_bonus": 0.18,
            "database_bonus": 0.24,
        },
        "error": {
            "graph_bonus": 0.14,
            "docs_bonus": 0.12,
        },
        "tool": {
            "config_bonus": 0.08,
            "graph_bonus": 0.1,
        },
    },
}


def merge_nested_dicts(base: dict, override: dict) -> dict:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_nested_dicts(merged[key], value)
        else:
            merged[key] = value
    return merged


def apply_legacy_config_migrations(config: dict, raw_config: dict) -> dict:
    if "context_budget" not in raw_config and "retrieval_context_tokens" in raw_config:
        total_tokens = int(raw_config["retrieval_context_tokens"])
        config["context_budget"]["total_tokens"] = total_tokens
        config["context_budget"]["chunk_tokens"] = max(
            2000,
            total_tokens
            - config["context_budget"]["memory_tokens"]
            - config["context_budget"]["facts_tokens"]
            - config["context_budget"]["file_summary_tokens"],
        )
    if "context_budget" in raw_config and "total_tokens" not in raw_config["context_budget"]:
        config["context_budget"]["total_tokens"] = raw_config.get(
            "retrieval_context_tokens", config["context_budget"]["total_tokens"]
        )
    config["context_budget"]["reserved_answer_tokens"] = raw_config.get(
        "answer_max_tokens",
        config["context_budget"]["reserved_answer_tokens"],
    )
    return config


def load_config(config_path: Path = CONFIG_PATH) -> dict:
    config = json.loads(json.dumps(DEFAULT_CONFIG))
    raw_config: dict = {}
    if config_path.exists():
        raw_config = json.loads(config_path.read_text())
        config = merge_nested_dicts(config, raw_config)
    return apply_legacy_config_migrations(config, raw_config)


def write_merged_config(config_path: Path = CONFIG_PATH) -> dict:
    current = {}
    if config_path.exists():
        current = json.loads(config_path.read_text())
    merged = merge_nested_dicts(DEFAULT_CONFIG, current)
    config_path.write_text(json.dumps(merged, indent=2) + "\n")
    return merged


def get_index_profile(config: dict, override: str | None) -> tuple[str, dict]:
    profile_name = override or config["indexing"]["profile"]
    profile = config["index_profiles"].get(profile_name)
    if profile is None:
        raise SystemExit(f"Unknown index profile: {profile_name}")
    return profile_name, profile


def get_mode_profile(config: dict, mode: str) -> dict:
    profile = config["mode_profiles"].get(mode)
    if profile is None:
        raise SystemExit(f"Unknown mode profile: {mode}")
    return merge_nested_dicts(config, profile)


LEGACY_CONFIG_KEYS = {
    "retrieval_context_tokens",
    "answer_max_tokens",
}


def _flatten_dict_paths(data: dict, prefix: str = "") -> set[str]:
    paths: set[str] = set()
    for key, value in data.items():
        path = f"{prefix}.{key}" if prefix else key
        paths.add(path)
        if isinstance(value, dict):
            paths.update(_flatten_dict_paths(value, path))
    return paths


def _has_path(config: dict, path: str) -> bool:
    current: object = config
    for segment in path.split("."):
        if not isinstance(current, dict) or segment not in current:
            return False
        current = current[segment]
    return True


def required_config_key_paths(default_config: dict = DEFAULT_CONFIG) -> set[str]:
    return _flatten_dict_paths(default_config)


def missing_required_config_keys(config: dict, required_paths: set[str] | None = None) -> list[str]:
    required = required_paths or required_config_key_paths()
    return sorted(path for path in required if not _has_path(config, path))


def unknown_config_keys(
    raw_config: dict,
    default_config: dict = DEFAULT_CONFIG,
    *,
    allowed_top_level: set[str] | None = None,
) -> list[str]:
    allowed = allowed_top_level or LEGACY_CONFIG_KEYS
    unknown: list[str] = []

    def walk(raw: dict, known: dict, prefix: str = "") -> None:
        for key, value in raw.items():
            path = f"{prefix}.{key}" if prefix else key
            if not prefix and key in allowed:
                continue
            if key not in known:
                unknown.append(path)
                continue
            known_value = known[key]
            if isinstance(value, dict):
                if isinstance(known_value, dict):
                    walk(value, known_value, path)
                else:
                    unknown.append(path)

    walk(raw_config, default_config)
    return sorted(set(unknown))
