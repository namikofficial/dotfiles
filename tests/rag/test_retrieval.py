from __future__ import annotations

import copy
import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.retrieval import (
    ContextSource,
    RetrievalCandidates,
    build_retrieval_plan,
    fact_hits,
    fts_match_terms,
    gather_context,
    rank_retrieval_candidates,
    reciprocal_rank_fusion,
    rewrite_queries,
)
from rag.settings import DEFAULT_CONFIG
from rag.state import add_error, add_test_failure, remember_memory, upsert_github_context, upsert_git_context
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
            VALUES ('f1', 'dotfiles', 'hypr/hyprland.lua', 'keybind', 'SUPER+TAB', 'exec overview', 42, 1.0, 'extractor', 'abc', 1.0)
            """
        )
        conn.commit()
        plan = build_retrieval_plan("super tab", "dotfiles")
        rows = fact_hits(conn, plan, copy.deepcopy(DEFAULT_CONFIG))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["path"], "hypr/hyprland.lua")

    def test_build_retrieval_plan_expands_with_memory_and_taxonomy(self) -> None:
        conn = make_connection()
        remember_memory(conn, None, "known_stack", "backend", "node nest mikro-orm postgres", global_scope=True)
        plan = build_retrieval_plan("backend auth service", "dotfiles", config=copy.deepcopy(DEFAULT_CONFIG), conn=conn)
        self.assertIn("node", plan.analysis.expanded_terms)
        self.assertIn("nest", plan.analysis.expanded_terms)

    def test_fts_match_terms_strips_match_breaking_punctuation(self) -> None:
        match = fts_match_terms(["repo.", "AuthService.login", "config-trace"])
        self.assertEqual(match, "repo OR AuthService OR login OR config OR trace")

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
                "hypr/hyprland.lua",
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
                'hl.bind("SUPER + TAB", hl.dsp.exec_cmd("scratchpad-overview"))',
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
            VALUES ('f1', 'dotfiles', 'hypr/hyprland.lua', 'keybind', 'SUPER+TAB', 'exec scratchpad-overview', 42, 1.0, 'extractor', 'hash1', 1.0)
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

    def test_rank_retrieval_candidates_adds_context_sources_and_missing_context(self) -> None:
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
                "svc1",
                "dotfiles",
                "/repo/dotfiles",
                "src/auth_service.py",
                "python",
                "code",
                "AuthService.run",
                10.0,
                "hash-auth",
                "rag-v4",
                config["embedding_model"],
                "semantic-lines-v4",
                0,
                1,
                40,
                "class AuthService:\n    def run(self):\n        raise RuntimeError('boom')\n",
            ),
        )
        conn.execute(
            """
            INSERT INTO file_summaries (
                repo, path, package, file_hash, language, kind, summary, symbols, facts_count, updated_at
            ) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "dotfiles",
                "tests/test_auth_service.py",
                "hash-test",
                "python",
                "code",
                "Regression tests for AuthService failures",
                "test_auth_service",
                0,
                11.0,
            ),
        )
        conn.execute(
            """
            INSERT INTO file_summaries (
                repo, path, package, file_hash, language, kind, summary, symbols, facts_count, updated_at
            ) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "dotfiles",
                "docs/auth-service.md",
                "hash-docs",
                "markdown",
                "docs",
                "AuthService troubleshooting notes and error docs",
                "AuthService",
                0,
                12.0,
            ),
        )
        conn.execute(
            """
            INSERT INTO file_dependencies (
                edge_id, repo, source_path, package, package_root, dependency, dependency_kind,
                target_path, line, is_export, is_internal, file_hash, updated_at
            ) VALUES (?, ?, ?, NULL, NULL, ?, ?, ?, ?, 0, 1, ?, ?)
            """,
            (
                "edge1",
                "dotfiles",
                "tests/test_auth_service.py",
                "AuthService.run",
                "import",
                "src/auth_service.py",
                4,
                "dep-hash",
                13.0,
            ),
        )
        upsert_git_context(
            conn,
            "dotfiles",
            "feature/auth",
            head_commit="abc123",
            indexed_branch="main",
            indexed_commit="999999",
            dirty=True,
            status_short=" M src/auth_service.py",
            diff_text="diff --git a/src/auth_service.py b/src/auth_service.py\n+raise RuntimeError('boom')",
            staged_diff_text="",
            recent_log_text="abc123 fix auth",
            changed_files=["src/auth_service.py"],
        )
        upsert_github_context(
            conn,
            "dotfiles",
            "pr",
            12,
            "Fix AuthService failure",
            body="Tracks the failing AuthService.run path",
            changed_files=["src/auth_service.py", "tests/test_auth_service.py"],
            comments=["Please confirm the failing stack trace is covered."],
            review_comments=["Needs a regression test."],
            ci_logs_text="pytest tests/test_auth_service.py failed with RuntimeError",
            linked_issues=["#99"],
        )
        add_test_failure(
            conn,
            "dotfiles",
            "pytest tests/test_auth_service.py",
            "RuntimeError: boom\n  at AuthService.run src/auth_service.py:3\n",
            runner="pytest",
            exit_code=1,
        )
        add_error(
            conn,
            "dotfiles",
            "RuntimeError: boom\n  at AuthService.run src/auth_service.py:3\n",
            fix_text="Add the missing regression guard in AuthService.run",
            command="pytest tests/test_auth_service.py",
            exit_code=1,
        )
        conn.commit()
        plan = build_retrieval_plan(
            "Why is AuthService.run failing in PR #12?",
            "dotfiles",
            mode="deep",
            config=config,
            conn=conn,
        )
        git_row = conn.execute("SELECT * FROM git_context WHERE repo = 'dotfiles'").fetchone()
        candidates = RetrievalCandidates(
            plan=plan,
            semantic_ids=["svc1"],
            keyword_ids=[],
            recent_ids=[],
            facts=[],
            summaries=[],
            memory=None,
            git_context=git_row,
            github_refs=conn.execute("SELECT * FROM github_context").fetchall(),
            test_failures=conn.execute("SELECT * FROM test_failure_memory").fetchall(),
            error_matches=conn.execute("SELECT * FROM error_memory").fetchall(),
        )
        result = rank_retrieval_candidates(conn, config, candidates, use_reranker=True)
        source_types = [source.source_type for source in result.context_sources]
        self.assertIn("git", source_types)
        self.assertIn("github", source_types)
        self.assertIn("test_failure", source_types)
        self.assertIn("error", source_types)
        self.assertIn("missing_context", source_types)
        self.assertIn("caller file", result.debug["missing_context_added"])
        self.assertIn("test file", result.debug["missing_context_added"])
        self.assertIn("related docs", result.debug["missing_context_added"])
        context, files = gather_context(
            result.rows,
            config,
            summaries=result.summaries,
            context_sources=result.context_sources,
        )
        self.assertIn("<context_sources>", context)
        self.assertIn("Fix AuthService failure", context)
        self.assertIn("feature/auth", context)
        self.assertIn("tests/test_auth_service.py", "\n".join(files))


if __name__ == "__main__":
    unittest.main()
