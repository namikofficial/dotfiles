from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path
from unittest.mock import patch


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.server import handle_tool
from rag.state import add_command, add_error, remember_memory
from rag.storage import ensure_db


def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


class V7ServerContractsTest(unittest.TestCase):
    def test_memory_and_recent_state_tools_return_json_shapes(self) -> None:
        conn = make_connection()
        remember_memory(conn, "dotfiles", "developer_preferences", "cli ux", "one public rag command")
        add_command(conn, "dotfiles", "rag --plan test", purpose="contract check")
        add_error(conn, "dotfiles", "database is locked", fix_text="retry later")

        with patch("rag.server.connect_db", return_value=conn):
            memory = handle_tool("memory", {"repo": "dotfiles"})
            commands = handle_tool("recent-commands", {"repo": "dotfiles"})
            errors = handle_tool("recent-errors", {"repo": "dotfiles"})

        self.assertEqual(memory["memories"][0]["kind"], "developer_preferences")
        self.assertEqual(commands["commands"][0]["command"], "rag --plan test")
        self.assertEqual(errors["errors"][0]["message"], "database is locked")


if __name__ == "__main__":
    unittest.main()
