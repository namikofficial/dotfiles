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
    },
    "context_budget": {
        "total_tokens": 12000,
        "memory_tokens": 1800,
        "facts_tokens": 1800,
        "file_summary_tokens": 2200,
        "chunk_tokens": 6000,
        "reserved_answer_tokens": 2200,
    },
    "indexing": {
        "profile": "balanced",
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
