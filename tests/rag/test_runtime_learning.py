from __future__ import annotations

import asyncio
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from contextlib import contextmanager
from unittest.mock import patch


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag import mcp_server
from rag.profiles import init_repo_profile, load_repo_profile, save_repo_profile, validate_repo_profile
from rag.state import (
    get_retrieval_run,
    record_retrieval_outcome,
    record_retrieval_run,
    retrieval_run_payload,
)
from rag.storage import ensure_db


def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


@contextmanager
def _db_ctx(conn: sqlite3.Connection):
    yield conn


class RuntimeLearningTest(unittest.TestCase):
    def test_retrieval_run_export_and_payload_are_redacted(self) -> None:
        conn = make_connection()
        with tempfile.TemporaryDirectory() as tmp:
            payload = record_retrieval_run(
                conn,
                run_id="run-1",
                repo="dotfiles",
                branch="main",
                query="use sk-live-secret in auth",
                mode="agent",
                intent="general",
                plan={"query": "use sk-live-secret in auth"},
                rewrites=["use sk-live-secret in auth"],
                candidate_counts={"semantic": 3},
                selected_files=["system/rag/cli.py"],
                edit_scope={"likely_edit": [{"path": "system/rag/cli.py", "reason": "top hit"}]},
                missing_context={"missing": ["test file"]},
                packed_context_token_estimate=1200,
                timings_ms={"semantic": 12.5},
                warnings=["Authorization: Bearer sk-live-secret"],
                metadata={"suggested_commands": ["python -m unittest discover -s tests/rag -p 'test_*.py'"]},
                export_root=Path(tmp),
            )
            exported = Path(tmp) / ".agent" / "rag-runs" / "run-1.json"
            self.assertTrue(exported.exists())
            self.assertNotIn("sk-live-secret", exported.read_text())
            self.assertNotIn("sk-live-secret", json.dumps(payload))
            row = get_retrieval_run(conn, "run-1")
            self.assertIsNotNone(row)
            self.assertEqual(retrieval_run_payload(row)["run_id"], "run-1")
        conn.close()

    def test_retrieval_outcome_tracks_missed_files_and_cache(self) -> None:
        conn = make_connection()
        record_retrieval_outcome(
            conn,
            repo="dotfiles",
            task="fix auth flow",
            retrieved_files=["system/rag/cli.py"],
            edited_files=["system/rag/cli.py", "system/rag/mcp_server.py"],
            checks_run=["python -m unittest discover -s tests/rag -p 'test_*.py'"],
            passed=True,
            notes="no secrets",
            run_id="run-2",
        )
        outcome = conn.execute("SELECT missed_files_json FROM retrieval_outcomes LIMIT 1").fetchone()
        self.assertIn("system/rag/mcp_server.py", outcome["missed_files_json"])
        cache_kinds = {
            row["kind"]
            for row in conn.execute("SELECT kind FROM retrieval_cache").fetchall()
        }
        self.assertIn("edited", cache_kinds)
        self.assertIn("missed", cache_kinds)
        conn.close()

    def test_repo_profile_file_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path, profile = init_repo_profile(root)
            self.assertTrue(path.exists())
            profile["boost_paths"].append("system/rag/cli.py")
            save_repo_profile(profile, root)
            loaded = load_repo_profile(root)
            self.assertIn("system/rag/cli.py", loaded["boost_paths"])
            self.assertEqual(validate_repo_profile(loaded), [])

    def test_mcp_tool_list_includes_new_runtime_tools(self) -> None:
        tools = asyncio.run(mcp_server._list_tools())
        names = {tool.name for tool in tools}
        self.assertIn("rag_edit_scope", names)
        self.assertIn("rag_record_outcome", names)
        self.assertIn("rag_eval_query", names)
        self.assertIn("rag_perf_report", names)
        self.assertIn("rag_should_use_graph", names)
        self.assertIn("rag_task_continue", names)

    def test_mcp_record_outcome_returns_hit_rate_score(self) -> None:
        conn = make_connection()
        with patch("rag.mcp_server.db_conn", side_effect=lambda: _db_ctx(conn)), patch(
            "rag.mcp_server.record_outcome", return_value=123
        ):
            parsed = mcp_server._record_outcome_payload(
                {
                    "task": "fix auth flow",
                    "retrieved_files": ["a.py"],
                    "edited_files": ["a.py", "b.py"],
                    "checks_run": ["pytest -q"],
                    "passed": False,
                }
            )
        self.assertIn("score", parsed)
        self.assertEqual(parsed["score"]["missed_file_count"], 1)


if __name__ == "__main__":
    unittest.main()
