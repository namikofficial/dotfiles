from __future__ import annotations

import hashlib
import json
import re
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

from .runtime import RAG_HOME

MEMORY_KIND_LABELS = {
    "project_facts": "Project facts",
    "developer_preferences": "Developer preferences",
    "known_stack": "Known stack",
    "tool_preferences": "Tool preferences",
    "hardware_profile": "Hardware profile",
    "repo_conventions": "Repo conventions",
}
VALID_MEMORY_KINDS = tuple(MEMORY_KIND_LABELS)

REDACT_TOKEN_PATTERNS = (
    re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._\-+/=]{8,}"),
    re.compile(r"\bsk-[A-Za-z0-9-]{8,}\b"),
    re.compile(r"\b(?:sk|ghp|gho|ghu|github_pat)_[A-Za-z0-9_]{8,}\b"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
)
REDACT_HEADER_PATTERNS = (
    (re.compile(r"(?im)(authorization\s*:\s*)([^\n]+)"), r"\1<redacted>"),
    (re.compile(r"(?im)(cookie\s*:\s*)([^\n]+)"), r"\1<redacted>"),
    (re.compile(r"(?im)(set-cookie\s*:\s*)([^\n]+)"), r"\1<redacted>"),
)
REDACT_ENV_PATTERN = re.compile(
    r"(?im)\b([A-Z0-9_]*(?:TOKEN|SECRET|PASSWORD|PASSWD|API_KEY|ACCESS_KEY|PRIVATE_KEY|DATABASE_URL|COOKIE|SESSION|AUTH)[A-Z0-9_]*)\s*=\s*([^\s]+)"
)
REDACT_URL_CREDENTIAL_PATTERN = re.compile(
    r"([a-zA-Z][a-zA-Z0-9+.-]*://[^/\s:@]+):([^/\s@]+)@"
)
REDACT_DB_URL_PATTERN = re.compile(
    r"(?i)\b((?:postgres(?:ql)?|mysql|mongodb(?:\+srv)?|redis|mssql|amqp)://[^\s]+)"
)
REDACT_PRIVATE_KEY_BLOCK_PATTERN = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"
)


def _scope_clause(repo: str | None) -> tuple[str, list[object]]:
    if repo:
        return " WHERE repo = ?", [repo]
    return "", []



