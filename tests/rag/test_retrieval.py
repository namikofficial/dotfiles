from __future__ import annotations

import copy
import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.retrieval import (
    RetrievalCandidates,
    build_retrieval_plan,
    fact_hits,
    rank_retrieval_candidates,
    reciprocal_rank_fusion,
    rewrite_queries,
)
from rag.settings import DEFAULT_CONFIG
from rag.storage import ensure_db


def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


class RetrievalTest(unittest.TestCase):
    def test_rewrite_queries_splits_symbol_terms(self) -> None:
        rewrites = rewrite_queries("Find ScratchpadDashboard keybind")
        self.assertEqual(rewrites[0], "Find ScratchpadDashboard keybind")
        self.assertIn("find scratchpaddashboard keybind", rewrites)
        self.assertIn("find scratchpad dashboard keybind", rewrites)

    def test_reciprocal_rank_fusion_rewards_cross_list_agreement(self) -> None:
        scores = reciprocal_rank_fusion(["a", "b"], ["b", "a"])
        self.assertGreater(scores["a"], 0)
        self.assertGreater(scores["b"], 0)
        self.assertAlmostEqual(scores["a"], scores["b"], places=9)

    def test_fact_hits_finds_matching_keybind(self) -> None:
        conn = make_connection()
        conn.execute(
            """
            INSERT INTO facts (fact_id, repo, path, kind, key, value, line, confidence, source, file_hash, updated_at)
            VALUES ('f1', 'dotfiles', 'hypr/hyprland.conf', 'keybind', 'SUPER+TAB', 'exec overview', 42, 1.0, 'extractor', 'abc', 1.0)
            """
        )
        conn.commit()
        plan = build_retrieval_plan("super tab", "dotfiles")
        rows = fact_hits(conn, plan, copy.deepcopy(DEFAULT_CONFIG))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["path"], "hypr/hyprland.conf")

    def test_rank_retrieval_candidates_promotes_hypr_keybind_chunk(self) -> None:
        conn = make_connection()
        config = copy.deepcopy(DEFAULT_CONFIG)
        conn.execute(
            """
            INSERT INTO chunks (
                chunk_id, repo, root, path, language, kind, symbol, modified_at,
                file_hash, index_schema, embedding_model, chunker, chunk_index,
                start_line, end_line, content
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "c1",
                "dotfiles",
                "/tmp/dotfiles",
                "hypr/hyprland.conf",
                "hyprland",
                "config",
                "bind:SUPER+TAB:exec",
                1.0,
                "hash1",
                "rag-v4",
                config["embedding_model"],
                "semantic-lines-v4",
                0,
                40,
                44,
                "bind = SUPER, TAB, exec, scratchpad-overview",
            ),
        )
        conn.execute(
            """
            INSERT INTO chunks (
                chunk_id, repo, root, path, language, kind, symbol, modified_at,
                file_hash, index_schema, embedding_model, chunker, chunk_index,
                start_line, end_line, content
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "c2",
                "dotfiles",
                "/tmp/dotfiles",
                "docs/notes.md",
                "markdown",
                "docs",
                "",
                1.0,
                "hash2",
                "rag-v4",
                config["embedding_model"],
                "semantic-lines-v4",
                0,
                1,
                10,
                "General note about tab switching and overview behavior",
            ),
        )
        conn.execute(
            """
            INSERT INTO facts (fact_id, repo, path, kind, key, value, line, confidence, source, file_hash, updated_at)
            VALUES ('f1', 'dotfiles', 'hypr/hyprland.conf', 'keybind', 'SUPER+TAB', 'exec scratchpad-overview', 42, 1.0, 'extractor', 'hash1', 1.0)
            """
        )
        conn.commit()
        plan = build_retrieval_plan("super tab overview", "dotfiles")
        candidates = RetrievalCandidates(
            plan=plan,
            semantic_ids=["c2", "c1"],
            keyword_ids=[],
            recent_ids=[],
            facts=list(
                conn.execute("SELECT * FROM facts WHERE repo = 'dotfiles'").fetchall()
            ),
            summaries=[],
            memory=None,
        )
        result = rank_retrieval_candidates(conn, config, candidates, use_reranker=True)
        self.assertEqual(result.rows[0]["chunk_id"], "c1")


if __name__ == "__main__":
    unittest.main()
