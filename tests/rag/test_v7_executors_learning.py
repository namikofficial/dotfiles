from __future__ import annotations

import sqlite3
import sys
import unittest
from pathlib import Path


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.executors import get_executor
from rag.learning import create_memory_candidate, list_memory_candidates, review_memory_candidate
from rag.storage import ensure_db


def make_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


class V7ExecutorsLearningTest(unittest.TestCase):
    def test_builtin_executors_are_available(self) -> None:
        for executor_id in ("local-answer", "copy", "file"):
            ok, reason = get_executor(executor_id).available()
            self.assertTrue(ok, reason)

    def test_memory_candidate_lifecycle_requires_review(self) -> None:
        conn = make_connection()
        candidate_id = create_memory_candidate(
            conn,
            kind="preference",
            content="User prefers one public rag command.",
            confidence=0.9,
        )
        rows = list_memory_candidates(conn)
        self.assertEqual(rows[0]["id"], candidate_id)
        self.assertEqual(rows[0]["status"], "pending")
        self.assertTrue(review_memory_candidate(conn, candidate_id, "accepted"))
        accepted = list_memory_candidates(conn, status="accepted")
        self.assertEqual(accepted[0]["id"], candidate_id)


if __name__ == "__main__":
    unittest.main()
