from __future__ import annotations

import argparse
import sqlite3
import urllib.request
from datetime import datetime
from pathlib import Path

from qdrant_client import models
from rich.table import Table

from .indexing import index_repo
from .llm import ask_llm, models_url
from .memory import (
    generate_repo_memory,
    refresh_file_summaries,
    repo_memory_status_rows,
    store_repo_memory,
)
from .retrieval import (
    RetrievalPlan,
    fact_hits,
    gather_context,
    print_retrieval_explain,
    reranker_enabled,
    retrieve,
)
from .runtime import CONFIG_PATH, DB_PATH, console
from .settings import get_index_profile, load_config
from .storage import connect_db, ensure_collection, get_qdrant, infer_repo_filter, resolve_repo_name, repo_identity
from .types import IndexInterrupted


def cmd_index(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    root = Path(args.path).expanduser().resolve()
    profile_name, profile = get_index_profile(config, args.profile)
    console.print(f"[cyan]Indexing[/cyan] {root} ...")
    try:
        changed_files, total_chunks = index_repo(
            conn, client, config, root, changed_only=args.changed_only, profile=profile
        )
    except IndexInterrupted as exc:
        console.print(
            f"[yellow]Cancelled.[/yellow] Kept {exc.changed_files} completed files and {exc.total_chunks} chunks. "
            "Rerun [bold]rag index --changed-only[/bold] to continue from the current directory."
        )
        return 130
    if profile["repo_memory"]:
        repo = repo_identity(root)[1]
        console.print(f"[cyan]Refreshing repo memory[/cyan] for {repo} ...")
        store_repo_memory(conn, repo, generate_repo_memory(conn, config, repo))
    console.print(
        f"[green]Indexed[/green] {changed_files} files and {total_chunks} chunks from {root} "
        f"(profile: {profile_name})"
    )
    return 0


def cmd_reindex(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    profile_name, profile = get_index_profile(config, args.profile)
    repos = conn.execute("SELECT root FROM indexed_repos ORDER BY repo").fetchall()
    if not repos:
        console.print("[yellow]No repos indexed yet.[/yellow]")
        return 0
    total_files = 0
    total_chunks = 0
    for row in repos:
        root = Path(row["root"])
        console.print(f"[cyan]Reindexing[/cyan] {root} ...")
        try:
            changed_files, chunks = index_repo(conn, client, config, root, changed_only=True, profile=profile)
        except IndexInterrupted as exc:
            total_files += exc.changed_files
            total_chunks += exc.total_chunks
            console.print(
                f"[yellow]Cancelled.[/yellow] Kept {total_files} completed files and {total_chunks} chunks so far."
            )
            return 130
        total_files += changed_files
        total_chunks += chunks
        if profile["repo_memory"]:
            repo = repo_identity(root)[1]
            console.print(f"[cyan]Refreshing repo memory[/cyan] for {repo} ...")
            store_repo_memory(conn, repo, generate_repo_memory(conn, config, repo))
    console.print(f"[green]Reindexed[/green] {total_files} changed files and {total_chunks} chunks (profile: {profile_name})")
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    collection_name = config["qdrant_collection"]
    points = 0
    if client.collection_exists(collection_name):
        points = int(client.get_collection(collection_name).points_count or 0)
    console.print("[bold]RAG status[/bold]")
    console.print(f"Config: {CONFIG_PATH}")
    console.print(f"SQLite: {DB_PATH}")
    console.print(f"Qdrant: {config['qdrant_url']}")
    console.print(f"Collection: {collection_name}")
    console.print()
    console.print(f"Repos indexed: {conn.execute('SELECT COUNT(*) FROM indexed_repos').fetchone()[0]}")
    console.print(f"Chunks: {conn.execute('SELECT COUNT(*) FROM chunks').fetchone()[0]}")
    console.print(f"Facts: {conn.execute('SELECT COUNT(*) FROM facts').fetchone()[0]}")
    console.print(f"File summaries: {conn.execute('SELECT COUNT(*) FROM file_summaries').fetchone()[0]}")
    console.print(f"Repo memories: {conn.execute('SELECT COUNT(*) FROM repo_memory').fetchone()[0]}")
    console.print(f"Embedding model: {config['embedding_model']}")
    console.print(f"Answer model: {config['answer_model']}")
    console.print(
        "Reranker: "
        + ("enabled" if config["reranker"]["enabled"] else "disabled")
        + f" ({config['reranker']['mode']})"
    )
    profile_name, _profile = get_index_profile(config, None)
    console.print(f"Index profile: {profile_name}")
    console.print(
        "Context budget: "
        f"{config['context_budget']['total_tokens']} total / "
        f"{config['context_budget']['memory_tokens']} memory / "
        f"{config['context_budget']['facts_tokens']} facts / "
        f"{config['context_budget']['file_summary_tokens']} summaries / "
        f"{config['context_budget']['chunk_tokens']} chunks / "
        f"{config['context_budget']['reserved_answer_tokens']} answer reserve"
    )
    console.print(
        "Retrieval diversity: "
        f"{config['retrieval']['max_chunks_per_file']} chunks/file, "
        f"{config['retrieval']['max_fact_files']} fact files, "
        f"{config['retrieval']['max_summary_files']} summary files"
    )
    memory_statuses = repo_memory_status_rows(conn)
    if memory_statuses:
        fresh = sum(1 for row in memory_statuses if row["status"] == "fresh")
        stale = sum(1 for row in memory_statuses if row["status"] == "stale")
        missing = sum(1 for row in memory_statuses if row["status"] == "missing")
        console.print(f"Repo memory freshness: {fresh} fresh, {stale} stale, {missing} missing")
    console.print("Last indexed:")
    rows = conn.execute(
        "SELECT repo, root, last_indexed FROM indexed_repos ORDER BY last_indexed DESC"
    ).fetchall()
    if not rows:
        console.print("- none")
    for row in rows:
        stamp = datetime.fromtimestamp(row["last_indexed"]).strftime("%Y-%m-%d %H:%M")
        console.print(f"- {row['repo']}  {stamp}  {row['root']}")
    console.print(f"Qdrant points: {points}")
    return 0


def cmd_clean(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    ensure_collection(client, config)
    if args.all:
        if client.collection_exists(config["qdrant_collection"]):
            client.delete_collection(config["qdrant_collection"])
        conn.execute("DELETE FROM chunks")
        conn.execute("DELETE FROM chunks_fts")
        conn.execute("DELETE FROM facts")
        conn.execute("DELETE FROM file_summaries")
        conn.execute("DELETE FROM repo_memory")
        conn.execute("DELETE FROM indexed_repos")
        conn.commit()
        ensure_collection(client, config)
        console.print("[green]Cleared[/green] all local RAG state")
        return 0
    repo = args.repo
    if not repo:
        raise SystemExit("Use rag clean --repo <name> or rag clean --all")
    rows = conn.execute("SELECT chunk_id FROM chunks WHERE repo = ?", (repo,)).fetchall()
    ids = [row["chunk_id"] for row in rows]
    if ids:
        client.delete(
            collection_name=config["qdrant_collection"],
            points_selector=models.PointIdsList(points=ids),
            wait=True,
        )
    conn.execute("DELETE FROM chunks WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM chunks_fts WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM facts WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM file_summaries WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM repo_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM indexed_repos WHERE repo = ?", (repo,))
    conn.commit()
    console.print(f"[green]Cleared[/green] repo state for {repo}")
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    repo = infer_repo_filter(conn, args.repo)
    result = retrieve(conn, client, config, args.query, repo, reranker_enabled(config, args.rerank))
    if args.explain:
        print_retrieval_explain(result.debug, result.rows)
        console.print()
    table = Table(title="RAG search results")
    table.add_column("#", justify="right")
    table.add_column("file")
    table.add_column("kind")
    table.add_column("symbol")
    table.add_column("preview")
    for index, row in enumerate(result.rows[:10], start=1):
        preview = row["content"].strip().replace("\n", " ")
        table.add_row(
            str(index),
            f"{row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}",
            row["kind"],
            row["symbol"] or "-",
            preview[:120],
        )
    console.print(table)
    return 0


def cmd_ask(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    repo = infer_repo_filter(conn, args.repo)
    result = retrieve(conn, client, config, args.query, repo, reranker_enabled(config, args.rerank))
    if not result.rows:
        console.print("[yellow]No indexed context matched that query.[/yellow]")
        return 1
    context, files = gather_context(
        result.rows,
        config,
        facts=result.facts,
        summaries=result.summaries,
        memory=result.memory["summary"] if args.memory and result.memory else None,
    )
    if args.show_context:
        print_retrieval_explain(result.debug, result.rows)
        console.print("\n[bold]Context:[/bold]")
        console.print(context)
        console.print()
    answer = ask_llm(config, args.query, context)
    console.print("[bold]Answer:[/bold]")
    console.print(answer or "[red]No answer returned.[/red]")
    console.print("\n[bold]Relevant files:[/bold]")
    for item in files:
        console.print(f"- {item}")
    return 0


def cmd_summarize_files(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    refreshed = refresh_file_summaries(conn, repo=repo, changed_only=args.changed_only)
    scope = repo or "all indexed repos"
    console.print(f"[green]Refreshed[/green] {refreshed} file summaries for {scope}")
    return 0


def cmd_summarize(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if not repo:
        raise SystemExit("No repo selected. Use --repo or run inside an indexed repo.")
    console.print(f"[cyan]Summarizing[/cyan] {repo} ...")
    summary = generate_repo_memory(conn, config, repo)
    store_repo_memory(conn, repo, summary)
    console.print(f"[green]Stored[/green] repo memory for {repo}")
    return 0


def cmd_memory(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.memory_command == "status":
        rows = repo_memory_status_rows(conn, repo)
        if not rows:
            console.print("[yellow]No indexed repos yet.[/yellow]")
            return 0
        table = Table(title="Repo memory status")
        table.add_column("repo")
        table.add_column("status")
        table.add_column("memory")
        table.add_column("detail")
        for row in rows:
            memory_updated = (
                datetime.fromtimestamp(row["memory_updated_at"]).strftime("%Y-%m-%d %H:%M")
                if row["memory_updated_at"]
                else "-"
            )
            detail = "; ".join(row["reasons"]) if row["reasons"] else f"{row['chunk_count']} chunks"
            table.add_row(row["repo"], str(row["status"]), memory_updated, detail)
        console.print(table)
        return 0
    if args.memory_command == "show":
        if not repo:
            raise SystemExit("No repo selected. Use --repo or run inside an indexed repo.")
        row = conn.execute("SELECT summary FROM repo_memory WHERE repo = ?", (repo,)).fetchone()
        if row is None:
            console.print(f"[yellow]No repo memory stored for {repo}.[/yellow]")
            return 0
        console.print(row["summary"])
        return 0
    if args.memory_command == "refresh":
        if not repo:
            raise SystemExit("No repo selected. Use --repo or run inside an indexed repo.")
        summary = generate_repo_memory(conn, config, repo)
        store_repo_memory(conn, repo, summary)
        console.print(f"[green]Refreshed[/green] repo memory for {repo}")
        return 0
    if args.memory_command == "clear":
        if args.all:
            conn.execute("DELETE FROM repo_memory")
            conn.commit()
            console.print("[green]Cleared[/green] all repo memory")
            return 0
        if not repo:
            raise SystemExit("No repo selected. Use --repo, run inside an indexed repo, or use --all.")
        conn.execute("DELETE FROM repo_memory WHERE repo = ?", (repo,))
        conn.commit()
        console.print(f"[green]Cleared[/green] repo memory for {repo}")
        return 0
    raise SystemExit(f"Unknown memory command: {args.memory_command}")


def cmd_facts(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.subject == "list":
        sql = "SELECT repo, path, kind, key, value, line FROM facts"
        params: list[str] = []
        clauses: list[str] = []
        if repo:
            clauses.append("repo = ?")
            params.append(repo)
        if args.kind:
            clauses.append("kind = ?")
            params.append(args.kind)
        if clauses:
            sql += " WHERE " + " AND ".join(clauses)
        sql += " ORDER BY repo, path, line LIMIT 40"
        rows = conn.execute(sql, params).fetchall()
    else:
        if not args.query:
            raise SystemExit("Use `rag facts list` or `rag facts <kind> <query>`")
        query = " ".join(args.query)
        sql = "SELECT repo, path, kind, key, value, line FROM facts WHERE kind = ? AND (key LIKE ? OR value LIKE ?)"
        params = [args.subject, f"%{query}%", f"%{query}%"]
        if repo:
            sql += " AND repo = ?"
            params.append(repo)
        sql += " ORDER BY confidence DESC, updated_at DESC LIMIT 30"
        rows = conn.execute(sql, params).fetchall()
    table = Table(title="RAG facts")
    table.add_column("kind")
    table.add_column("key")
    table.add_column("value")
    table.add_column("file")
    for row in rows:
        table.add_row(row["kind"], row["key"], str(row["value"])[:80], f"{row['repo']}/{row['path']}:{row['line']}")
    console.print(table)
    return 0


def trace_fact_rows(
    conn: sqlite3.Connection,
    config: dict,
    kind: str,
    query: str,
    repo: str | None,
    limit: int,
) -> list[sqlite3.Row]:
    if kind == "keybind":
        plan = RetrievalPlan(query=query, repo=repo, rewrites=[], intent="keybind")
        return fact_hits(conn, plan, config)[:limit]
    sql = """
        SELECT fact_id, repo, path, kind, key, value, line, confidence, updated_at
        FROM facts
        WHERE kind = ? AND (key LIKE ? OR value LIKE ? OR path LIKE ?)
    """
    params: list[object] = [kind, f"%{query}%", f"%{query}%", f"%{query}%"]
    if repo:
        sql += " AND repo = ?"
        params.append(repo)
    sql += " ORDER BY confidence DESC, updated_at DESC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()


def trace_nearby_chunks(
    conn: sqlite3.Connection,
    repo: str,
    path: str,
    line: int,
    limit: int = 2,
) -> list[sqlite3.Row]:
    return conn.execute(
        """
        SELECT repo, path, start_line, end_line, kind, language, symbol, content,
               CASE
                   WHEN start_line <= ? AND end_line >= ? THEN 0
                   ELSE MIN(ABS(start_line - ?), ABS(end_line - ?))
               END AS distance
        FROM chunks
        WHERE repo = ? AND path = ?
        ORDER BY distance ASC, start_line ASC
        LIMIT ?
        """,
        (line, line, line, line, repo, path, limit),
    ).fetchall()


def cmd_trace(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    query = " ".join(args.query)
    rows = trace_fact_rows(conn, config, args.kind, query, repo, args.limit)
    if not rows:
        console.print("[yellow]No matching facts found.[/yellow]")
        return 1
    table = Table(title=f"RAG trace: {args.kind}")
    table.add_column("#", justify="right")
    table.add_column("key")
    table.add_column("value")
    table.add_column("file")
    for index, row in enumerate(rows, start=1):
        table.add_row(
            str(index),
            row["key"],
            str(row["value"])[:90],
            f"{row['repo']}/{row['path']}:{row['line']}",
        )
    console.print(table)
    for index, row in enumerate(rows, start=1):
        console.print()
        console.print(f"[bold]{index}. {row['repo']}/{row['path']}:{row['line']}[/bold]")
        console.print(f"kind={row['kind']} key={row['key']}")
        console.print(f"value={row['value']}")
        chunks = trace_nearby_chunks(conn, row["repo"], row["path"], int(row["line"]))
        if not chunks:
            continue
        console.print("[dim]Nearby evidence[/dim]")
        for chunk in chunks:
            console.print(
                f"- {chunk['start_line']}-{chunk['end_line']} {chunk['kind']} {chunk['symbol'] or '-'}"
            )
            console.print(chunk["content"].strip())
    return 0


def cmd_doctor(_args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    table = Table(title="RAG doctor")
    table.add_column("check")
    table.add_column("status")
    table.add_column("detail")
    try:
        client.get_collections()
        table.add_row("qdrant", "ok", config["qdrant_url"])
    except Exception as exc:  # pragma: no cover
        table.add_row("qdrant", "fail", str(exc))
        console.print(table)
        return 1
    try:
        collection = client.get_collection(config["qdrant_collection"])
        points = str(collection.points_count)
    except Exception:
        points = "0"
    table.add_row("collection", "ok", f"{config['qdrant_collection']} ({points} points)")
    repo_count = conn.execute("SELECT COUNT(*) AS count FROM indexed_repos").fetchone()["count"]
    chunk_count = conn.execute("SELECT COUNT(*) AS count FROM chunks").fetchone()["count"]
    table.add_row("sqlite", "ok", f"{repo_count} repos, {chunk_count} chunks")
    fact_count = conn.execute("SELECT COUNT(*) AS count FROM facts").fetchone()["count"]
    summary_count = conn.execute("SELECT COUNT(*) AS count FROM file_summaries").fetchone()["count"]
    memory_count = conn.execute("SELECT COUNT(*) AS count FROM repo_memory").fetchone()["count"]
    table.add_row("memory", "ok", f"{fact_count} facts, {summary_count} file summaries, {memory_count} repo memories")
    try:
        with urllib.request.urlopen(
            urllib.request.Request(
                models_url(config["answer_url"]),
                headers={"Content-Type": "application/json"},
            ),
            timeout=5,
        ):
            pass
        table.add_row("answer model", "ok", config["answer_model"])
    except Exception as exc:  # pragma: no cover
        table.add_row("answer model", "fail", str(exc))
    table.add_row("embedding model", "ok", config["embedding_model"])
    table.add_row(
        "reranker",
        "ok" if config["reranker"]["enabled"] else "off",
        f"{config['reranker']['mode']} (top {config['reranker']['top_k_output']})",
    )
    profile_name, _profile = get_index_profile(config, None)
    table.add_row("index profile", "ok", profile_name)
    table.add_row(
        "context budget",
        "ok",
        (
            f"total={config['context_budget']['total_tokens']} "
            f"memory={config['context_budget']['memory_tokens']} "
            f"facts={config['context_budget']['facts_tokens']} "
            f"summaries={config['context_budget']['file_summary_tokens']} "
            f"chunks={config['context_budget']['chunk_tokens']}"
        ),
    )
    memory_statuses = repo_memory_status_rows(conn)
    stale_count = sum(1 for row in memory_statuses if row["status"] == "stale")
    missing_count = sum(1 for row in memory_statuses if row["status"] == "missing")
    table.add_row("memory freshness", "ok" if not stale_count and not missing_count else "warn", f"{stale_count} stale, {missing_count} missing")
    console.print(table)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="rag")
    subparsers = parser.add_subparsers(dest="command", required=True)

    index_parser = subparsers.add_parser("index", help="Index a repo or folder")
    index_parser.add_argument(
        "path",
        nargs="?",
        default=".",
        help="Repo or folder to index (defaults to the current directory).",
    )
    index_parser.add_argument(
        "--changed-only",
        action="store_true",
        help="Skip files whose content hash has not changed.",
    )
    index_parser.add_argument(
        "--profile",
        choices=["fast", "balanced", "deep"],
        help="Indexing profile to use (defaults to config indexing.profile).",
    )
    index_parser.set_defaults(func=cmd_index)

    ask_parser = subparsers.add_parser("ask", help="Ask a question against the local index")
    ask_parser.add_argument("query")
    ask_parser.add_argument("--repo", help="Filter to a repo name")
    ask_parser.add_argument(
        "--memory",
        action="store_true",
        help="Prepend stored repo memory before facts, file summaries, and chunks.",
    )
    ask_parser.add_argument(
        "--show-context",
        action="store_true",
        help="Print the packed retrieval context before the answer.",
    )
    ask_rerank_group = ask_parser.add_mutually_exclusive_group()
    ask_rerank_group.add_argument(
        "--rerank",
        dest="rerank",
        action="store_true",
        default=None,
        help="Force the reranker on for this query.",
    )
    ask_rerank_group.add_argument(
        "--no-rerank",
        dest="rerank",
        action="store_false",
        help="Skip the reranker for this query.",
    )
    ask_parser.set_defaults(func=cmd_ask)

    search_parser = subparsers.add_parser("search", help="Search indexed chunks")
    search_parser.add_argument("query")
    search_parser.add_argument("--repo", help="Filter to a repo name")
    search_parser.add_argument(
        "--explain",
        action="store_true",
        help="Show query rewrites and retrieval-stage counts before the results.",
    )
    search_rerank_group = search_parser.add_mutually_exclusive_group()
    search_rerank_group.add_argument(
        "--rerank",
        dest="rerank",
        action="store_true",
        default=None,
        help="Force the reranker on for this query.",
    )
    search_rerank_group.add_argument(
        "--no-rerank",
        dest="rerank",
        action="store_false",
        help="Skip the reranker for this query.",
    )
    search_parser.set_defaults(func=cmd_search)

    reindex_parser = subparsers.add_parser("reindex", help="Reindex changed files in previously indexed repos")
    reindex_parser.add_argument(
        "--profile",
        choices=["fast", "balanced", "deep"],
        help="Indexing profile to use (defaults to config indexing.profile).",
    )
    reindex_parser.set_defaults(func=cmd_reindex)

    summarize_files_parser = subparsers.add_parser(
        "summarize-files",
        help="Refresh file summaries from indexed chunks and facts",
    )
    summarize_files_parser.add_argument("--repo", help="Refresh summaries for one repo")
    summarize_files_parser.add_argument(
        "--changed-only",
        action="store_true",
        help="Only refresh summaries whose file hash no longer matches.",
    )
    summarize_files_parser.set_defaults(func=cmd_summarize_files)

    summarize_parser = subparsers.add_parser("summarize", help="Generate durable repo memory")
    summarize_parser.add_argument("--repo", help="Summarize one indexed repo")
    summarize_parser.set_defaults(func=cmd_summarize)

    memory_parser = subparsers.add_parser("memory", help="Show, refresh, clear, or inspect repo memory")
    memory_parser.add_argument("memory_command", choices=["show", "refresh", "clear", "status"])
    memory_parser.add_argument("--repo", help="Target repo name")
    memory_parser.add_argument("--all", action="store_true", help="Apply clear to all repos")
    memory_parser.set_defaults(func=cmd_memory)

    facts_parser = subparsers.add_parser("facts", help="List or query structured facts")
    facts_parser.add_argument("subject", help="Use `list` or a fact kind like alias, keybind, env, tool, sql-object")
    facts_parser.add_argument("query", nargs="*", help="Search text when querying a fact kind")
    facts_parser.add_argument("--repo", help="Filter to one repo")
    facts_parser.add_argument("--kind", help="Fact kind filter when using `rag facts list`")
    facts_parser.set_defaults(func=cmd_facts)

    trace_parser = subparsers.add_parser("trace", help="Trace facts back to nearby indexed evidence")
    trace_parser.add_argument("kind", help="Fact kind to trace, like keybind, tool, alias, env, or sql-object")
    trace_parser.add_argument("query", nargs="+", help="Search text for the trace query")
    trace_parser.add_argument("--repo", help="Filter to one repo")
    trace_parser.add_argument("--limit", type=int, default=5, help="Maximum fact matches to trace")
    trace_parser.set_defaults(func=cmd_trace)

    status_parser = subparsers.add_parser("status", help="Show quick local RAG status")
    status_parser.set_defaults(func=cmd_status)

    clean_parser = subparsers.add_parser("clean", help="Clear repo-specific or full local RAG state")
    clean_scope = clean_parser.add_mutually_exclusive_group(required=True)
    clean_scope.add_argument("--repo", help="Clear one indexed repo by name")
    clean_scope.add_argument("--all", action="store_true", help="Clear the whole local RAG index")
    clean_parser.set_defaults(func=cmd_clean)

    doctor_parser = subparsers.add_parser("doctor", help="Check local RAG health")
    doctor_parser.set_defaults(func=cmd_doctor)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except KeyboardInterrupt:
        console.print("[yellow]Cancelled.[/yellow]")
        return 130
    except sqlite3.OperationalError as exc:
        if "database is locked" in str(exc).lower():
            console.print(
                "[yellow]RAG database is busy.[/yellow] Another rag command is already using the local index. "
                "Wait for it to finish or stop it, then retry."
            )
            return 1
        raise
