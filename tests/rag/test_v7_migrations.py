from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.storage import ensure_db


class V7MigrationsTest(unittest.TestCase):
    def test_v7_tables_and_migration_ledger_exist(self) -> None:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        ensure_db(conn)
        tables = {
            row["name"]
            for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'").fetchall()
        }
        self.assertIn("_schema_migrations", tables)
        self.assertIn("profiles", tables)
        self.assertIn("profile_usage", tables)
        self.assertIn("execution_runs", tables)
        self.assertIn("memory_candidates", tables)
        migrations = conn.execute("SELECT COUNT(*) AS count FROM _schema_migrations").fetchone()["count"]
        self.assertGreaterEqual(migrations, 4)

    def test_builtin_profiles_are_seeded(self) -> None:
        conn = sqlite3.connect(":memory:")
        conn.row_factory = sqlite3.Row
        ensure_db(conn)
        ids = {
            row["id"]
            for row in conn.execute("SELECT id FROM profiles").fetchall()
        }
        self.assertIn("rag-engineer", ids)
        self.assertIn("repo-review", ids)


if __name__ == "__main__":
    unittest.main()
