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
    build_context_pack,
    generate_repo_memory,
    list_tool_taxonomy,
    refresh_file_summaries,
    repo_memory_status_rows,
    store_repo_memory,
    store_context_pack,
    write_context_pack_file,
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
from .settings import get_index_profile, get_mode_profile, load_config
from .state import (
    add_command,
    add_decision,
    add_error,
    add_todo,
    compact_session,
    detect_memory_conflicts,
    format_operational_state,
    get_session,
    list_commands,
    list_decisions,
    list_errors,
    list_memory_entries,
    list_sessions,
    list_todos,
    load_operational_state,
    record_session,
    remember_memory,
    save_handoff,
    session_compaction_details,
    session_files,
    update_todo_status,
)
from .storage import connect_db, ensure_collection, get_qdrant, infer_repo_filter, resolve_repo_name, repo_identity
from .types import IndexInterrupted


def route_mode(query: str) -> tuple[str, str]:
    lowered = query.lower()
    terms = lowered.split()
    agent_markers = (
        "agent",
        "handoff",
        "codex",
        "copilot",
        "opencode",
        "implement",
        "migration",
        "multi-step",
        "prepare context",
        "task graph",
    )
    deep_markers = (
        "review",
        "architecture",
        "analyze",
        "debug",
        "investigate",
        "cleanup",
        "refactor",
        "plan",
        "workflow",
        "broken",
        "failing",
        "why",
    )
    if any(marker in lowered for marker in agent_markers):
        return "agent", "matched long-running implementation or handoff language"
    if "\n" in query or len(terms) >= 18 or any(marker in lowered for marker in deep_markers):
        return "deep", "matched analysis/debug depth heuristics"
    return "quick", "defaulted to the fast question path"


def resolved_mode(args: argparse.Namespace, config: dict) -> tuple[str, str]:
    requested = getattr(args, "mode", None) or config["routing"]["default_mode"]
    if requested and requested != "auto":
        return requested, f"explicit {requested} mode"
    return route_mode(args.query)


def optional_repo_memory(args: argparse.Namespace, result, mode_config: dict) -> str | None:
    use_memory = bool(mode_config["answer"]["use_memory"])
    if getattr(args, "memory", False):
        use_memory = True
    return result.memory["summary"] if use_memory and result.memory else None


def render_handoff(
    query: str,
    repo: str | None,
    route_reason: str,
    context: str,
    files: list[str],
    state_text: str | None,
    *,
    target_agent: str = "generic",
) -> str:
    file_lines = [f"- {item}" for item in files] if files else ["- none captured"]
    template_titles = {
        "generic": "Coding agent handoff",
        "codex": "Codex implementation handoff",
        "opencode": "OpenCode execution handoff",
        "copilot": "Copilot coding handoff",
        "human": "Human collaborator handoff",
    }
    template_steps = {
        "generic": [
            "- Re-open the important files and validate the retrieved context before editing.",
            "- Turn any incomplete items into concrete code/test tasks.",
            "- Keep changes small, then rerun the relevant tests.",
        ],
        "codex": [
            "- Start with the important files and convert the goal into precise code edits.",
            "- Preserve existing CLI surfaces unless a retrieved constraint requires otherwise.",
            "- Finish by rerunning the closest existing tests before handing back.",
        ],
        "opencode": [
            "- Use the retrieved files as the narrow execution scope.",
            "- Prefer patch-sized edits and keep shell commands reproducible.",
            "- Update tightly coupled docs/tests before closing the task.",
        ],
        "copilot": [
            "- Rehydrate the task from the retrieved context and operational memory first.",
            "- Keep the SQLite-first architecture intact while implementing the requested feature.",
            "- Return concise progress plus any residual risks after validation.",
        ],
        "human": [
            "- Read the goal and important files before planning any edits.",
            "- Validate assumptions against the retrieved context and operational state.",
            "- Use the suggested steps as a checklist for implementation and verification.",
        ],
    }
    sections = [
        f"# {template_titles.get(target_agent, template_titles['generic'])}",
        "",
        "## Goal",
        query,
        "",
        "## Target agent",
        target_agent,
        "",
        "## Target repo",
        repo or "unscoped",
        "",
        "## Constraints",
        "- Stay grounded in retrieved files and state.",
        "- Preserve current CLI compatibility surfaces unless the code demands otherwise.",
        "- Prefer retrieval/ranking/state improvements over extra helper-model chains.",
        "",
        "## Routing",
        f"- mode: agent",
        f"- reason: {route_reason}",
        "",
    ]
    if state_text:
        sections.extend(["## Operational state", state_text, ""])
    sections.extend(
        [
            "## Important files",
            *file_lines,
            "",
            "## Retrieved context",
            context or "No context packed.",
            "",
            "## Suggested first steps",
            *template_steps.get(target_agent, template_steps["generic"]),
        ]
    )
    return "\n".join(sections).strip()


