from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
import sys

sys.path.insert(0, str(SYSTEM_DIR))

from rag.settings import (
    DEFAULT_CONFIG,
    get_mode_profile,
    load_config,
    missing_required_config_keys,
    required_config_key_paths,
    unknown_config_keys,
    write_merged_config,
)


class SettingsTest(unittest.TestCase):
    def test_default_config_uses_dense_qdrant_without_sparse_keys(self) -> None:
        self.assertNotIn("qdrant_vectors", DEFAULT_CONFIG)
        self.assertNotIn("qdrant_sparse", DEFAULT_CONFIG)

    def test_load_config_migrates_legacy_flat_tokens(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config_path = Path(tmp) / "config.json"
            config_path.write_text(
                json.dumps(
                    {
                        "retrieval_context_tokens": 9000,
                        "answer_max_tokens": 1234,
                    }
                )
            )
            config = load_config(config_path)
        self.assertEqual(config["context_budget"]["total_tokens"], 9000)
        self.assertEqual(config["context_budget"]["reserved_answer_tokens"], 1234)
        self.assertEqual(config["context_budget"]["chunk_tokens"], 3200)

    def test_write_merged_config_keeps_overrides_and_full_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            config_path = Path(tmp) / "config.json"
            config_path.write_text(json.dumps({"answer_model": "custom-local"}))
            merged = write_merged_config(config_path)
            persisted = json.loads(config_path.read_text())
        self.assertEqual(merged["answer_model"], "custom-local")
        self.assertEqual(persisted["answer_model"], "custom-local")
        self.assertEqual(persisted["answer_url"], "http://127.0.0.1:8080/v1/chat/completions")
        self.assertEqual(persisted["key_aliases"]["mod"], "SUPER")
        self.assertEqual(persisted["query_intelligence"]["abbreviations"]["cfg"][0], "config")

    def test_get_mode_profile_applies_deep_overrides(self) -> None:
        config = load_config(Path("/does-not-exist"))
        deep = get_mode_profile(config, "deep")
        self.assertEqual(deep["retrieval_pipeline"]["semantic_limit"], 30)
        self.assertEqual(deep["reranker"]["top_k_output"], 10)
        self.assertTrue(deep["answer"]["use_memory"])

    def test_unknown_config_keys_reports_unrecognized_paths(self) -> None:
        raw = {
            "answer_model": "local",
            "unknown_root": True,
            "retrieval_pipeline": {"semantic_limit": 20, "unknown_inner": 1},
        }
        unknown = unknown_config_keys(raw)
        self.assertIn("unknown_root", unknown)
        self.assertIn("retrieval_pipeline.unknown_inner", unknown)

    def test_missing_required_config_keys_detects_removed_nodes(self) -> None:
        config = load_config(Path("/does-not-exist"))
        del config["retrieval_pipeline"]["semantic_limit"]
        missing = missing_required_config_keys(config, required_config_key_paths())
        self.assertIn("retrieval_pipeline.semantic_limit", missing)


if __name__ == "__main__":
    unittest.main()
