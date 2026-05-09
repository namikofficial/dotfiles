from __future__ import annotations

import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SYSTEM_DIR = Path(__file__).resolve().parents[2] / "system"
sys.path.insert(0, str(SYSTEM_DIR))

from rag.memory import write_context_pack_file
from rag.state import (
    add_command,
    add_error,
    add_test_failure,
    compact_session,
    record_session,
    redact_sensitive_text,
    save_handoff,
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


class SecurityRedactionTest(unittest.TestCase):
    def test_redact_sensitive_text_masks_common_secret_shapes(self) -> None:
        payload = """
Authorization: Bearer sk-live-1234567890
Cookie: sessionid=abcdef
DATABASE_URL=postgres://user:supersecret@db.local/app
token=ghp_ABCDEF1234567890
-----BEGIN PRIVATE KEY-----
abc
-----END PRIVATE KEY-----
"""
        redacted = redact_sensitive_text(payload)
        self.assertNotIn("sk-live-1234567890", redacted)
        self.assertNotIn("sessionid=abcdef", redacted)
        self.assertNotIn("supersecret", redacted)
        self.assertNotIn("ghp_ABCDEF1234567890", redacted)
        self.assertIn("<redacted>", redacted)
        self.assertIn("<redacted-private-key>", redacted)

    def test_state_memory_writes_store_redacted_values(self) -> None:
        conn = make_connection()
        add_command(
            conn,
            "dotfiles",
            "DATABASE_URL=postgres://user:pass@db.local/app npm run migrate",
            purpose="Use token sk-live-abcdef",
        )
        add_error(
            conn,
            "dotfiles",
            'Authorization: Bearer sk-live-abcdef\nCookie: auth=abc123',
            fix_text="Set API_KEY=secret-value",
            command="curl -H 'Authorization: Bearer sk-live-abcdef' /health",
        )
        add_test_failure(
            conn,
            "dotfiles",
            "pytest tests/rag/test_retrieval.py",
            "AssertionError token=ghp_ABCDEF1234567890 at tests/rag/test_retrieval.py:12",
        )
        upsert_git_context(
            conn,
            "dotfiles",
            "main",
            head_commit="abc123",
            indexed_branch="main",
            indexed_commit="abc123",
            dirty=True,
            status_short=" M .env",
            diff_text="API_KEY=topsecret",
            staged_diff_text="COOKIE=value",
            recent_log_text="fix auth token",
            changed_files=[".env", "scripts/deploy.sh"],
        )
        upsert_github_context(
            conn,
            "dotfiles",
            "pr",
            99,
            "Auth fixes",
            body="Authorization: Bearer sk-live-abcdef",
            comments=["DATABASE_URL=postgres://user:pass@db.local/app"],
            review_comments=["cookie: abc123"],
            ci_logs_text="token=ghp_ABCDEF1234567890",
        )

        command_row = conn.execute("SELECT command, purpose FROM command_memory LIMIT 1").fetchone()
        self.assertNotIn("postgres://user:pass@", command_row["command"])
        self.assertNotIn("sk-live-abcdef", command_row["purpose"])

        error_row = conn.execute("SELECT error_text, fix_text, command FROM error_memory LIMIT 1").fetchone()
        self.assertNotIn("sk-live-abcdef", error_row["error_text"])
        self.assertNotIn("secret-value", error_row["fix_text"])
        self.assertNotIn("sk-live-abcdef", error_row["command"])

        failure_row = conn.execute("SELECT output_text FROM test_failure_memory LIMIT 1").fetchone()
        self.assertNotIn("ghp_ABCDEF1234567890", failure_row["output_text"])

        git_row = conn.execute("SELECT diff_text, staged_diff_text FROM git_context LIMIT 1").fetchone()
        self.assertNotIn("topsecret", git_row["diff_text"])
        self.assertNotIn("COOKIE=value", git_row["staged_diff_text"])

        gh_row = conn.execute("SELECT body, comments_json, ci_logs_text FROM github_context LIMIT 1").fetchone()
        self.assertNotIn("sk-live-abcdef", gh_row["body"])
        self.assertNotIn("postgres://user:pass@", gh_row["comments_json"])
        self.assertNotIn("ghp_ABCDEF1234567890", gh_row["ci_logs_text"])
        conn.close()

    def test_session_compaction_and_handoff_are_redacted(self) -> None:
        conn = make_connection()
        session_id = record_session(
            conn,
            "dotfiles",
            "agent",
            "prepare handoff using token sk-live-abcdef",
            "manual",
            "handoff",
            'Run `curl -H "Authorization: Bearer sk-live-abcdef"`\nerror: DATABASE_URL=postgres://user:pass@host/db',
            ["system/rag/cli.py:1-20"],
        )
        compact_row = compact_session(conn, session_id)
        self.assertIsNotNone(compact_row)
        if compact_row is None:
            self.fail("expected compacted row")
        details = session_compaction_details(compact_row)
        joined = "\n".join(details.get("commands", []) + details.get("errors", []))
        self.assertNotIn("sk-live-abcdef", joined)
        self.assertNotIn("postgres://user:pass@", joined)

        with tempfile.TemporaryDirectory() as tmp:
            with patch("rag.state.RAG_HOME", Path(tmp)):
                handoff_path = save_handoff(
                    "dotfiles",
                    "prepare handoff sk-live-abcdef",
                    "Authorization: Bearer sk-live-abcdef",
                )
            text = handoff_path.read_text()
            self.assertNotIn("sk-live-abcdef", text)
        conn.close()

    def test_context_pack_file_is_redacted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            path = write_context_pack_file(
                root,
                "security",
                "DATABASE_URL=postgres://user:pass@db.local/app\nAuthorization: Bearer sk-live-abcdef",
            )
            text = path.read_text()
            self.assertNotIn("postgres://user:pass@", text)
            self.assertNotIn("sk-live-abcdef", text)


if __name__ == "__main__":
    unittest.main()