def run_query_mode(args: argparse.Namespace) -> int:
    config = load_config()
    mode, route_reason = resolved_mode(args, config)
    effective_config = get_mode_profile(config, mode)
    conn = connect_db()
    client = get_qdrant(effective_config)
    repo = infer_repo_filter(conn, getattr(args, "repo", None))
    result = retrieve(
        conn,
        client,
        effective_config,
        args.query,
        repo,
        reranker_enabled(effective_config, getattr(args, "rerank", None)),
        mode=mode,
    )
    if not result.rows:
        console.print("[yellow]No indexed context matched that query.[/yellow]")
        return 1
    state_text: str | None = None
    if effective_config["answer"]["use_operational_state"]:
        state_text = format_operational_state(load_operational_state(conn, repo))
    context, files = gather_context(
        result.rows,
        effective_config,
        facts=result.facts,
        summaries=result.summaries,
        memory=optional_repo_memory(args, result, effective_config),
        operational_state=state_text,
        operational_state_tokens=int(effective_config["answer"]["operational_state_tokens"]),
    )
    if getattr(args, "show_context", False):
        print_retrieval_explain(result.debug, result.rows)
        console.print(f"\n[bold]Route:[/bold] {mode} ({route_reason})")
        console.print("\n[bold]Context:[/bold]")
        console.print(context)
        console.print()
    target_agent = getattr(args, "target_agent", "generic")
    if mode == "agent" and getattr(args, "output_format", "handoff") == "handoff":
        output = render_handoff(
            args.query,
            repo,
            route_reason,
            context,
            files,
            state_text,
            target_agent=target_agent,
        )
        console.print(output)
        session_id = record_session(conn, repo, mode, args.query, route_reason, "handoff", output, files)
        compact_session(conn, session_id)
        if getattr(args, "save_handoff", False):
            handoff_path = save_handoff(repo, args.query, output)
            console.print(f"\n[green]Saved[/green] handoff to {handoff_path}")
        console.print(f"\n[dim]Session {session_id} saved.[/dim]")
        return 0
    answer = ask_llm(effective_config, args.query, context, mode=mode)
    console.print(f"[bold]{mode.title()} answer:[/bold]")
    console.print(answer or "[red]No answer returned.[/red]")
    console.print("\n[bold]Relevant files:[/bold]")
    for item in files:
        console.print(f"- {item}")
    session_id = record_session(conn, repo, mode, args.query, route_reason, "answer", answer, files)
    if mode in {"deep", "agent"}:
        compact_session(conn, session_id)
    console.print(f"\n[dim]Session {session_id} saved.[/dim]")
    return 0


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
    console.print(f"Memory notes: {conn.execute('SELECT COUNT(*) FROM developer_memory').fetchone()[0]}")
    console.print(f"Context packs: {conn.execute('SELECT COUNT(*) FROM context_packs').fetchone()[0]}")
    console.print(f"Todos: {conn.execute('SELECT COUNT(*) FROM task_todos').fetchone()[0]}")
    console.print(f"Decisions: {conn.execute('SELECT COUNT(*) FROM task_decisions').fetchone()[0]}")
    console.print(f"Sessions: {conn.execute('SELECT COUNT(*) FROM task_sessions').fetchone()[0]}")
    console.print(f"Session compactions: {conn.execute('SELECT COUNT(*) FROM session_compactions').fetchone()[0]}")
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
        conn.execute("DELETE FROM developer_memory")
        conn.execute("DELETE FROM context_packs")
        conn.execute("DELETE FROM indexed_repos")
        conn.execute("DELETE FROM task_todos")
        conn.execute("DELETE FROM task_decisions")
        conn.execute("DELETE FROM command_memory")
        conn.execute("DELETE FROM error_memory")
        conn.execute("DELETE FROM task_sessions")
        conn.execute("DELETE FROM session_compactions")
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
    conn.execute("DELETE FROM developer_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM context_packs WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM indexed_repos WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM task_todos WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM task_decisions WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM command_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM error_memory WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM task_sessions WHERE repo = ?", (repo,))
    conn.execute("DELETE FROM session_compactions WHERE repo = ?", (repo,))
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
    return run_query_mode(args)


