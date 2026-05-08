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
    recent_hits,
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

    def test_build_retrieval_plan_expands_symbol_query_and_fixes_typos(self) -> None:
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
                "/workspace/dotfiles",
                "src/auth/auth-service.ts",
                "typescript",
                "code",
                "AuthService.login",
                50.0,
                "hash-auth",
                "rag-v4",
                config["embedding_model"],
                "semantic-lines-v4",
                0,
                1,
                20,
                "export class AuthService { login() {} }",
            ),
        )
        conn.commit()
        plan = build_retrieval_plan("AuthSvc.lgin cfg", "dotfiles", config=config, conn=conn)
        self.assertEqual(plan.intent, "symbol")
        self.assertIn("service", plan.analysis.expanded_terms)
        self.assertIn("login", plan.analysis.corrected_terms)
        self.assertIn("config", plan.analysis.expanded_terms)
        self.assertTrue(any("service" in rewrite and "login" in rewrite for rewrite in plan.rewrites))

    def test_fact_hits_boosts_config_facts_for_dev_query(self) -> None:
        conn = make_connection()
        config = copy.deepcopy(DEFAULT_CONFIG)
        conn.execute(
            """
            INSERT INTO facts (fact_id, repo, path, kind, key, value, line, confidence, source, file_hash, updated_at)
            VALUES
                ('f1', 'dotfiles', 'configs/app.yaml', 'config-key', 'database.pool.max', '24', 8, 1.0, 'extractor', 'hash1', 10.0),
                ('f2', 'dotfiles', 'docs/database.md', 'sql-object', 'pooling', 'overview', 3, 1.0, 'extractor', 'hash2', 10.0)
            """
        )
        conn.commit()
        plan = build_retrieval_plan("db cfg pool", "dotfiles", config=config, conn=conn)
        rows = fact_hits(conn, plan, config)
        self.assertEqual(plan.intent, "config")
        self.assertEqual(rows[0]["kind"], "config-key")
        self.assertEqual(rows[0]["path"], "configs/app.yaml")

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

    def test_recent_hits_prefers_path_match_over_fresher_noise(self) -> None:
        conn = make_connection()
        config = copy.deepcopy(DEFAULT_CONFIG)
        rows = [
            (
                "c1",
                "dotfiles",
                "/workspace/dotfiles",
                "src/auth/auth-service.ts",
                "typescript",
                "code",
                "AuthService.login",
                10.0,
                "hash1",
                "rag-v4",
                config["embedding_model"],
                "semantic-lines-v4",
                0,
                1,
                20,
                "export class AuthService { login() {} }",
            ),
            (
                "c2",
                "dotfiles",
                "/workspace/dotfiles",
                "notes/today.md",
                "markdown",
                "docs",
                "",
                100.0,
                "hash2",
                "rag-v4",
                config["embedding_model"],
                "semantic-lines-v4",
                0,
                1,
                10,
                "Recent note about unrelated chores",
            ),
        ]
        conn.executemany(
            """
            INSERT INTO chunks (
                chunk_id, repo, root, path, language, kind, symbol, modified_at,
                file_hash, index_schema, embedding_model, chunker, chunk_index,
                start_line, end_line, content
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            rows,
        )
        conn.commit()
        plan = build_retrieval_plan("auth service ts", "dotfiles", config=config, conn=conn)
        self.assertEqual(recent_hits(conn, config, plan)[0], "c1")

    def test_rank_retrieval_candidates_promotes_symbol_and_file_type_match(self) -> None:
        conn = make_connection()
        config = copy.deepcopy(DEFAULT_CONFIG)
        conn.executemany(
            """
            INSERT INTO chunks (
                chunk_id, repo, root, path, language, kind, symbol, modified_at,
                file_hash, index_schema, embedding_model, chunker, chunk_index,
                start_line, end_line, content
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    "c1",
                    "dotfiles",
                    "/workspace/dotfiles",
                    "src/auth/auth-service.ts",
                    "typescript",
                    "code",
                    "AuthService.login",
                    10.0,
                    "hash-ts",
                    "rag-v4",
                    config["embedding_model"],
                    "semantic-lines-v4",
                    0,
                    1,
                    20,
                    "export class AuthService { login() { return token; } }",
                ),
                (
                    "c2",
                    "dotfiles",
                    "/workspace/dotfiles",
                    "docs/auth-login.md",
                    "markdown",
                    "docs",
                    "",
                    80.0,
                    "hash-md",
                    "rag-v4",
                    config["embedding_model"],
                    "semantic-lines-v4",
                    0,
                    1,
                    14,
                    "Auth login design notes and historical overview",
                ),
            ],
        )
        conn.execute(
            """
            INSERT INTO file_summaries (repo, path, file_hash, language, kind, summary, symbols, facts_count, updated_at)
            VALUES ('dotfiles', 'src/auth/auth-service.ts', 'hash-ts', 'typescript', 'code', 'Auth service for login flow', 'AuthService.login', 1, 20.0)
            """
        )
        conn.commit()
        plan = build_retrieval_plan("AuthService login ts", "dotfiles", config=config, conn=conn)
        candidates = RetrievalCandidates(
            plan=plan,
            semantic_ids=["c2", "c1"],
            keyword_ids=[],
            recent_ids=[],
            facts=[],
            summaries=list(conn.execute("SELECT * FROM file_summaries").fetchall()),
            memory=None,
        )
        result = rank_retrieval_candidates(conn, config, candidates, use_reranker=True)
        self.assertEqual(result.rows[0]["chunk_id"], "c1")


if __name__ == "__main__":
    unittest.main()
