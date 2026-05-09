from __future__ import annotations

import json
import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.cli import build_parser, route_mode, suggestion_for_argparse_error, workflow_keys_for_query
from rag.memory import build_context_pack
from rag.retrieval import gather_context
from rag.settings import DEFAULT_CONFIG, get_mode_profile
from rag.state import (
    add_command,
    add_decision,
    add_error,
    add_test_failure,
    add_todo,
    compact_session,
    detect_memory_conflicts,
    format_operational_state,
    list_memory_entries,
    load_operational_state,
    normalize_error_text,
    record_session,
    remember_memory,
    session_compaction_details,
    upsert_github_context,
    upsert_git_context,
)
from rag.storage import ensure_db



def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


class CliStateTest(unittest.TestCase):
    def test_route_mode_prefers_agent_for_handoff_requests(self) -> None:
        mode, reason = route_mode("prepare Codex handoff for the RAG CLI migration")
        self.assertEqual(mode, "agent")
        self.assertIn("handoff", reason)

    def test_build_parser_supports_mode_surfaces(self) -> None:
        parser = build_parser()
        self.assertEqual(parser.parse_args(["quick", "explain config"]).command, "quick")
        self.assertEqual(parser.parse_args(["deep", "review this flow"]).command, "deep")
        ask_args = parser.parse_args(["ask", "--mode", "agent", "prepare context"])
        self.assertEqual(ask_args.mode, "agent")
        handoff_args = parser.parse_args(["handoff", "codex", "prepare context"])
        self.assertEqual(handoff_args.command, "handoff")
        self.assertEqual(handoff_args.target, "codex")
        context_git_args = parser.parse_args(["context", "git", "--refresh"])
        self.assertEqual(context_git_args.context_command, "git")
        context_failure_args = parser.parse_args(
            ["context", "test-failure", "add", "pytest -q", "--output", "AssertionError"]
        )
        self.assertEqual(context_failure_args.failure_command, "add")
        suggest_args = parser.parse_args(["suggest", "debug"])
        self.assertEqual(suggest_args.command, "suggest")
        self.assertEqual(suggest_args.query, "debug")
        memory_args = parser.parse_args(
            ["memory", "remember", "known_stack", "backend", "node", "nest", "--global-scope"]
        )
        self.assertEqual(memory_args.memory_command, "remember")
        self.assertTrue(memory_args.global_scope)

    def test_cli_suggestions_for_typos_and_workflows(self) -> None:
        message = "argument command: invalid choice: 'serach' (choose from 'index', 'search', 'status')"
        self.assertEqual(suggestion_for_argparse_error(message), "search")
        self.assertIn("debug", workflow_keys_for_query("debug retrieval misses"))
        self.assertIn("memory", workflow_keys_for_query("remember project facts"))

    def test_gather_context_includes_operational_state(self) -> None:
        config = get_mode_profile(DEFAULT_CONFIG, "deep")
        context, files = gather_context(
            [],
            config,
            operational_state="## Todos\n- [open] Refresh retrieval docs",
            operational_state_tokens=400,
            memory="Repo summary",
        )
        self.assertIn("<operational_state>", context)
        self.assertIn("<repo_memory>", context)
        self.assertEqual(files, [])

    def test_state_helpers_round_trip(self) -> None:
        conn = make_connection()
        add_todo(conn, "dotfiles", "Add agent mode", detail="Ship explicit CLI surfaces")
        add_decision(conn, "dotfiles", "Use explicit modes", "Keep ask as compatibility alias")
        add_command(conn, "dotfiles", "python -m unittest tests.rag.test_retrieval", purpose="RAG regression check")
        add_error(
            conn,
            "dotfiles",
            "database is locked at src/db.py:42",
            fix_text="Retry after the active run finishes",
            command="pytest tests/rag/test_retrieval.py",
            exit_code=1,
        )
        add_test_failure(
            conn,
            "dotfiles",
            "pytest tests/rag/test_retrieval.py",
            "AssertionError: expected 1 == 2\n at RetrievalTest.test_case tests/rag/test_retrieval.py:88",
            runner="pytest",
            exit_code=1,
        )
        upsert_github_context(
            conn,
            "dotfiles",
            "pr",
            42,
            "Improve retrieval diagnostics",
            body="Adds debug output for context sources",
            changed_files=["system/rag/retrieval.py"],
            comments=["Looks good overall"],
        )
        upsert_git_context(
            conn,
            "dotfiles",
            "feature/retrieval",
            head_commit="abc123",
            indexed_branch="main",
            indexed_commit="def456",
            dirty=True,
            status_short=" M system/rag/retrieval.py",
            diff_text="+ new explain output",
            staged_diff_text="",
            recent_log_text="abc123 Improve retrieval diagnostics",
            changed_files=["system/rag/retrieval.py"],
        )
        remember_memory(conn, None, "known_stack", "backend", "Node NestJS MikroORM Postgres", global_scope=True)
        remember_memory(conn, "dotfiles", "repo_conventions", "handoffs", "Prefer concise markdown handoffs")
        session_id = record_session(
            conn,
            "dotfiles",
            "deep",
            "review retrieval routing",
            "matched analysis/debug depth heuristics",
            "answer",
            "Grounded answer\nUse `rag memory pack dotfiles --write-file`\nerror: database is locked | fix: retry",
            ["dotfiles/system/rag/cli.py:1-20"],
        )
        compact_row = compact_session(conn, session_id)
        self.assertIsNotNone(compact_row)
        if compact_row is None:
            self.fail("session compaction should exist")
        details = session_compaction_details(compact_row)
        self.assertIn("rag memory pack dotfiles --write-file", details["commands"][0])
        state = format_operational_state(load_operational_state(conn, "dotfiles"))
        self.assertIn("Add agent mode", state)
        self.assertIn("Use explicit modes", state)
        self.assertIn("database is locked", state)
        self.assertIn("Test failures", state)
        self.assertIn("GitHub context", state)
        self.assertIn("Git context", state)
        self.assertIn("Known stack", state)
        self.assertIn("Repo conventions", state)
        self.assertIn("Session compactions", state)
        self.assertIn(session_id, state)

    def test_memory_conflicts_and_context_pack(self) -> None:
        conn = make_connection()
        conn.execute(
            "INSERT INTO indexed_repos (repo, root, last_indexed) VALUES (?, ?, ?)",
            ("dotfiles", "/repo/dotfiles", 10.0),
        )
        conn.execute(
            """
            INSERT INTO repo_memory (
                repo, root, summary, architecture, important_paths, conventions,
                updated_at, index_schema, source_chunk_count, summary_commit,
                changed_files_json, changed_symbols_json, freshness_score
            ) VALUES (?, ?, ?, NULL, NULL, NULL, ?, ?, ?, ?, '[]', '[]', ?)
            """,
            ("dotfiles", "/repo/dotfiles", "# Repo summary\nStable repo memory", 10.0, "rag-v4", 5, "abc123", 1.0),
        )
        remember_memory(conn, "dotfiles", "repo_conventions", "network", "uses iwd")
        remember_memory(conn, "dotfiles", "repo_conventions", "network", "NetworkManager + wpa_supplicant")
        conflicts = detect_memory_conflicts(conn, "dotfiles")
        self.assertEqual(len(conflicts), 1)
        rows = list_memory_entries(conn, "dotfiles", kind="repo_conventions", status="all")
        by_value = {row["value"]: row["status"] for row in rows}
        self.assertEqual(by_value["NetworkManager + wpa_supplicant"], "active")
        self.assertIn(by_value["uses iwd"], {"stale", "conflict"})
        remember_memory(conn, None, "known_stack", "backend", "node nest mikro-orm postgres", global_scope=True)
        content, metadata = build_context_pack(conn, "dotfiles", "backend", agent_target="codex")
        self.assertIn("# Context pack: backend", content)
        self.assertIn("## Repo memory", content)
        self.assertIn("## Repo conventions", content)
        self.assertIn("## Tool taxonomy", content)
        self.assertTrue(metadata["has_repo_memory"])

    def test_error_normalization_ignores_line_numbers(self) -> None:
        first = normalize_error_text("RuntimeError: boom at src/app.py:12")
        second = normalize_error_text("RuntimeError: boom at src/app.py:48")
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
