from __future__ import annotations

import json
import re
import sqlite3
import time
import uuid
from pathlib import Path

from .runtime import RAG_HOME


def _scope_clause(repo: str | None) -> tuple[str, list[object]]:
    if repo:
        return " WHERE repo = ?", [repo]
    return "", []


def add_todo(
    conn: sqlite3.Connection,
    repo: str | None,
    title: str,
    detail: str | None = None,
    status: str = "open",
    source_session_id: str | None = None,
) -> int:
    now = time.time()
    cursor = conn.execute(
        """
        INSERT INTO task_todos (repo, title, detail, status, source_session_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (repo, title.strip(), detail, status, source_session_id, now, now),
    )
    conn.commit()
    return int(cursor.lastrowid)


def list_todos(conn: sqlite3.Connection, repo: str | None, status: str | None, limit: int) -> list[sqlite3.Row]:
    clauses: list[str] = []
    params: list[object] = []
    if repo:
        clauses.append("repo = ?")
        params.append(repo)
    if status and status != "all":
        clauses.append("status = ?")
        params.append(status)
    sql = "SELECT * FROM task_todos"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY CASE status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END, updated_at DESC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()


def update_todo_status(conn: sqlite3.Connection, todo_id: int, status: str) -> bool:
    cursor = conn.execute(
        "UPDATE task_todos SET status = ?, updated_at = ? WHERE todo_id = ?",
        (status, time.time(), todo_id),
    )
    conn.commit()
    return cursor.rowcount > 0


def add_decision(
    conn: sqlite3.Connection,
    repo: str | None,
    title: str,
    detail: str,
    rationale: str | None = None,
    source_session_id: str | None = None,
) -> int:
    now = time.time()
    cursor = conn.execute(
        """
        INSERT INTO task_decisions (repo, title, detail, rationale, source_session_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (repo, title.strip(), detail.strip(), rationale, source_session_id, now, now),
    )
    conn.commit()
    return int(cursor.lastrowid)


def list_decisions(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM task_decisions{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def add_command(
    conn: sqlite3.Connection,
    repo: str | None,
    command: str,
    purpose: str | None = None,
    notes: str | None = None,
    source_session_id: str | None = None,
) -> int:
    now = time.time()
    cursor = conn.execute(
        """
        INSERT INTO command_memory (repo, command, purpose, notes, source_session_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (repo, command.strip(), purpose, notes, source_session_id, now, now),
    )
    conn.commit()
    return int(cursor.lastrowid)


def list_commands(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM command_memory{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def add_error(
    conn: sqlite3.Connection,
    repo: str | None,
    error_text: str,
    fix_text: str | None = None,
    notes: str | None = None,
    source_session_id: str | None = None,
) -> int:
    now = time.time()
    cursor = conn.execute(
        """
        INSERT INTO error_memory (repo, error_text, fix_text, notes, source_session_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (repo, error_text.strip(), fix_text, notes, source_session_id, now, now),
    )
    conn.commit()
    return int(cursor.lastrowid)


def list_errors(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM error_memory{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def record_session(
    conn: sqlite3.Connection,
    repo: str | None,
    mode: str,
    query: str,
    route_reason: str,
    output_kind: str,
    output_text: str,
    relevant_files: list[str],
) -> str:
    session_id = uuid.uuid4().hex[:12]
    now = time.time()
    conn.execute(
        """
        INSERT INTO task_sessions (
            session_id, repo, mode, query, route_reason, output_kind, output_text, relevant_files_json, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            session_id,
            repo,
            mode,
            query.strip(),
            route_reason,
            output_kind,
            output_text.strip(),
            json.dumps(relevant_files),
            now,
            now,
        ),
    )
    conn.commit()
    return session_id


def list_sessions(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM task_sessions{clause} ORDER BY created_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def get_session(conn: sqlite3.Connection, session_id: str) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM task_sessions WHERE session_id = ?", (session_id,)).fetchone()


def session_files(row: sqlite3.Row) -> list[str]:
    return json.loads(row["relevant_files_json"] or "[]")


def load_operational_state(conn: sqlite3.Connection, repo: str | None) -> dict[str, list[sqlite3.Row]]:
    return {
        "todos": list_todos(conn, repo, status="all", limit=6),
        "decisions": list_decisions(conn, repo, limit=6),
        "commands": list_commands(conn, repo, limit=6),
        "errors": list_errors(conn, repo, limit=6),
        "sessions": list_sessions(conn, repo, limit=4),
    }


def format_operational_state(state: dict[str, list[sqlite3.Row]]) -> str:
    sections: list[str] = []
    todos = state["todos"]
    if todos:
        sections.append(
            "## Todos\n"
            + "\n".join(
                f"- [{row['status']}] {row['title']}" + (f" — {row['detail']}" if row["detail"] else "")
                for row in todos
            )
        )
    decisions = state["decisions"]
    if decisions:
        sections.append(
            "## Decisions\n"
            + "\n".join(
                f"- {row['title']}: {row['detail']}" + (f" (why: {row['rationale']})" if row["rationale"] else "")
                for row in decisions
            )
        )
    commands = state["commands"]
    if commands:
        sections.append(
            "## Useful commands\n"
            + "\n".join(
                f"- `{row['command']}`" + (f" — {row['purpose']}" if row["purpose"] else "")
                for row in commands
            )
        )
    errors = state["errors"]
    if errors:
        sections.append(
            "## Errors and fixes\n"
            + "\n".join(
                f"- error: {row['error_text']}" + (f" | fix: {row['fix_text']}" if row["fix_text"] else "")
                for row in errors
            )
        )
    sessions = state["sessions"]
    if sessions:
        sections.append(
            "## Recent sessions\n"
            + "\n".join(f"- {row['session_id']} [{row['mode']}] {row['query']}" for row in sessions)
        )
    return "\n\n".join(sections)


def slugify(text: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug[:60] or "handoff"


def save_handoff(repo: str | None, goal: str, content: str) -> Path:
    scope = repo or "global"
    directory = RAG_HOME / "projects" / scope / "handoffs"
    directory.mkdir(parents=True, exist_ok=True)
    filename = f"{time.strftime('%Y%m%d-%H%M%S')}-{slugify(goal)}.md"
    path = directory / filename
    path.write_text(content.rstrip() + "\n")
    return path
