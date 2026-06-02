from __future__ import annotations

import json
import sqlite3
import time
import uuid

from .state import redact_sensitive_text


VALID_CANDIDATE_KINDS = {"convention", "error_fix", "preference", "command"}


def create_memory_candidate(
    conn: sqlite3.Connection,
    *,
    kind: str,
    content: str,
    evidence: list[dict] | None = None,
    confidence: float = 0.0,
    source_session_id: str | None = None,
) -> str:
    if kind not in VALID_CANDIDATE_KINDS:
        raise ValueError(f"unsupported memory candidate kind: {kind}")
    candidate_id = str(uuid.uuid4())
    now = time.time()
    conn.execute(
        """
        INSERT INTO memory_candidates (
            id, kind, content, evidence_json, confidence, status, source_session_id, created_at, reviewed_at
        ) VALUES (?, ?, ?, ?, ?, 'pending', ?, ?, NULL)
        """,
        (
            candidate_id,
            kind,
            redact_sensitive_text(content).strip(),
            json.dumps(evidence or []),
            confidence,
            source_session_id,
            now,
        ),
    )
    conn.commit()
    return candidate_id


def list_memory_candidates(
    conn: sqlite3.Connection,
    *,
    status: str = "pending",
    limit: int = 20,
) -> list[sqlite3.Row]:
    if status == "all":
        return conn.execute(
            "SELECT * FROM memory_candidates ORDER BY created_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
    return conn.execute(
        "SELECT * FROM memory_candidates WHERE status = ? ORDER BY created_at DESC LIMIT ?",
        (status, limit),
    ).fetchall()


def review_memory_candidate(conn: sqlite3.Connection, candidate_id: str, status: str, content: str | None = None) -> bool:
    if status not in {"accepted", "rejected", "edited"}:
        raise ValueError(f"unsupported candidate status: {status}")
    now = time.time()
    if content is None:
        cursor = conn.execute(
            "UPDATE memory_candidates SET status = ?, reviewed_at = ? WHERE id = ?",
            (status, now, candidate_id),
        )
    else:
        cursor = conn.execute(
            "UPDATE memory_candidates SET status = ?, content = ?, reviewed_at = ? WHERE id = ?",
            (status, redact_sensitive_text(content), now, candidate_id),
        )
    conn.commit()
    return cursor.rowcount > 0
