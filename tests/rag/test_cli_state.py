from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.cli import build_parser, route_mode
from rag.retrieval import gather_context
from rag.settings import DEFAULT_CONFIG, get_mode_profile
from rag.state import add_command, add_decision, add_error, add_todo, format_operational_state, record_session
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
        add_error(conn, "dotfiles", "database is locked", fix_text="Retry after the active run finishes")
        session_id = record_session(
            conn,
            "dotfiles",
            "deep",
            "review retrieval routing",
            "matched analysis/debug depth heuristics",
            "answer",
            "Grounded answer",
            ["dotfiles/system/rag/cli.py:1-20"],
        )
        state = format_operational_state(
            {
                "todos": conn.execute("SELECT * FROM task_todos").fetchall(),
                "decisions": conn.execute("SELECT * FROM task_decisions").fetchall(),
                "commands": conn.execute("SELECT * FROM command_memory").fetchall(),
                "errors": conn.execute("SELECT * FROM error_memory").fetchall(),
                "sessions": conn.execute("SELECT * FROM task_sessions").fetchall(),
            }
        )
        self.assertIn("Add agent mode", state)
        self.assertIn("Use explicit modes", state)
        self.assertIn("database is locked", state)
        self.assertIn(session_id, state)


if __name__ == "__main__":
    unittest.main()
