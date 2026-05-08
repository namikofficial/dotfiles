from __future__ import annotations

import sqlite3
import time

from .indexing import replace_file_summary, summarize_file
from .llm import complete_llm
from .runtime import INDEX_SCHEMA
from .storage import repo_identity
from .types import Chunk, Fact, RepoMemoryStatus


def generate_repo_memory(
    conn: sqlite3.Connection,
    config: dict,
    repo: str,
) -> str:
    repo_row = conn.execute("SELECT root FROM indexed_repos WHERE repo = ?", (repo,)).fetchone()
    if repo_row is None:
        raise SystemExit(f"Repo not indexed: {repo}")
    summary_rows = conn.execute(
        "SELECT path, summary, symbols FROM file_summaries WHERE repo = ? ORDER BY facts_count DESC, updated_at DESC LIMIT 24",
        (repo,),
    ).fetchall()
    fact_rows = conn.execute(
        """
        SELECT path, kind, key, value, line FROM facts
        WHERE repo = ?
        ORDER BY
            CASE kind
                WHEN 'keybind' THEN 0
                WHEN 'tool' THEN 1
                WHEN 'env' THEN 2
                WHEN 'startup' THEN 3
                WHEN 'exec' THEN 4
                WHEN 'package' THEN 5
                WHEN 'sql-object' THEN 6
                WHEN 'alias' THEN 7
                ELSE 20
            END,
            updated_at DESC
        LIMIT 32
        """,
        (repo,),
    ).fetchall()
    file_summary_text = "\n".join(
        f"- {row['path']}: {row['summary']} (symbols: {row['symbols'] or '-'})" for row in summary_rows
    )
    fact_text = "\n".join(
        f"- {row['path']}:{row['line']} kind={row['kind']} key={row['key']} value={row['value']}" for row in fact_rows
    )
    system_prompt = (
        "You are creating durable memory for a local repo assistant. Summarize this repo for future retrieval. "
        "Focus on purpose, architecture, important entry points, conventions, risky scripts, local setup commands, "
        "backend/database touchpoints, and important runtime paths. Avoid temporary details. Return markdown with stable headings."
    )
    user_prompt = (
        f"Repo: {repo}\nRoot: {repo_row['root']}\n\nFile summaries:\n{file_summary_text}\n\nFacts:\n{fact_text}\n"
    )
    return complete_llm(config, system_prompt, user_prompt, max_tokens=1400)


def store_repo_memory(conn: sqlite3.Connection, repo: str, summary: str) -> None:
    repo_row = conn.execute("SELECT root FROM indexed_repos WHERE repo = ?", (repo,)).fetchone()
    if repo_row is None:
        raise SystemExit(f"Repo not indexed: {repo}")
    chunk_count = conn.execute("SELECT COUNT(*) FROM chunks WHERE repo = ?", (repo,)).fetchone()[0]
    conn.execute(
        """
        INSERT INTO repo_memory (
            repo, root, summary, architecture, important_paths, conventions, updated_at, index_schema, source_chunk_count
        ) VALUES (?, ?, ?, NULL, NULL, NULL, ?, ?, ?)
        ON CONFLICT(repo) DO UPDATE SET
            root=excluded.root,
            summary=excluded.summary,
            updated_at=excluded.updated_at,
            index_schema=excluded.index_schema,
            source_chunk_count=excluded.source_chunk_count
        """,
        (repo, repo_row["root"], summary, time.time(), INDEX_SCHEMA, chunk_count),
    )
    conn.commit()


def repo_memory_status_rows(conn: sqlite3.Connection, repo: str | None = None) -> list[RepoMemoryStatus]:
    sql = """
        SELECT ir.repo, ir.root, ir.last_indexed,
               rm.updated_at AS memory_updated_at,
               rm.index_schema AS memory_index_schema,
               rm.source_chunk_count AS memory_chunk_count
        FROM indexed_repos ir
        LEFT JOIN repo_memory rm ON rm.repo = ir.repo
    """
    params: list[str] = []
    if repo:
        sql += " WHERE ir.repo = ?"
        params.append(repo)
    sql += " ORDER BY ir.repo"
    rows = conn.execute(sql, params).fetchall()
    results: list[RepoMemoryStatus] = []
    for row in rows:
        repo_name = str(row["repo"])
        root = str(row["root"])
        last_indexed = float(row["last_indexed"])
        memory_updated_at = float(row["memory_updated_at"]) if row["memory_updated_at"] is not None else None
        current_chunk_count = int(
            conn.execute("SELECT COUNT(*) FROM chunks WHERE repo = ?", (repo_name,)).fetchone()[0]
        )
        reasons: list[str] = []
        status = "fresh"
        if memory_updated_at is None:
            status = "missing"
            reasons.append("no repo memory stored")
        else:
            if row["memory_index_schema"] != INDEX_SCHEMA:
                status = "stale"
                reasons.append(f"schema {row['memory_index_schema']} != {INDEX_SCHEMA}")
            if last_indexed > memory_updated_at:
                status = "stale"
                reasons.append("repo indexed after memory refresh")
            memory_chunk_count = int(row["memory_chunk_count"] or 0)
            if abs(current_chunk_count - memory_chunk_count) >= 25:
                status = "stale"
                reasons.append(f"chunk count drifted ({memory_chunk_count} -> {current_chunk_count})")
        results.append(
            {
                "repo": repo_name,
                "root": root,
                "status": status,
                "reasons": reasons,
                "memory_updated_at": memory_updated_at,
                "last_indexed": last_indexed,
                "chunk_count": current_chunk_count,
            }
        )
    return results


def refresh_file_summaries(conn: sqlite3.Connection, repo: str | None = None, changed_only: bool = False) -> int:
    sql = (
        "SELECT repo, path, file_hash, language, kind FROM chunks "
        + ("WHERE repo = ? " if repo else "")
        + "GROUP BY repo, path, file_hash, language, kind ORDER BY repo, path"
    )
    params = [repo] if repo else []
    rows = conn.execute(sql, params).fetchall()
    refreshed = 0
    for row in rows:
        existing = conn.execute(
            "SELECT file_hash FROM file_summaries WHERE repo = ? AND path = ?",
            (row["repo"], row["path"]),
        ).fetchone()
        if changed_only and existing and existing["file_hash"] == row["file_hash"]:
            continue
        chunk_rows = conn.execute(
            "SELECT symbol, content, start_line, end_line, kind FROM chunks WHERE repo = ? AND path = ? ORDER BY chunk_index",
            (row["repo"], row["path"]),
        ).fetchall()
        chunks = [
            Chunk(
                content=chunk["content"],
                start_line=chunk["start_line"],
                end_line=chunk["end_line"],
                symbol=chunk["symbol"] or "",
                kind=chunk["kind"],
            )
            for chunk in chunk_rows
        ]
        facts = [
            Fact(
                kind=fact["kind"],
                key=fact["key"],
                value=fact["value"],
                line=fact["line"],
                confidence=fact["confidence"],
                source=fact["source"],
            )
            for fact in conn.execute(
                "SELECT * FROM facts WHERE repo = ? AND path = ? ORDER BY line",
                (row["repo"], row["path"]),
            ).fetchall()
        ]
        summary, symbols = summarize_file(row["path"], row["language"], row["kind"], chunks, facts)
        replace_file_summary(
            conn,
            row["repo"],
            row["path"],
            row["file_hash"],
            row["language"],
            row["kind"],
            summary,
            symbols,
            len(facts),
        )
        refreshed += 1
    conn.commit()
    return refreshed


def selected_repo_name(root) -> str:
    return repo_identity(root)[1]