def cmd_quick(args: argparse.Namespace) -> int:
    args.mode = "quick"
    return run_query_mode(args)


def cmd_deep(args: argparse.Namespace) -> int:
    args.mode = "deep"
    return run_query_mode(args)


def cmd_agent(args: argparse.Namespace) -> int:
    args.mode = "agent"
    return run_query_mode(args)


def cmd_handoff(args: argparse.Namespace) -> int:
    args.mode = "agent"
    args.output_format = "handoff"
    args.target_agent = args.target
    return run_query_mode(args)


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
    repo = resolve_repo_name(conn, getattr(args, "repo", None))
    if args.memory_command == "status":
        rows = repo_memory_status_rows(conn, repo)
        if not rows:
            console.print("[yellow]No indexed repos yet.[/yellow]")
            return 0
        table = Table(title="Repo memory status")
        table.add_column("repo")
        table.add_column("status")
        table.add_column("memory")
        table.add_column("freshness")
        table.add_column("detail")
        for row in rows:
            memory_updated = (
                datetime.fromtimestamp(row["memory_updated_at"]).strftime("%Y-%m-%d %H:%M")
                if row["memory_updated_at"]
                else "-"
            )
            detail = "; ".join(row["reasons"]) if row["reasons"] else f"{row['chunk_count']} chunks"
            table.add_row(row["repo"], str(row["status"]), memory_updated, str(row["freshness_score"]), detail)
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
    if args.memory_command == "remember":
        memory_id = remember_memory(
            conn,
            repo,
            args.kind,
            args.subject,
            " ".join(args.value),
            global_scope=args.global_scope,
        )
        console.print(f"[green]Stored[/green] memory {memory_id}")
        return 0
    if args.memory_command == "notes":
        rows = list_memory_entries(
            conn,
            repo,
            kind=args.kind,
            limit=args.limit,
            scope=args.scope,
            status=args.status,
        )
        table = Table(title="RAG memory notes")
        table.add_column("id", justify="right")
        table.add_column("kind")
        table.add_column("subject")
        table.add_column("value")
        table.add_column("scope")
        table.add_column("status")
        for row in rows:
            table.add_row(
                str(row["memory_id"]),
                row["kind"],
                row["subject"],
                str(row["value"])[:80],
                row["repo"] or "global",
                row["status"],
            )
        console.print(table)
        return 0
    if args.memory_command == "conflicts":
        rows = detect_memory_conflicts(conn, repo, limit=args.limit)
        if not rows:
            console.print("[green]No memory conflicts detected.[/green]")
            return 0
        table = Table(title="RAG memory conflicts")
        table.add_column("kind")
        table.add_column("subject")
        table.add_column("scope")
        table.add_column("values")
        for row in rows:
            table.add_row(
                str(row["kind"]),
                str(row["subject"]),
                str(row["repo"] or "global"),
                " | ".join(str(value) for value in row["values"]),
            )
        console.print(table)
        return 0
    if args.memory_command == "compact":
        if args.session_id:
            row = compact_session(conn, args.session_id)
            if row is None:
                console.print(f"[yellow]Session {args.session_id} not found.[/yellow]")
                return 1
            console.print(row["summary"])
            return 0
        rows = conn.execute(
            "SELECT * FROM session_compactions"
            + (" WHERE repo = ?" if repo else "")
            + " ORDER BY updated_at DESC LIMIT ?",
            ([repo] if repo else []) + [args.limit],
        ).fetchall()
        table = Table(title="RAG session compactions")
        table.add_column("session")
        table.add_column("mode")
        table.add_column("summary")
        table.add_column("signals")
        for row in rows:
            details = session_compaction_details(row)
            signals = []
            for key in ("todos", "commands", "errors"):
                values = details.get(key) or []
                if values:
                    signals.append(f"{key}:{len(values)}")
            table.add_row(row["session_id"], row["mode"], row["summary"][:100], ", ".join(signals) or "-")
        console.print(table)
        return 0
    if args.memory_command == "pack":
        content, metadata = build_context_pack(conn, repo, args.name, agent_target=args.target_agent)
        store_context_pack(conn, repo, args.name, content, metadata, agent_target=args.target_agent)
        console.print(content)
        if args.write_file:
            if not repo:
                raise SystemExit("Use --repo or run inside an indexed repo to write a .context file.")
            root_row = conn.execute("SELECT root FROM indexed_repos WHERE repo = ?", (repo,)).fetchone()
            if root_row is None:
                raise SystemExit(f"Repo not indexed: {repo}")
            path = write_context_pack_file(Path(root_row["root"]), args.name, content)
            console.print(f"\n[green]Saved[/green] {path}")
        return 0
    if args.memory_command == "taxonomy":
        rows = list_tool_taxonomy(conn, domain=args.domain, query=args.query, limit=args.limit)
        if args.format == "yaml":
            grouped: dict[str, list[str]] = {}
            for row in rows:
                grouped.setdefault(str(row["domain"]), []).append(str(row["tool"]))
            for domain, tools in grouped.items():
                console.print(f"{domain}:\n  tools: [{', '.join(tools)}]")
            return 0
        table = Table(title="RAG tool taxonomy")
        table.add_column("domain")
        table.add_column("tool")
        table.add_column("aliases")
        table.add_column("description")
        for row in rows:
            table.add_row(row["domain"], row["tool"], row["aliases"], row["description"] or "-")
        console.print(table)
        return 0
    raise SystemExit(f"Unknown memory command: {args.memory_command}")