def _normalize_memory_subject(subject: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", subject.lower()).strip("-")
    return slug or "memory"


def redact_sensitive_text(text: str) -> str:
    if not text:
        return text
    redacted = text
    redacted = REDACT_PRIVATE_KEY_BLOCK_PATTERN.sub("<redacted-private-key>", redacted)
    for pattern, replacement in REDACT_HEADER_PATTERNS:
        redacted = pattern.sub(replacement, redacted)
    redacted = REDACT_ENV_PATTERN.sub(r"\1=<redacted>", redacted)
    redacted = REDACT_URL_CREDENTIAL_PATTERN.sub(r"\1:<redacted>@", redacted)

    def _redact_db_url(match: re.Match[str]) -> str:
        value = match.group(1)
        return REDACT_URL_CREDENTIAL_PATTERN.sub(r"\1:<redacted>@", value)

    redacted = REDACT_DB_URL_PATTERN.sub(_redact_db_url, redacted)
    for pattern in REDACT_TOKEN_PATTERNS:
        redacted = pattern.sub("<redacted-token>", redacted)
    return redacted


def _redact_optional(text: str | None) -> str | None:
    if text is None:
        return None
    return redact_sensitive_text(text)


def _redact_text_list(values: list[str]) -> list[str]:
    return [redact_sensitive_text(value) for value in values]


def _cursor_lastrowid(cursor: sqlite3.Cursor) -> int:
    row_id = cursor.lastrowid
    if row_id is None:
        raise RuntimeError("Expected sqlite cursor.lastrowid to be set")
    return int(row_id)


def record_execution_run(
    conn: sqlite3.Connection,
    *,
    run_id: str,
    session_id: str,
    repo: str | None,
    target: str,
    profile_id: str,
    intent: str,
    mode: str,
    risk_level: str,
    query: str,
    prompt_hash: str,
    agent_plan: dict[str, Any],
    status: str,
    stdout: str | None = None,
    stderr: str | None = None,
    exit_code: int | None = None,
    duration_ms: int | None = None,
    files_modified: list[str] | None = None,
    started_at: float | None = None,
    finished_at: float | None = None,
) -> None:
    now = time.time()
    conn.execute(
        """
        INSERT OR REPLACE INTO execution_runs (
            id, session_id, repo, target, profile_id, intent, mode, risk_level, query,
            prompt_hash, agent_plan_json, status, stdout, stderr, exit_code, duration_ms,
            files_modified, started_at, finished_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            session_id,
            repo,
            target,
            profile_id,
            intent,
            mode,
            risk_level,
            query,
            prompt_hash,
            json.dumps(agent_plan, sort_keys=True),
            status,
            _redact_optional(stdout),
            _redact_optional(stderr),
            exit_code,
            duration_ms,
            json.dumps(files_modified or []),
            started_at or now,
            finished_at,
        ),
    )
    conn.commit()



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
    return _cursor_lastrowid(cursor)



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
    return _cursor_lastrowid(cursor)



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
    redacted_command = redact_sensitive_text(command).strip()
    redacted_purpose = _redact_optional(purpose)
    redacted_notes = _redact_optional(notes)
    cursor = conn.execute(
        """
        INSERT INTO command_memory (repo, command, purpose, notes, source_session_id, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (repo, redacted_command, redacted_purpose, redacted_notes, source_session_id, now, now),
    )
    conn.commit()
    return _cursor_lastrowid(cursor)



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
    command: str | None = None,
    exit_code: int | None = None,
    source_session_id: str | None = None,
) -> int:
    now = time.time()
    redacted_error_text = redact_sensitive_text(error_text)
    redacted_fix_text = _redact_optional(fix_text)
    redacted_notes = _redact_optional(notes)
    redacted_command = _redact_optional(command)
    normalized_error = normalize_error_text(redacted_error_text)
    fingerprint_hash = fingerprint_error(normalized_error)
    stack_symbols = json.dumps(extract_stack_symbols(redacted_error_text))
    file_paths = json.dumps(extract_file_paths(redacted_error_text))
    cursor = conn.execute(
        """
        INSERT INTO error_memory (
            repo, error_text, fix_text, notes, normalized_error, fingerprint_hash,
            stack_symbols_json, file_paths_json, command, exit_code,
            source_session_id, created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo,
            redacted_error_text.strip(),
            redacted_fix_text,
            redacted_notes,
            normalized_error,
            fingerprint_hash,
            stack_symbols,
            file_paths,
            redacted_command,
            exit_code,
            source_session_id,
            now,
            now,
        ),
    )
    conn.commit()
    return _cursor_lastrowid(cursor)



def list_errors(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM error_memory{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()



def normalize_error_text(text: str) -> str:
    normalized = text.strip()
    normalized = re.sub(r"\b0x[0-9a-fA-F]+\b", "0x<hex>", normalized)
    normalized = re.sub(
        r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b",
        "<uuid>",
        normalized,
    )
    normalized = re.sub(r"\b(line|col(?:umn)?|position|errno|exit code)\s+\d+\b", r"\1 <n>", normalized, flags=re.I)
    normalized = re.sub(r"(?<=[:(])\d+(?=(?::\d+)?[)\s]|$)", "<n>", normalized)
    normalized = re.sub(r"\s+", " ", normalized)
    return normalized.strip().lower()



def fingerprint_error(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]



def extract_file_paths(text: str) -> list[str]:
    paths: list[str] = []
    for match in re.finditer(r"(?<![A-Za-z0-9_])([~./A-Za-z0-9_-][A-Za-z0-9_./-]*\.[A-Za-z0-9]{1,8})(?::\d+(?::\d+)?)?", text):
        path = match.group(1).strip()
        if "/" not in path and "." not in path:
            continue
        paths.append(path)
    return list(dict.fromkeys(paths))[:12]



def extract_stack_symbols(text: str) -> list[str]:
    symbols = [
        match.group(1)
        for match in re.finditer(r"\bat\s+([A-Za-z_][A-Za-z0-9_.$<>:#-]+)", text)
    ]
    return list(dict.fromkeys(symbols))[:12]



def upsert_git_context(
    conn: sqlite3.Connection,
    repo: str,
    branch: str,
    *,
    head_commit: str | None,
    indexed_branch: str | None,
    indexed_commit: str | None,
    dirty: bool,
    status_short: str,
    diff_text: str,
    staged_diff_text: str,
    recent_log_text: str,
    changed_files: list[str],
) -> None:
    now = time.time()
    redacted_status = redact_sensitive_text(status_short).strip()
    redacted_diff = redact_sensitive_text(diff_text).strip()
    redacted_staged_diff = redact_sensitive_text(staged_diff_text).strip()
    redacted_recent_log = redact_sensitive_text(recent_log_text).strip()
    redacted_changed_files = _redact_text_list(changed_files)
    conn.execute(
        """
        INSERT INTO git_context (
            repo, branch, head_commit, indexed_branch, indexed_commit, dirty,
            status_short, diff_text, staged_diff_text, recent_log_text, changed_files_json, captured_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(repo, branch) DO UPDATE SET
            head_commit = excluded.head_commit,
            indexed_branch = excluded.indexed_branch,
            indexed_commit = excluded.indexed_commit,
            dirty = excluded.dirty,
            status_short = excluded.status_short,
            diff_text = excluded.diff_text,
            staged_diff_text = excluded.staged_diff_text,
            recent_log_text = excluded.recent_log_text,
            changed_files_json = excluded.changed_files_json,
            captured_at = excluded.captured_at
        """,
        (
            repo,
            branch,
            head_commit,
            indexed_branch,
            indexed_commit,
            1 if dirty else 0,
            redacted_status,
            redacted_diff,
            redacted_staged_diff,
            redacted_recent_log,
            json.dumps(redacted_changed_files),
            now,
        ),
    )
    conn.commit()



def list_git_contexts(conn: sqlite3.Connection, repo: str | None, limit: int = 10) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM git_context{clause} ORDER BY captured_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()



def upsert_github_context(
    conn: sqlite3.Connection,
    repo: str | None,
    ref_type: str,
    ref_number: int,
    title: str,
    *,
    body: str = "",
    changed_files: list[str] | None = None,
    comments: list[str] | None = None,
    review_comments: list[str] | None = None,
    ci_logs_text: str = "",
    linked_issues: list[str] | None = None,
    source: str = "manual",
) -> None:
    now = time.time()
    redacted_title = redact_sensitive_text(title).strip()
    redacted_body = redact_sensitive_text(body).strip()
    redacted_changed_files = _redact_text_list(changed_files or [])
    redacted_comments = _redact_text_list(comments or [])
    redacted_review_comments = _redact_text_list(review_comments or [])
    redacted_ci_logs = redact_sensitive_text(ci_logs_text).strip()
    redacted_linked_issues = _redact_text_list(linked_issues or [])
    redacted_source = redact_sensitive_text(source).strip()
    conn.execute(
        """
        INSERT INTO github_context (
            repo, ref_type, ref_number, title, body, changed_files_json, comments_json,
            review_comments_json, ci_logs_text, linked_issues_json, source, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(repo, ref_type, ref_number) DO UPDATE SET
            title = excluded.title,
            body = excluded.body,
            changed_files_json = excluded.changed_files_json,
            comments_json = excluded.comments_json,
            review_comments_json = excluded.review_comments_json,
            ci_logs_text = excluded.ci_logs_text,
            linked_issues_json = excluded.linked_issues_json,
            source = excluded.source,
            updated_at = excluded.updated_at
        """,
        (
            repo,
            ref_type,
            ref_number,
            redacted_title,
            redacted_body,
            json.dumps(redacted_changed_files),
            json.dumps(redacted_comments),
            json.dumps(redacted_review_comments),
            redacted_ci_logs,
            json.dumps(redacted_linked_issues),
            redacted_source,
            now,
        ),
    )
    conn.commit()



def list_github_contexts(
    conn: sqlite3.Connection,
    repo: str | None,
    *,
    ref_type: str | None = None,
    limit: int = 10,
) -> list[sqlite3.Row]:
    clauses: list[str] = []
    params: list[object] = []
    if repo:
        clauses.append("repo = ?")
        params.append(repo)
    if ref_type:
        clauses.append("ref_type = ?")
        params.append(ref_type)
    sql = "SELECT * FROM github_context"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY updated_at DESC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()



def add_test_failure(
    conn: sqlite3.Connection,
    repo: str | None,
    command: str,
    output_text: str,
    *,
    runner: str | None = None,
    exit_code: int | None = None,
    source: str = "local",
) -> int:
    now = time.time()
    redacted_command = redact_sensitive_text(command).strip()
    redacted_output = redact_sensitive_text(output_text).strip()
    normalized_error = normalize_error_text(redacted_output)
    fingerprint_hash = fingerprint_error(normalized_error)
    cursor = conn.execute(
        """
        INSERT INTO test_failure_memory (
            repo, runner, command, output_text, normalized_error, fingerprint_hash,
            stack_symbols_json, file_paths_json, exit_code, source, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo,
            runner,
            redacted_command,
            redacted_output,
            normalized_error,
            fingerprint_hash,
            json.dumps(extract_stack_symbols(redacted_output)),
            json.dumps(extract_file_paths(redacted_output)),
            exit_code,
            source,
            now,
            now,
        ),
    )
    conn.commit()
    return _cursor_lastrowid(cursor)



def list_test_failures(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM test_failure_memory{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()



def remember_memory(
    conn: sqlite3.Connection,
    repo: str | None,
    kind: str,
    subject: str,
    value: str,
    *,
    global_scope: bool = False,
    source_session_id: str | None = None,
) -> int:
    if kind not in MEMORY_KIND_LABELS:
        raise ValueError(f"Unknown memory kind: {kind}")
    scoped_repo = None if global_scope else repo
    normalized_subject = _normalize_memory_subject(subject)
    now = time.time()
    rows = conn.execute(
        """
        SELECT memory_id, value FROM developer_memory
        WHERE kind = ?
          AND normalized_subject = ?
          AND ((repo IS NULL AND ? IS NULL) OR repo = ?)
        ORDER BY updated_at DESC, memory_id DESC
        """,
        (kind, normalized_subject, scoped_repo, scoped_repo),
    ).fetchall()
    normalized_value = value.strip()
    for row in rows:
        if str(row["value"]).strip() == normalized_value:
            conn.execute(
                """
                UPDATE developer_memory
                SET subject = ?, value = ?, status = 'active', updated_at = ?, last_used_at = ?
                WHERE memory_id = ?
                """,
                (subject.strip(), normalized_value, now, now, row["memory_id"]),
            )
            conn.commit()
            return int(row["memory_id"])
    conn.execute(
        """
        UPDATE developer_memory
        SET status = 'stale', updated_at = ?
        WHERE kind = ?
          AND normalized_subject = ?
          AND ((repo IS NULL AND ? IS NULL) OR repo = ?)
          AND status = 'active'
        """,
        (now, kind, normalized_subject, scoped_repo, scoped_repo),
    )
    cursor = conn.execute(
        """
        INSERT INTO developer_memory (
            repo, kind, subject, normalized_subject, value, status,
            source_session_id, created_at, updated_at, last_used_at
        )
        VALUES (?, ?, ?, ?, ?, 'active', ?, ?, ?, ?)
        """,
        (
            scoped_repo,
            kind,
            subject.strip(),
            normalized_subject,
            normalized_value,
            source_session_id,
            now,
            now,
            now,
        ),
    )
    conn.commit()
    return _cursor_lastrowid(cursor)



def list_memory_entries(
    conn: sqlite3.Connection,
    repo: str | None,
    *,
    kind: str | None = None,
    limit: int = 20,
    scope: str = "all",
    status: str = "active",
) -> list[sqlite3.Row]:
    clauses: list[str] = []
    params: list[object] = []
    if scope == "global":
        clauses.append("repo IS NULL")
    elif scope == "repo":
        if repo:
            clauses.append("repo = ?")
            params.append(repo)
        else:
            clauses.append("repo IS NOT NULL")
    elif repo:
        clauses.append("(repo = ? OR repo IS NULL)")
        params.append(repo)
    if kind:
        clauses.append("kind = ?")
        params.append(kind)
    if status != "all":
        clauses.append("status = ?")
        params.append(status)
    sql = "SELECT * FROM developer_memory"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY kind, CASE status WHEN 'active' THEN 0 WHEN 'conflict' THEN 1 ELSE 2 END, updated_at DESC, memory_id DESC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()



def detect_memory_conflicts(
    conn: sqlite3.Connection,
    repo: str | None,
    limit: int = 20,
) -> list[dict[str, object]]:
    clauses: list[str] = []
    params: list[object] = []
    if repo:
        clauses.append("(repo = ? OR repo IS NULL)")
        params.append(repo)
    where_clause = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    groups = conn.execute(
        f"""
        SELECT repo, kind, normalized_subject, COUNT(DISTINCT value) AS distinct_values
        FROM developer_memory
        {where_clause}
        GROUP BY repo, kind, normalized_subject
        HAVING COUNT(DISTINCT value) > 1
        ORDER BY MAX(updated_at) DESC
        LIMIT ?
        """,
        params + [limit],
    ).fetchall()
    conflicts: list[dict[str, object]] = []
    for group in groups:
        rows = conn.execute(
            """
            SELECT * FROM developer_memory
            WHERE kind = ? AND normalized_subject = ?
              AND ((repo IS NULL AND ? IS NULL) OR repo = ?)
            ORDER BY updated_at DESC, memory_id DESC
            """,
            (group["kind"], group["normalized_subject"], group["repo"], group["repo"]),
        ).fetchall()
        for row in rows[1:]:
            if row["status"] == "active":
                conn.execute(
                    "UPDATE developer_memory SET status = 'conflict', updated_at = ? WHERE memory_id = ?",
                    (time.time(), row["memory_id"]),
                )
        conn.commit()
        conflicts.append(
            {
                "repo": group["repo"],
                "kind": group["kind"],
                "subject": rows[0]["subject"] if rows else group["normalized_subject"],
                "values": [row["value"] for row in rows],
                "statuses": [row["status"] for row in rows],
            }
        )
    return conflicts



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
    redacted_query = redact_sensitive_text(query).strip()
    redacted_route_reason = redact_sensitive_text(route_reason).strip()
    redacted_output = redact_sensitive_text(output_text).strip()
    redacted_files = _redact_text_list(relevant_files)
    redacted_output_kind = redact_sensitive_text(output_kind).strip()
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
            redacted_query,
            redacted_route_reason,
            redacted_output_kind,
            redacted_output,
            json.dumps(redacted_files),
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



def _extract_session_artifacts(query: str, output_text: str) -> dict[str, list[str]]:
    safe_query = redact_sensitive_text(query)
    safe_output = redact_sensitive_text(output_text)
    commands = [
        redact_sensitive_text(match.strip())
        for match in re.findall(r"`([^`\n]+)`", safe_output)
        if len(match.strip()) >= 3
    ]
    errors = [
        redact_sensitive_text(line.split("error:", 1)[1].strip())
        for line in safe_output.splitlines()
        if "error:" in line.lower()
    ]
    todos = []
    for line in safe_output.splitlines():
        stripped = line.strip()
        lowered = stripped.lower()
        if stripped.startswith("- [") or lowered.startswith("todo:") or lowered.startswith("- todo"):
            todos.append(redact_sensitive_text(stripped))
    if not todos and re.search(r"\b(add|fix|implement|refactor|review|debug)\b", safe_query.lower()):
        todos.append(safe_query.strip())
    decisions = [
        redact_sensitive_text(line.strip())
        for line in safe_output.splitlines()
        if line.strip().lower().startswith("decision:") or "## decisions" in line.lower()
    ]
    useful_facts = [
        redact_sensitive_text(line.strip())
        for line in safe_output.splitlines()
        if line.strip().startswith("- ") and any(token in line.lower() for token in ("repo", "mode", "reason", "file"))
    ]
    return {
        "commands": list(dict.fromkeys(commands))[:6],
        "errors": list(dict.fromkeys(errors))[:6],
        "todos": list(dict.fromkeys(todos))[:6],
        "decisions": list(dict.fromkeys(decisions))[:6],
        "useful_facts": list(dict.fromkeys(useful_facts))[:6],
    }



def compact_session(conn: sqlite3.Connection, session_id: str) -> sqlite3.Row | None:
    row = get_session(conn, session_id)
    if row is None:
        return None
    now = time.time()
    files = session_files(row)
    file_summary = ", ".join(files[:4]) if files else "none"
    output_preview = redact_sensitive_text(str(row["output_text"])).strip().replace("\n", " ")[:280]
    route_reason = redact_sensitive_text(str(row["route_reason"]))
    query_text = redact_sensitive_text(str(row["query"]))
    mode_text = redact_sensitive_text(str(row["mode"]))
    summary = (
        f"[{mode_text}] {query_text} | files: {file_summary} | route: {route_reason}"
        + (f" | output: {output_preview}" if output_preview else "")
    )
    extracted = _extract_session_artifacts(query_text, str(row["output_text"]))
    conn.execute(
        """
        INSERT INTO session_compactions (session_id, repo, mode, summary, extracted_json, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(session_id) DO UPDATE SET
            repo = excluded.repo,
            mode = excluded.mode,
            summary = excluded.summary,
            extracted_json = excluded.extracted_json,
            updated_at = excluded.updated_at
        """,
        (session_id, row["repo"], row["mode"], summary, json.dumps(extracted), now, now),
    )
    conn.commit()
    return conn.execute(
        "SELECT * FROM session_compactions WHERE session_id = ?",
        (session_id,),
    ).fetchone()



def list_session_compactions(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM session_compactions{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()



def session_compaction_details(row: sqlite3.Row) -> dict[str, list[str]]:
    return json.loads(row["extracted_json"] or "{}")


def extract_memory_from_compaction(
    compaction_row: sqlite3.Row,
) -> list[dict[str, str]]:
    """Return structured memory candidate dicts from a session compaction row.

    Each dict has: kind, subject, value, scope ('repo'|'global'), confidence.
    Heuristic only — no LLM calls. For LLM extraction, use the --llm flag on
    `rag memory extract`.
    """
    details = session_compaction_details(compaction_row)
    candidates: list[dict[str, str]] = []
    for cmd in details.get("commands", []):
        candidates.append({
            "kind": "tool_preferences",
            "subject": "command",
            "value": cmd,
            "scope": "repo",
            "confidence": "medium",
        })
    for decision in details.get("decisions", []):
        candidates.append({
            "kind": "repo_conventions",
            "subject": "decision",
            "value": decision,
            "scope": "repo",
            "confidence": "high",
        })
    for fact in details.get("useful_facts", []):
        candidates.append({
            "kind": "project_facts",
            "subject": "fact",
            "value": fact,
            "scope": "repo",
            "confidence": "medium",
        })
    return candidates


def add_eval_case(
    conn: sqlite3.Connection,
    repo: str | None,
    query: str,
    expected_files: list[str],
    *,
    mode: str = "deep",
    expected_symbols: list[str] | None = None,
    notes: str | None = None,
) -> int:
    now = time.time()
    cursor = conn.execute(
        """
        INSERT INTO eval_cases (
            repo, query, mode, expected_files_json, expected_symbols_json, notes, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            repo,
            query.strip(),
            mode,
            json.dumps(expected_files),
            json.dumps(expected_symbols or []),
            notes,
            now,
            now,
        ),
    )
    conn.commit()
    return _cursor_lastrowid(cursor)



def list_eval_cases(conn: sqlite3.Connection, repo: str | None, limit: int) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM eval_cases{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()



def get_eval_case(conn: sqlite3.Connection, case_id: int) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM eval_cases WHERE case_id = ?", (case_id,)).fetchone()



def eval_case_expected_files(row: sqlite3.Row) -> list[str]:
    return json.loads(row["expected_files_json"] or "[]")


def eval_case_expected_symbols(row: sqlite3.Row) -> list[str]:
    return json.loads(row["expected_symbols_json"] or "[]")


def _redacted_json(value: Any) -> str:
    return redact_sensitive_text(json.dumps(value, sort_keys=True))


def _load_json_column(row: sqlite3.Row, column: str, default: Any) -> Any:
    raw = row[column]
    if not raw:
        return default
    return json.loads(raw)


def _normalize_task_fingerprint(task: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", " ", task.lower()).strip()
    return hashlib.sha1(normalized.encode("utf-8")).hexdigest()


def _write_run_export(export_root: Path | None, payload: dict[str, Any]) -> Path | None:
    if export_root is None:
        return None
    run_dir = export_root / ".agent" / "rag-runs"
    run_dir.mkdir(parents=True, exist_ok=True)
    path = run_dir / f"{payload['run_id']}.json"
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    return path


def record_retrieval_run(
    conn: sqlite3.Connection,
    *,
    run_id: str,
    repo: str | None,
    branch: str | None,
    query: str,
    mode: str,
    intent: str | None,
    plan: dict[str, Any],
    rewrites: list[str],
    candidate_counts: dict[str, int],
    selected_files: list[str],
    edit_scope: dict[str, Any],
    missing_context: dict[str, Any],
    packed_context_token_estimate: int,
    timings_ms: dict[str, float],
    warnings: list[str] | None = None,
    errors: list[str] | None = None,
    metadata: dict[str, Any] | None = None,
    export_root: Path | None = None,
    created_at: float | None = None,
) -> dict[str, Any]:
    now = created_at or time.time()
    sanitized = {
        "run_id": run_id,
        "timestamp": now,
        "repo": redact_sensitive_text(repo or ""),
        "branch": redact_sensitive_text(branch or ""),
        "query": redact_sensitive_text(query),
        "mode": mode,
        "intent": intent or "",
        "plan": json.loads(_redacted_json(plan or {})),
        "rewrites": _redact_text_list(rewrites or []),
        "candidate_counts": candidate_counts,
        "selected_files": _redact_text_list(selected_files or []),
        "edit_scope": json.loads(_redacted_json(edit_scope or {})),
        "missing_context": json.loads(_redacted_json(missing_context or {})),
        "packed_context_token_estimate": int(packed_context_token_estimate),
        "timings_ms": timings_ms,
        "warnings": _redact_text_list(warnings or []),
        "errors": _redact_text_list(errors or []),
        "metadata": json.loads(_redacted_json(metadata or {})),
    }
    conn.execute(
        """
        INSERT OR REPLACE INTO retrieval_runs (
            id, repo, branch, mode, intent, query, plan_json, rewrites_json,
            candidate_counts_json, selected_files_json, edit_scope_json, missing_context_json,
            packed_context_token_estimate, timings_json, warnings_json, errors_json,
            metadata_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            sanitized["repo"] or None,
            sanitized["branch"] or None,
            mode,
            sanitized["intent"] or None,
            sanitized["query"],
            json.dumps(sanitized["plan"], sort_keys=True),
            json.dumps(sanitized["rewrites"], sort_keys=True),
            json.dumps(candidate_counts, sort_keys=True),
            json.dumps(sanitized["selected_files"], sort_keys=True),
            json.dumps(sanitized["edit_scope"], sort_keys=True),
            json.dumps(sanitized["missing_context"], sort_keys=True),
            int(packed_context_token_estimate),
            json.dumps(timings_ms, sort_keys=True),
            json.dumps(sanitized["warnings"], sort_keys=True),
            json.dumps(sanitized["errors"], sort_keys=True),
            json.dumps(sanitized["metadata"], sort_keys=True),
            now,
        ),
    )
    conn.commit()
    _write_run_export(export_root, sanitized)
    return sanitized


def list_retrieval_runs(conn: sqlite3.Connection, repo: str | None, limit: int = 20) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM retrieval_runs{clause} ORDER BY created_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def latest_retrieval_run(conn: sqlite3.Connection, repo: str | None) -> sqlite3.Row | None:
    rows = list_retrieval_runs(conn, repo, limit=1)
    return rows[0] if rows else None


def get_retrieval_run(conn: sqlite3.Connection, run_id: str) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM retrieval_runs WHERE id = ?", (run_id,)).fetchone()


def retrieval_run_payload(row: sqlite3.Row) -> dict[str, Any]:
    return {
        "run_id": row["id"],
        "timestamp": row["created_at"],
        "repo": row["repo"],
        "branch": row["branch"],
        "query": row["query"],
        "mode": row["mode"],
        "intent": row["intent"],
        "plan": _load_json_column(row, "plan_json", {}),
        "rewrites": _load_json_column(row, "rewrites_json", []),
        "candidate_counts": _load_json_column(row, "candidate_counts_json", {}),
        "selected_files": _load_json_column(row, "selected_files_json", []),
        "edit_scope": _load_json_column(row, "edit_scope_json", {}),
        "missing_context": _load_json_column(row, "missing_context_json", {}),
        "packed_context_token_estimate": row["packed_context_token_estimate"],
        "timings_ms": _load_json_column(row, "timings_json", {}),
        "warnings": _load_json_column(row, "warnings_json", []),
        "errors": _load_json_column(row, "errors_json", []),
        "metadata": _load_json_column(row, "metadata_json", {}),
    }


def explain_retrieval_run(row: sqlite3.Row) -> str:
    payload = retrieval_run_payload(row)
    candidate_counts = payload["candidate_counts"]
    timings = payload["timings_ms"]
    lines = [
        f"run_id: {payload['run_id']}",
        f"mode: {payload['mode']}",
        f"intent: {payload['intent'] or '-'}",
        f"query: {payload['query']}",
        "candidate counts:",
    ]
    lines.extend(f"- {key}: {value}" for key, value in sorted(candidate_counts.items()))
    lines.append("timings:")
    lines.extend(f"- {key}: {value}ms" for key, value in sorted(timings.items()))
    if payload["warnings"]:
        lines.append("warnings:")
        lines.extend(f"- {value}" for value in payload["warnings"])
    if payload["errors"]:
        lines.append("errors:")
        lines.extend(f"- {value}" for value in payload["errors"])
    return "\n".join(lines)


def warm_retrieval_cache(
    conn: sqlite3.Connection,
    repo: str | None,
    paths: list[str],
    *,
    kind: str = "hot",
    score: float = 1.0,
    metadata: dict[str, Any] | None = None,
) -> None:
    if not repo:
        return
    now = time.time()
    for path in _redact_text_list(paths):
        conn.execute(
            """
            INSERT INTO retrieval_cache (repo, path, kind, score, hits, metadata_json, updated_at)
            VALUES (?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(repo, path, kind) DO UPDATE SET
                score = excluded.score,
                hits = retrieval_cache.hits + 1,
                metadata_json = excluded.metadata_json,
                updated_at = excluded.updated_at
            """,
            (repo, path, kind, score, json.dumps(metadata or {}, sort_keys=True), now),
        )
    conn.commit()


def list_retrieval_cache(conn: sqlite3.Connection, repo: str | None, limit: int = 20) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM retrieval_cache{clause} ORDER BY updated_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def clear_retrieval_cache(conn: sqlite3.Connection, repo: str | None) -> int:
    clause, params = _scope_clause(repo)
    cursor = conn.execute(f"DELETE FROM retrieval_cache{clause}", params)
    conn.commit()
    return cursor.rowcount


def record_retrieval_outcome(
    conn: sqlite3.Connection,
    *,
    repo: str | None,
    task: str,
    retrieved_files: list[str],
    edited_files: list[str],
    checks_run: list[str],
    passed: bool,
    notes: str | None = None,
    run_id: str | None = None,
) -> int:
    redacted_task = redact_sensitive_text(task.strip())
    retrieved = _redact_text_list(retrieved_files)
    edited = _redact_text_list(edited_files)
    missed = [path for path in edited if path not in set(retrieved)]
    now = time.time()
    cursor = conn.execute(
        """
        INSERT INTO retrieval_outcomes (
            run_id, repo, task, task_fingerprint, retrieved_files_json, edited_files_json,
            checks_run_json, passed, notes, missed_files_json, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            run_id,
            repo,
            redacted_task,
            _normalize_task_fingerprint(redacted_task),
            json.dumps(retrieved, sort_keys=True),
            json.dumps(edited, sort_keys=True),
            json.dumps(_redact_text_list(checks_run), sort_keys=True),
            1 if passed else 0,
            _redact_optional(notes),
            json.dumps(missed, sort_keys=True),
            now,
        ),
    )
    if repo:
        if edited:
            warm_retrieval_cache(
                conn,
                repo,
                edited,
                kind="edited",
                score=1.2 if passed else 0.8,
                metadata={"run_id": run_id or "", "passed": bool(passed)},
            )
        if missed:
            warm_retrieval_cache(
                conn,
                repo,
                missed,
                kind="missed",
                score=1.1,
                metadata={"run_id": run_id or "", "task": redacted_task},
            )
    conn.commit()
    return _cursor_lastrowid(cursor)


def list_retrieval_outcomes(conn: sqlite3.Connection, repo: str | None, limit: int = 50) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM retrieval_outcomes{clause} ORDER BY created_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def record_eval_run(
    conn: sqlite3.Connection,
    *,
    run_id: str,
    repo: str | None,
    case_count: int,
    metrics: dict[str, Any],
) -> None:
    conn.execute(
        """
        INSERT OR REPLACE INTO eval_runs (id, repo, case_count, metrics_json, created_at)
        VALUES (?, ?, ?, ?, ?)
        """,
        (run_id, repo, case_count, _redacted_json(metrics), time.time()),
    )
    conn.commit()


def list_eval_runs(conn: sqlite3.Connection, repo: str | None, limit: int = 20) -> list[sqlite3.Row]:
    clause, params = _scope_clause(repo)
    return conn.execute(
        f"SELECT * FROM eval_runs{clause} ORDER BY created_at DESC LIMIT ?",
        params + [limit],
    ).fetchall()


def get_eval_run(conn: sqlite3.Connection, run_id: str) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM eval_runs WHERE id = ?", (run_id,)).fetchone()


def load_operational_state(conn: sqlite3.Connection, repo: str | None) -> dict[str, list[sqlite3.Row]]:
    return {
        "todos": list_todos(conn, repo, status="all", limit=6),
        "decisions": list_decisions(conn, repo, limit=6),
        "commands": list_commands(conn, repo, limit=6),
        "errors": list_errors(conn, repo, limit=6),
        "git_contexts": list_git_contexts(conn, repo, limit=2),
        "github_contexts": list_github_contexts(conn, repo, limit=4),
        "test_failures": list_test_failures(conn, repo, limit=4),
        "sessions": list_sessions(conn, repo, limit=4),
        "memory_entries": list_memory_entries(conn, repo, limit=12, scope="all", status="active"),
        "compactions": list_session_compactions(conn, repo, limit=3),
    }



def format_operational_state(state: dict[str, list[sqlite3.Row]]) -> str:
    sections: list[str] = []
    todos = state.get("todos", [])
    if todos:
        sections.append(
            "## Todos\n"
            + "\n".join(
                f"- [{row['status']}] {row['title']}" + (f" — {row['detail']}" if row["detail"] else "")
                for row in todos
            )
        )
    decisions = state.get("decisions", [])
    if decisions:
        sections.append(
            "## Decisions\n"
            + "\n".join(
                f"- {row['title']}: {row['detail']}" + (f" (why: {row['rationale']})" if row["rationale"] else "")
                for row in decisions
            )
        )
    commands = state.get("commands", [])
    if commands:
        sections.append(
            "## Useful commands\n"
            + "\n".join(
                f"- `{row['command']}`" + (f" — {row['purpose']}" if row["purpose"] else "")
                for row in commands
            )
        )
    errors = state.get("errors", [])
    if errors:
        sections.append(
            "## Errors and fixes\n"
            + "\n".join(
                f"- error: {row['error_text']}" + (f" | fix: {row['fix_text']}" if row["fix_text"] else "")
                for row in errors
            )
        )
    test_failures = state.get("test_failures", [])
    if test_failures:
        sections.append(
            "## Test failures\n"
            + "\n".join(
                f"- `{row['command']}` [{row['fingerprint_hash']}]"
                + (f" exit={row['exit_code']}" if row["exit_code"] is not None else "")
                for row in test_failures
            )
        )
    github_contexts = state.get("github_contexts", [])
    if github_contexts:
        sections.append(
            "## GitHub context\n"
            + "\n".join(
                f"- {row['ref_type']} #{row['ref_number']}: {row['title']}"
                for row in github_contexts
            )
        )
    git_contexts = state.get("git_contexts", [])
    if git_contexts:
        sections.append(
            "## Git context\n"
            + "\n".join(
                f"- {row['branch']} dirty={'yes' if row['dirty'] else 'no'} changed={', '.join(json.loads(row['changed_files_json'] or '[]')[:4]) or '-'}"
                for row in git_contexts
            )
        )
    memory_entries = state.get("memory_entries", [])
    if memory_entries:
        grouped: dict[str, list[sqlite3.Row]] = {kind: [] for kind in MEMORY_KIND_LABELS}
        for row in memory_entries:
            grouped.setdefault(row["kind"], []).append(row)
        for kind in VALID_MEMORY_KINDS:
            rows = grouped.get(kind, [])
            if not rows:
                continue
            sections.append(
                f"## {MEMORY_KIND_LABELS[kind]}\n"
                + "\n".join(
                    f"- {row['subject']}: {row['value']}"
                    + (" [global]" if row["repo"] is None else "")
                    for row in rows
                )
            )
    compactions = state.get("compactions", [])
    if compactions:
        sections.append(
            "## Session compactions\n"
            + "\n".join(f"- {row['summary']}" for row in compactions)
        )
    sessions = state.get("sessions", [])
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
    redacted_goal = redact_sensitive_text(goal)
    redacted_content = redact_sensitive_text(content)
    filename = f"{time.strftime('%Y%m%d-%H%M%S')}-{slugify(redacted_goal)}.md"
    path = directory / filename
    path.write_text(redacted_content.rstrip() + "\n")
    return path
