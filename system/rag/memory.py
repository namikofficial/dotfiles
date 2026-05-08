from __future__ import annotations

import json
import re
import sqlite3
import subprocess
import time
from pathlib import Path

from .indexing import replace_file_summary, summarize_file
from .llm import complete_llm
from .runtime import INDEX_SCHEMA
from .state import (
    MEMORY_KIND_LABELS,
    format_operational_state,
    list_memory_entries,
    list_session_compactions,
    load_operational_state,
    session_compaction_details,
)
from .storage import repo_identity
from .types import Chunk, Fact, RepoMemoryStatus



def _query_terms(text: str) -> list[str]:
    return [token.lower() for token in re.findall(r"[A-Za-z0-9_./:-]+", text)]



def git_head_commit(root: Path) -> str | None:
    try:
        return subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        return None



def git_changed_files_since(root: Path, commit: str | None) -> list[str]:
    if not commit:
        return []
    current = git_head_commit(root)
    if not current or current == commit:
        return []
    try:
        output = subprocess.check_output(
            ["git", "-C", str(root), "diff", "--name-only", f"{commit}..{current}", "--"],
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except subprocess.CalledProcessError:
        return []
    return [line.strip() for line in output.splitlines() if line.strip()]



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
    root = Path(repo_row["root"])
    chunk_count = conn.execute("SELECT COUNT(*) FROM chunks WHERE repo = ?", (repo,)).fetchone()[0]
    conn.execute(
        """
        INSERT INTO repo_memory (
            repo, root, summary, architecture, important_paths, conventions, updated_at,
            index_schema, source_chunk_count, summary_commit, changed_files_json,
            changed_symbols_json, freshness_score
        ) VALUES (?, ?, ?, NULL, NULL, NULL, ?, ?, ?, ?, '[]', '[]', 1.0)
        ON CONFLICT(repo) DO UPDATE SET
            root = excluded.root,
            summary = excluded.summary,
            updated_at = excluded.updated_at,
            index_schema = excluded.index_schema,
            source_chunk_count = excluded.source_chunk_count,
            summary_commit = excluded.summary_commit,
            changed_files_json = excluded.changed_files_json,
            changed_symbols_json = excluded.changed_symbols_json,
            freshness_score = excluded.freshness_score
        """,
        (repo, str(root), summary, time.time(), INDEX_SCHEMA, chunk_count, git_head_commit(root)),
    )
    conn.commit()



def _changed_symbols(conn: sqlite3.Connection, repo: str, changed_files: list[str]) -> list[str]:
    if not changed_files:
        return []
    placeholders = ",".join("?" for _ in changed_files)
    rows = conn.execute(
        f"""
        SELECT DISTINCT symbol FROM chunks
        WHERE repo = ? AND path IN ({placeholders}) AND symbol IS NOT NULL AND symbol != ''
        ORDER BY symbol LIMIT 16
        """,
        [repo, *changed_files],
    ).fetchall()
    return [str(row["symbol"]) for row in rows]



def _refresh_repo_memory_metrics(
    conn: sqlite3.Connection,
    repo: str,
    root: str,
    last_indexed: float,
    memory_updated_at: float | None,
    memory_index_schema: str | None,
    memory_chunk_count: int | None,
    summary_commit: str | None,
) -> tuple[str, list[str], float, str | None, list[str], list[str]]:
    reasons: list[str] = []
    status = "fresh"
    root_path = Path(root)
    current_commit = git_head_commit(root_path)
    changed_files = git_changed_files_since(root_path, summary_commit)
    changed_symbols = _changed_symbols(conn, repo, changed_files)
    freshness_score = 1.0
    if memory_updated_at is None:
        return "missing", ["no repo memory stored"], 0.0, current_commit, [], []
    if memory_index_schema != INDEX_SCHEMA:
        status = "stale"
        freshness_score -= 0.2
        reasons.append(f"schema {memory_index_schema} != {INDEX_SCHEMA}")
    if last_indexed > memory_updated_at:
        status = "stale"
        freshness_score -= 0.2
        reasons.append("repo indexed after memory refresh")
    current_chunk_count = int(conn.execute("SELECT COUNT(*) FROM chunks WHERE repo = ?", (repo,)).fetchone()[0])
    if abs(current_chunk_count - int(memory_chunk_count or 0)) >= 25:
        status = "stale"
        freshness_score -= 0.15
        reasons.append(f"chunk count drifted ({memory_chunk_count or 0} -> {current_chunk_count})")
    if summary_commit and current_commit and summary_commit != current_commit:
        status = "stale"
        freshness_score -= min(0.3, 0.04 * max(1, len(changed_files)))
        reasons.append(f"commit changed ({summary_commit[:8]} -> {current_commit[:8]})")
    if changed_files:
        reasons.append(f"{len(changed_files)} files changed since summary")
    if changed_symbols:
        reasons.append(f"{len(changed_symbols)} symbols touched since summary")
        freshness_score -= min(0.15, 0.02 * len(changed_symbols))
    return status, reasons, max(0.0, round(freshness_score, 2)), current_commit, changed_files, changed_symbols



def repo_memory_status_rows(conn: sqlite3.Connection, repo: str | None = None) -> list[RepoMemoryStatus]:
    sql = """
        SELECT ir.repo, ir.root, ir.last_indexed,
               rm.updated_at AS memory_updated_at,
               rm.index_schema AS memory_index_schema,
               rm.source_chunk_count AS memory_chunk_count,
               rm.summary_commit AS summary_commit
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
        status, reasons, freshness_score, current_commit, changed_files, changed_symbols = _refresh_repo_memory_metrics(
            conn,
            repo_name,
            root,
            last_indexed,
            memory_updated_at,
            row["memory_index_schema"],
            int(row["memory_chunk_count"] or 0) if row["memory_chunk_count"] is not None else 0,
            row["summary_commit"],
        )
        current_chunk_count = int(conn.execute("SELECT COUNT(*) FROM chunks WHERE repo = ?", (repo_name,)).fetchone()[0])
        if memory_updated_at is not None:
            conn.execute(
                """
                UPDATE repo_memory
                SET changed_files_json = ?, changed_symbols_json = ?, freshness_score = ?
                WHERE repo = ?
                """,
                (json.dumps(changed_files), json.dumps(changed_symbols), freshness_score, repo_name),
            )
        results.append(
            {
                "repo": repo_name,
                "root": root,
                "status": status,
                "reasons": reasons,
                "memory_updated_at": memory_updated_at,
                "last_indexed": last_indexed,
                "chunk_count": current_chunk_count,
                "summary_commit": row["summary_commit"],
                "current_commit": current_commit,
                "changed_files": changed_files,
                "changed_symbols": changed_symbols,
                "freshness_score": freshness_score,
            }
        )
    conn.commit()
    return results



def list_tool_taxonomy(
    conn: sqlite3.Connection,
    *,
    domain: str | None = None,
    query: str | None = None,
    limit: int = 40,
) -> list[sqlite3.Row]:
    clauses: list[str] = []
    params: list[object] = []
    if domain:
        clauses.append("domain = ?")
        params.append(domain)
    if query:
        tokens = _query_terms(query)[:8]
        token_clauses: list[str] = []
        for token in tokens:
            token_clauses.append("(domain LIKE ? OR tool LIKE ? OR aliases LIKE ? OR description LIKE ?)")
            params.extend([f"%{token}%", f"%{token}%", f"%{token}%", f"%{token}%"])
        if token_clauses:
            clauses.append("(" + " OR ".join(token_clauses) + ")")
    sql = "SELECT * FROM tool_taxonomy"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY domain, tool LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()



def taxonomy_terms_for_query(conn: sqlite3.Connection, query: str) -> list[str]:
    rows = list_tool_taxonomy(conn, query=query, limit=24)
    tokens = _query_terms(query)
    if any(token in {"backend", "api", "server", "nestjs"} for token in tokens):
        rows.extend(list_tool_taxonomy(conn, domain="node_backend", limit=12))
    if any(token in {"rust", "kernel", "driver", "systems"} for token in tokens):
        rows.extend(list_tool_taxonomy(conn, domain="rust_systems", limit=12))
    if any(token in {"desktop", "hyprland", "linux", "audio"} for token in tokens):
        rows.extend(list_tool_taxonomy(conn, domain="linux_desktop", limit=12))
    if any(token in {"metrics", "logs", "observability", "grafana"} for token in tokens):
        rows.extend(list_tool_taxonomy(conn, domain="observability", limit=12))
    expanded: list[str] = []
    for row in rows:
        expanded.append(str(row["tool"]))
        expanded.append(str(row["domain"]).replace("_", " "))
        expanded.extend(json.loads(row["aliases"] or "[]"))
    return [item for item in dict.fromkeys(expanded) if item]



def store_context_pack(
    conn: sqlite3.Connection,
    repo: str | None,
    name: str,
    content: str,
    metadata: dict[str, object],
    *,
    agent_target: str = "generic",
) -> None:
    now = time.time()
    conn.execute(
        """
        INSERT INTO context_packs (repo, name, agent_target, source, content, metadata_json, created_at, updated_at)
        VALUES (?, ?, ?, 'generated', ?, ?, ?, ?)
        ON CONFLICT(repo, name, agent_target) DO UPDATE SET
            content = excluded.content,
            metadata_json = excluded.metadata_json,
            updated_at = excluded.updated_at
        """,
        (repo, name, agent_target, content, json.dumps(metadata, indent=2, sort_keys=True), now, now),
    )
    conn.commit()



def get_context_pack(conn: sqlite3.Connection, repo: str | None, name: str, *, agent_target: str = "generic") -> sqlite3.Row | None:
    return conn.execute(
        "SELECT * FROM context_packs WHERE ((repo IS NULL AND ? IS NULL) OR repo = ?) AND name = ? AND agent_target = ?",
        (repo, repo, name, agent_target),
    ).fetchone()



def write_context_pack_file(root: Path, name: str, content: str) -> Path:
    directory = root / ".context"
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{name}.toon"
    path.write_text(content.rstrip() + "\n")
    return path



def build_context_pack(
    conn: sqlite3.Connection,
    repo: str | None,
    name: str,
    *,
    agent_target: str = "generic",
) -> tuple[str, dict[str, object]]:
    state = format_operational_state(load_operational_state(conn, repo))
    repo_summary = None
    freshness = None
    if repo:
        row = conn.execute("SELECT summary FROM repo_memory WHERE repo = ?", (repo,)).fetchone()
        repo_summary = row["summary"] if row else None
        status_rows = repo_memory_status_rows(conn, repo)
        freshness = status_rows[0]["freshness_score"] if status_rows else None
    memory_entries = list_memory_entries(conn, repo, scope="all", status="active", limit=24)
    memory_sections: list[str] = []
    for kind, label in MEMORY_KIND_LABELS.items():
        rows = [row for row in memory_entries if row["kind"] == kind]
        if not rows:
            continue
        memory_sections.append(
            f"## {label}\n"
            + "\n".join(
                f"- {row['subject']}: {row['value']}" + (" [global]" if row["repo"] is None else "")
                for row in rows
            )
        )
    compactions = list_session_compactions(conn, repo, limit=3)
    compaction_section = []
    for row in compactions:
        details = session_compaction_details(row)
        bullets = []
        for key in ("todos", "commands", "errors", "useful_facts"):
            values = details.get(key) or []
            if values:
                bullets.append(f"{key}: {', '.join(values[:2])}")
        compaction_section.append(f"- {row['summary']}" + (f" ({'; '.join(bullets)})" if bullets else ""))
    taxonomy_rows = list_tool_taxonomy(conn, query=f"{name} {repo or ''}", limit=12)
    domains: dict[str, list[str]] = {}
    for row in taxonomy_rows:
        domains.setdefault(str(row["domain"]), []).append(str(row["tool"]))
    sections = [
        f"# Context pack: {name}",
        "",
        "## Target",
        agent_target,
        "",
        "## Scope",
        repo or "global",
        "",
    ]
    if repo_summary:
        sections.extend(["## Repo memory", repo_summary, ""])
    if state:
        sections.extend(["## Operational state", state, ""])
    if memory_sections:
        sections.extend(memory_sections + [""])
    if compaction_section:
        sections.extend(["## Recent compactions", *compaction_section, ""])
    if domains:
        sections.extend(
            [
                "## Tool taxonomy",
                *[f"- {domain}: {', '.join(sorted(dict.fromkeys(tools)))}" for domain, tools in sorted(domains.items())],
                "",
            ]
        )
    metadata: dict[str, object] = {
        "name": name,
        "repo": repo,
        "agent_target": agent_target,
        "freshness_score": freshness,
        "tool_domains": sorted(domains),
        "generated_at": time.time(),
        "has_repo_memory": bool(repo_summary),
        "has_operational_state": bool(state),
    }
    return "\n".join(sections).strip(), metadata



def refresh_file_summaries(conn: sqlite3.Connection, repo: str | None = None, changed_only: bool = False) -> int:
    sql = (
        "SELECT repo, path, package, file_hash, language, kind FROM chunks "
        + ("WHERE repo = ? " if repo else "")
        + "GROUP BY repo, path, package, file_hash, language, kind ORDER BY repo, path"
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
            row["package"] or "",
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