def cmd_todo(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.todo_command == "list":
        rows = list_todos(conn, repo, args.status, args.limit)
        table = Table(title="RAG todos")
        table.add_column("id", justify="right")
        table.add_column("status")
        table.add_column("title")
        table.add_column("repo")
        for row in rows:
            table.add_row(str(row["todo_id"]), row["status"], row["title"], row["repo"] or "-")
        console.print(table)
        return 0
    if args.todo_command == "add":
        todo_id = add_todo(conn, repo, args.title, detail=args.detail, status=args.status)
        console.print(f"[green]Added[/green] todo {todo_id}")
        return 0
    if args.todo_command == "done":
        if not update_todo_status(conn, args.todo_id, "done"):
            console.print(f"[yellow]Todo {args.todo_id} not found.[/yellow]")
            return 1
        console.print(f"[green]Completed[/green] todo {args.todo_id}")
        return 0
    if args.todo_command == "start":
        if not update_todo_status(conn, args.todo_id, "in_progress"):
            console.print(f"[yellow]Todo {args.todo_id} not found.[/yellow]")
            return 1
        console.print(f"[green]Marked[/green] todo {args.todo_id} in progress")
        return 0
    raise SystemExit(f"Unknown todo command: {args.todo_command}")


def cmd_decision(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.decision_command == "list":
        rows = list_decisions(conn, repo, args.limit)
        table = Table(title="RAG decisions")
        table.add_column("id", justify="right")
        table.add_column("title")
        table.add_column("detail")
        table.add_column("repo")
        for row in rows:
            table.add_row(str(row["decision_id"]), row["title"], row["detail"][:100], row["repo"] or "-")
        console.print(table)
        return 0
    decision_id = add_decision(conn, repo, args.title, args.detail, rationale=args.rationale)
    console.print(f"[green]Added[/green] decision {decision_id}")
    return 0


def cmd_command_memory(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.command_memory_command == "list":
        rows = list_commands(conn, repo, args.limit)
        table = Table(title="RAG commands")
        table.add_column("id", justify="right")
        table.add_column("command")
        table.add_column("purpose")
        table.add_column("repo")
        for row in rows:
            table.add_row(str(row["command_id"]), row["command"], row["purpose"] or "-", row["repo"] or "-")
        console.print(table)
        return 0
    command_id = add_command(conn, repo, args.command_text, purpose=args.purpose, notes=args.notes)
    console.print(f"[green]Added[/green] command {command_id}")
    return 0


def cmd_error_memory(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.error_command == "list":
        rows = list_errors(conn, repo, args.limit)
        table = Table(title="RAG errors")
        table.add_column("id", justify="right")
        table.add_column("error")
        table.add_column("fix")
        table.add_column("repo")
        for row in rows:
            table.add_row(str(row["error_id"]), row["error_text"][:80], (row["fix_text"] or "-")[:80], row["repo"] or "-")
        console.print(table)
        return 0
    error_id = add_error(conn, repo, args.error_text, fix_text=args.fix, notes=args.notes)
    console.print(f"[green]Added[/green] error {error_id}")
    return 0


def cmd_session(args: argparse.Namespace) -> int:
    conn = connect_db()
    repo = resolve_repo_name(conn, args.repo)
    if args.session_command == "list":
        rows = list_sessions(conn, repo, args.limit)
        table = Table(title="RAG sessions")
        table.add_column("id")
        table.add_column("mode")
        table.add_column("kind")
        table.add_column("query")
        for row in rows:
            table.add_row(row["session_id"], row["mode"], row["output_kind"], row["query"][:90])
        console.print(table)
        return 0
    row = get_session(conn, args.session_id)
    if row is None:
        console.print(f"[yellow]Session {args.session_id} not found.[/yellow]")
        return 1
    console.print(f"[bold]Session[/bold] {row['session_id']} [{row['mode']}]")
    console.print(f"Repo: {row['repo'] or 'unscoped'}")
    console.print(f"Reason: {row['route_reason']}")
    console.print("\n[bold]Query:[/bold]")
    console.print(row["query"])
    console.print("\n[bold]Output:[/bold]")
    console.print(row["output_text"])
    files = session_files(row)
    if files:
        console.print("\n[bold]Files:[/bold]")
        for item in files:
            console.print(f"- {item}")
    return 0


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
        plan = RetrievalPlan(query=query, repo=repo, rewrites=[], intent="keybind", mode="quick")
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
    todo_count = conn.execute("SELECT COUNT(*) AS count FROM task_todos").fetchone()["count"]
    decision_count = conn.execute("SELECT COUNT(*) AS count FROM task_decisions").fetchone()["count"]
    session_count = conn.execute("SELECT COUNT(*) AS count FROM task_sessions").fetchone()["count"]
    memory_note_count = conn.execute("SELECT COUNT(*) AS count FROM developer_memory").fetchone()["count"]
    context_pack_count = conn.execute("SELECT COUNT(*) AS count FROM context_packs").fetchone()["count"]
    compaction_count = conn.execute("SELECT COUNT(*) AS count FROM session_compactions").fetchone()["count"]
    table.add_row(
        "memory",
        "ok",
        (
            f"{fact_count} facts, {summary_count} file summaries, {memory_count} repo memories, "
            f"{memory_note_count} memory notes, {context_pack_count} context packs, "
            f"{todo_count} todos, {decision_count} decisions, {session_count} sessions, "
            f"{compaction_count} compactions"
        ),
    )
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

    def add_query_parser(
        name: str,
        help_text: str,
        handler,
        *,
        include_mode_flag: bool = False,
        default_output_format: str = "answer",
    ) -> argparse.ArgumentParser:
        query_parser = subparsers.add_parser(name, help=help_text)
        query_parser.add_argument("query")
        query_parser.add_argument("--repo", help="Filter to a repo name")
        query_parser.add_argument(
            "--memory",
            action="store_true",
            help="Force repo memory into the packed context for this run.",
        )
        query_parser.add_argument(
            "--show-context",
            action="store_true",
            help="Print the packed retrieval context before the answer or handoff.",
        )
        rerank_group = query_parser.add_mutually_exclusive_group()
        rerank_group.add_argument(
            "--rerank",
            dest="rerank",
            action="store_true",
            default=None,
            help="Force the reranker on for this query.",
        )
        rerank_group.add_argument(
            "--no-rerank",
            dest="rerank",
            action="store_false",
            help="Skip the reranker for this query.",
        )
        if include_mode_flag:
            query_parser.add_argument(
                "--mode",
                choices=["auto", "quick", "deep", "agent"],
                default="auto",
                help="Routing mode for `rag ask` (defaults to config routing.default_mode / auto).",
            )
        if name == "agent":
            query_parser.add_argument(
                "--output-format",
                choices=["handoff", "answer"],
                default=default_output_format,
                help="Emit a coding-agent handoff or a direct answer.",
            )
            query_parser.add_argument(
                "--save-handoff",
                action="store_true",
                help="Persist the generated handoff under ~/ai-rag/projects/<repo>/handoffs/.",
            )
            query_parser.add_argument(
                "--target-agent",
                choices=["generic", "codex", "opencode", "copilot", "human"],
                default="generic",
                help="Format handoffs for a specific downstream agent or reviewer.",
            )
        else:
            query_parser.set_defaults(output_format=default_output_format, save_handoff=False, target_agent="generic")
        query_parser.set_defaults(func=handler)
        return query_parser

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

    add_query_parser("ask", "Ask a question against the local index", cmd_ask, include_mode_flag=True)
    add_query_parser("quick", "Force the fast retrieval+answer path", cmd_quick)
    add_query_parser("deep", "Force the deeper retrieval+planning path", cmd_deep)
    add_query_parser(
        "agent",
        "Build a longer-form answer or coding-agent handoff with operational state",
        cmd_agent,
        default_output_format="handoff",
    )
    handoff_parser = subparsers.add_parser("handoff", help="Build a target-specific coding handoff packet")
    handoff_parser.add_argument("target", choices=["codex", "opencode", "copilot", "human"])
    handoff_parser.add_argument("query")
    handoff_parser.add_argument("--repo", help="Filter to a repo name")
    handoff_parser.add_argument(
        "--memory",
        action="store_true",
        help="Force repo memory into the packed context for this run.",
    )
    handoff_parser.add_argument(
        "--show-context",
        action="store_true",
        help="Print the packed retrieval context before the handoff.",
    )
    handoff_rerank_group = handoff_parser.add_mutually_exclusive_group()
    handoff_rerank_group.add_argument(
        "--rerank",
        dest="rerank",
        action="store_true",
        default=None,
        help="Force the reranker on for this query.",
    )
    handoff_rerank_group.add_argument(
        "--no-rerank",
        dest="rerank",
        action="store_false",
        help="Skip the reranker for this query.",
    )
    handoff_parser.add_argument(
        "--save-handoff",
        action="store_true",
        help="Persist the generated handoff under ~/ai-rag/projects/<repo>/handoffs/.",
    )
    handoff_parser.set_defaults(func=cmd_handoff, output_format="handoff")

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

    memory_parser = subparsers.add_parser("memory", help="Inspect repo memory, notes, context packs, and taxonomy")
    memory_subparsers = memory_parser.add_subparsers(dest="memory_command", required=True)

    memory_status_parser = memory_subparsers.add_parser("status", help="Show repo memory freshness")
    memory_status_parser.add_argument("--repo", help="Target repo name")
    memory_status_parser.set_defaults(func=cmd_memory)

    memory_show_parser = memory_subparsers.add_parser("show", help="Show stored repo memory")
    memory_show_parser.add_argument("--repo", help="Target repo name")
    memory_show_parser.set_defaults(func=cmd_memory)

    memory_refresh_parser = memory_subparsers.add_parser("refresh", help="Refresh stored repo memory")
    memory_refresh_parser.add_argument("--repo", help="Target repo name")
    memory_refresh_parser.set_defaults(func=cmd_memory)

    memory_clear_parser = memory_subparsers.add_parser("clear", help="Clear stored repo memory")
    memory_clear_parser.add_argument("--repo", help="Target repo name")
    memory_clear_parser.add_argument("--all", action="store_true", help="Apply clear to all repos")
    memory_clear_parser.set_defaults(func=cmd_memory)

    memory_remember_parser = memory_subparsers.add_parser("remember", help="Store structured developer memory")
    memory_remember_parser.add_argument("kind", choices=[
        "project_facts",
        "developer_preferences",
        "known_stack",
        "tool_preferences",
        "hardware_profile",
        "repo_conventions",
    ])
    memory_remember_parser.add_argument("subject")
    memory_remember_parser.add_argument("value", nargs="+")
    memory_remember_parser.add_argument("--repo", help="Scope to one repo")
    memory_remember_parser.add_argument(
        "--global-scope",
        action="store_true",
        help="Store this memory globally instead of tying it to a repo.",
    )
    memory_remember_parser.set_defaults(func=cmd_memory)

    memory_notes_parser = memory_subparsers.add_parser("notes", help="List structured memory notes")
    memory_notes_parser.add_argument("--repo", help="Target repo name")
    memory_notes_parser.add_argument("--kind", help="Filter by memory kind")
    memory_notes_parser.add_argument("--scope", choices=["all", "repo", "global"], default="all")
    memory_notes_parser.add_argument("--status", choices=["active", "stale", "conflict", "all"], default="active")
    memory_notes_parser.add_argument("--limit", type=int, default=20)
    memory_notes_parser.set_defaults(func=cmd_memory)

    memory_conflicts_parser = memory_subparsers.add_parser("conflicts", help="Show conflicting memory notes")
    memory_conflicts_parser.add_argument("--repo", help="Target repo name")
    memory_conflicts_parser.add_argument("--limit", type=int, default=20)
    memory_conflicts_parser.set_defaults(func=cmd_memory)

    memory_compact_parser = memory_subparsers.add_parser("compact", help="List or refresh session compactions")
    memory_compact_parser.add_argument("--repo", help="Target repo name")
    memory_compact_parser.add_argument("--session-id", help="Compact one saved session immediately")
    memory_compact_parser.add_argument("--limit", type=int, default=10)
    memory_compact_parser.set_defaults(func=cmd_memory)

    memory_pack_parser = memory_subparsers.add_parser("pack", help="Build and optionally write a reusable context pack")
    memory_pack_parser.add_argument("name")
    memory_pack_parser.add_argument("--repo", help="Target repo name")
    memory_pack_parser.add_argument("--target-agent", choices=["generic", "codex", "opencode", "copilot", "human"], default="generic")
    memory_pack_parser.add_argument("--write-file", action="store_true", help="Write .context/<name>.toon in the repo root")
    memory_pack_parser.set_defaults(func=cmd_memory)

    memory_taxonomy_parser = memory_subparsers.add_parser("taxonomy", help="Inspect the personal tool taxonomy")
    memory_taxonomy_parser.add_argument("--domain", help="Filter one taxonomy domain")
    memory_taxonomy_parser.add_argument("--query", help="Search taxonomy domains and tools")
    memory_taxonomy_parser.add_argument("--format", choices=["table", "yaml"], default="table")
    memory_taxonomy_parser.add_argument("--limit", type=int, default=30)
    memory_taxonomy_parser.set_defaults(func=cmd_memory)

    todo_parser = subparsers.add_parser("todo", help="Manage structured RAG todos")
    todo_subparsers = todo_parser.add_subparsers(dest="todo_command", required=True)
    todo_list_parser = todo_subparsers.add_parser("list", help="List todos")
    todo_list_parser.add_argument("--repo", help="Filter to one repo")
    todo_list_parser.add_argument("--status", choices=["open", "in_progress", "done", "all"], default="open")
    todo_list_parser.add_argument("--limit", type=int, default=20)
    todo_list_parser.set_defaults(func=cmd_todo)
    todo_add_parser = todo_subparsers.add_parser("add", help="Add a todo")
    todo_add_parser.add_argument("title")
    todo_add_parser.add_argument("--repo", help="Scope to one repo")
    todo_add_parser.add_argument("--detail")
    todo_add_parser.add_argument("--status", choices=["open", "in_progress", "done"], default="open")
    todo_add_parser.set_defaults(func=cmd_todo)
    todo_done_parser = todo_subparsers.add_parser("done", help="Mark a todo done")
    todo_done_parser.add_argument("todo_id", type=int)
    todo_done_parser.set_defaults(func=cmd_todo)
    todo_start_parser = todo_subparsers.add_parser("start", help="Mark a todo in progress")
    todo_start_parser.add_argument("todo_id", type=int)
    todo_start_parser.set_defaults(func=cmd_todo)

    decision_parser = subparsers.add_parser("decision", help="Manage structured engineering decisions")
    decision_subparsers = decision_parser.add_subparsers(dest="decision_command", required=True)
    decision_list_parser = decision_subparsers.add_parser("list", help="List decisions")
    decision_list_parser.add_argument("--repo", help="Filter to one repo")
    decision_list_parser.add_argument("--limit", type=int, default=20)
    decision_list_parser.set_defaults(func=cmd_decision)
    decision_add_parser = decision_subparsers.add_parser("add", help="Record a decision")
    decision_add_parser.add_argument("title")
    decision_add_parser.add_argument("detail")
    decision_add_parser.add_argument("--repo", help="Scope to one repo")
    decision_add_parser.add_argument("--rationale")
    decision_add_parser.set_defaults(func=cmd_decision)

    command_parser = subparsers.add_parser("command", help="Remember useful commands")
    command_subparsers = command_parser.add_subparsers(dest="command_memory_command", required=True)
    command_list_parser = command_subparsers.add_parser("list", help="List remembered commands")
    command_list_parser.add_argument("--repo", help="Filter to one repo")
    command_list_parser.add_argument("--limit", type=int, default=20)
    command_list_parser.set_defaults(func=cmd_command_memory)
    command_add_parser = command_subparsers.add_parser("add", help="Store a useful command")
    command_add_parser.add_argument("command_text")
    command_add_parser.add_argument("--repo", help="Scope to one repo")
    command_add_parser.add_argument("--purpose")
    command_add_parser.add_argument("--notes")
    command_add_parser.set_defaults(func=cmd_command_memory)

    error_parser = subparsers.add_parser("error", help="Remember recurring errors and fixes")
    error_subparsers = error_parser.add_subparsers(dest="error_command", required=True)
    error_list_parser = error_subparsers.add_parser("list", help="List remembered errors")
    error_list_parser.add_argument("--repo", help="Filter to one repo")
    error_list_parser.add_argument("--limit", type=int, default=20)
    error_list_parser.set_defaults(func=cmd_error_memory)
    error_add_parser = error_subparsers.add_parser("add", help="Store an error/fix pair")
    error_add_parser.add_argument("error_text")
    error_add_parser.add_argument("--repo", help="Scope to one repo")
    error_add_parser.add_argument("--fix")
    error_add_parser.add_argument("--notes")
    error_add_parser.set_defaults(func=cmd_error_memory)

    session_parser = subparsers.add_parser("session", help="Inspect saved RAG sessions")
    session_subparsers = session_parser.add_subparsers(dest="session_command", required=True)
    session_list_parser = session_subparsers.add_parser("list", help="List saved sessions")
    session_list_parser.add_argument("--repo", help="Filter to one repo")
    session_list_parser.add_argument("--limit", type=int, default=20)
    session_list_parser.set_defaults(func=cmd_session)
    session_show_parser = session_subparsers.add_parser("show", help="Show one saved session")
    session_show_parser.add_argument("session_id")
    session_show_parser.set_defaults(func=cmd_session)

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
