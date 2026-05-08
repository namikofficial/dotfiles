from __future__ import annotations

import math
import re
import sqlite3
from dataclasses import dataclass
from typing import Sequence

from qdrant_client import QdrantClient, models

from .runtime import console
from .storage import get_embedder

STOPWORDS = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "be",
    "but",
    "by",
    "for",
    "from",
    "how",
    "i",
    "if",
    "in",
    "is",
    "it",
    "of",
    "on",
    "or",
    "the",
    "to",
    "what",
    "where",
    "which",
    "with",
}


@dataclass(frozen=True)
class RetrievalPlan:
    query: str
    repo: str | None
    rewrites: list[str]
    intent: str
    mode: str


@dataclass
class RetrievalCandidates:
    plan: RetrievalPlan
    semantic_ids: list[str]
    keyword_ids: list[str]
    recent_ids: list[str]
    facts: list[sqlite3.Row]
    summaries: list[sqlite3.Row]
    memory: sqlite3.Row | None


@dataclass
class RetrievalResult:
    plan: RetrievalPlan
    rows: list[sqlite3.Row]
    facts: list[sqlite3.Row]
    summaries: list[sqlite3.Row]
    memory: sqlite3.Row | None
    debug: dict


def approx_tokens(text: str) -> int:
    return max(1, math.ceil(len(text) / 4))


def split_symbol_tokens(token: str) -> list[str]:
    parts = re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?=[A-Z]|$)", token)
    return [part.lower() for part in parts if len(part) > 1]


def query_terms(query: str) -> list[str]:
    return [token.lower() for token in re.findall(r"[A-Za-z0-9_./:-]+", query) if token.lower() not in STOPWORDS]


def rewrite_queries(query: str, limit: int | None = None) -> list[str]:
    terms = query_terms(query)
    rewrites = [query.strip()]
    if terms:
        rewrites.append(" ".join(dict.fromkeys(terms)))
        split_terms: list[str] = []
        original_tokens = re.findall(r"[A-Za-z0-9_./:-]+", query)
        for term in original_tokens:
            split_terms.extend(split_symbol_tokens(term))
        if split_terms:
            rewrites.append(" ".join(dict.fromkeys(split_terms)))
    unique = [rewrite for rewrite in dict.fromkeys(rewrites) if rewrite]
    if limit is not None:
        return unique[:limit]
    return unique


def detect_intent(query: str) -> str:
    lowered = query.lower()
    if any(token in lowered for token in ("super", "alt", "ctrl", "shift", "keybind", "shortcut", "xf86")):
        return "keybind"
    if any(token in lowered for token in ("command", "cli tool", "binary", "docker", "gh", "opencode", "just")):
        return "tool"
    return "general"


def build_retrieval_plan(query: str, repo: str | None, mode: str = "quick", config: dict | None = None) -> RetrievalPlan:
    rewrite_limit = None
    if config is not None:
        rewrite_limit = int(config["retrieval_pipeline"]["rewrite_limit"])
    return RetrievalPlan(
        query=query,
        repo=repo,
        rewrites=rewrite_queries(query, limit=rewrite_limit),
        intent=detect_intent(query),
        mode=mode,
    )


def qdrant_filter(repo: str | None) -> models.Filter | None:
    if not repo:
        return None
    return models.Filter(
        must=[models.FieldCondition(key="repo", match=models.MatchValue(value=repo))]
    )


def semantic_hits(client: QdrantClient, config: dict, plan: RetrievalPlan) -> list[str]:
    hits: list[str] = []
    embedder = get_embedder(config)
    limit = int(config["retrieval_pipeline"]["semantic_limit"])
    for rewrite in plan.rewrites[: int(config["retrieval_pipeline"]["rewrite_limit"])]:
        vector = list(embedder.embed([rewrite]))[0].tolist()
        response = client.query_points(
            collection_name=config["qdrant_collection"],
            query=vector,
            query_filter=qdrant_filter(plan.repo),
            limit=limit,
            with_payload=True,
        )
        hits.extend(str(result.id) for result in response.points)
    return hits


def keyword_hits(conn: sqlite3.Connection, config: dict, plan: RetrievalPlan) -> list[str]:
    hits: list[str] = []
    limit = int(config["retrieval_pipeline"]["keyword_limit"])
    for rewrite in plan.rewrites[: int(config["retrieval_pipeline"]["rewrite_limit"])]:
        tokens = query_terms(rewrite)
        if not tokens:
            continue
        match = " OR ".join(tokens[:12])
        sql = (
            "SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ?"
            + (" AND repo = ?" if plan.repo else "")
            + " LIMIT ?"
        )
        params = [match] + ([plan.repo] if plan.repo else []) + [limit]
        hits.extend(row["chunk_id"] for row in conn.execute(sql, params).fetchall())
    return hits


def recent_hits(conn: sqlite3.Connection, config: dict, plan: RetrievalPlan) -> list[str]:
    terms = query_terms(plan.query)[:6]
    if not terms:
        return []
    like_clauses = []
    params: list[str] = []
    for term in terms:
        like_clauses.append("(path LIKE ? OR symbol LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%"])
    sql = "SELECT chunk_id FROM chunks WHERE " + " OR ".join(like_clauses)
    if plan.repo:
        sql += " AND repo = ?"
        params.append(plan.repo)
    sql += " ORDER BY modified_at DESC LIMIT ?"
    params.append(int(config["retrieval_pipeline"]["recent_limit"]))
    return [row["chunk_id"] for row in conn.execute(sql, params).fetchall()]


def normalize_keybind_token(token: str, config: dict) -> str:
    mapping = {
        "super": "SUPER",
        "alt": "ALT",
        "shift": "SHIFT",
        "grave": "GRAVE",
        **config["key_aliases"],
    }
    cleaned = token.strip().strip("$").lower()
    if not cleaned:
        return ""
    if cleaned in mapping:
        return mapping[cleaned]
    return cleaned.upper()


def normalize_query_keybind_tokens(query: str, config: dict) -> list[str]:
    normalized = []
    for token in query_terms(query):
        normalized_token = normalize_keybind_token(token, config)
        if normalized_token:
            normalized.append(normalized_token)
    return list(dict.fromkeys(normalized))


def keybind_fact_tokens(key: str, config: dict) -> set[str]:
    mapping = {
        part
        for part in re.split(r"[^A-Za-z0-9_$]+", key)
        if part
    }
    return {
        normalized
        for normalized in (normalize_keybind_token(part, config) for part in mapping)
        if normalized
    }


def fact_hits(conn: sqlite3.Connection, plan: RetrievalPlan, config: dict) -> list[sqlite3.Row]:
    if plan.intent == "keybind":
        sql = "SELECT * FROM facts WHERE kind = 'keybind'" + (" AND repo = ?" if plan.repo else "")
        rows = conn.execute(sql, [plan.repo] if plan.repo else []).fetchall()
        query_tokens = normalize_query_keybind_tokens(plan.query, config)
        scored = []
        required_key = query_tokens[-1] if query_tokens else None
        for row in rows:
            score = 0.0
            fact_tokens = keybind_fact_tokens(row["key"], config)
            value_lower = row["value"].lower()
            path_lower = row["path"].lower()
            overlap = 0
            for token in query_tokens:
                if token in fact_tokens:
                    score += 3.0
                    overlap += 1
            if required_key and required_key not in {"SUPER", "ALT", "CTRL", "SHIFT"} and required_key not in fact_tokens:
                continue
            if len(query_tokens) > 1 and overlap < 2:
                continue
            if "scratchpad" in value_lower:
                score += 2.0
            if "hypr" in path_lower:
                score += 1.0
            if score > 0:
                scored.append((score, row))
        scored.sort(key=lambda item: item[0], reverse=True)
        return [row for _score, row in scored[:12]]
    if plan.intent == "tool":
        sql = "SELECT * FROM facts WHERE kind = 'tool'" + (" AND repo = ?" if plan.repo else "")
        rows = conn.execute(sql, [plan.repo] if plan.repo else []).fetchall()
        terms = query_terms(plan.query)
        scored = []
        for row in rows:
            score = 0.0
            key_lower = row["key"].lower()
            value_lower = row["value"].lower()
            for term in terms:
                if term in key_lower:
                    score += 3.0
                if term in value_lower:
                    score += 1.0
            if score > 0:
                scored.append((score, row))
        scored.sort(key=lambda item: item[0], reverse=True)
        return [row for _score, row in scored[:12]]
    terms = query_terms(plan.query)[:8]
    if not terms:
        return []
    clauses = []
    params: list[str] = []
    for term in terms:
        clauses.append("(key LIKE ? OR value LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%"])
    sql = "SELECT * FROM facts WHERE " + " OR ".join(clauses)
    if plan.repo:
        sql += " AND repo = ?"
        params.append(plan.repo)
    sql += " ORDER BY confidence DESC, updated_at DESC LIMIT 12"
    return conn.execute(sql, params).fetchall()


def file_summary_hits(conn: sqlite3.Connection, plan: RetrievalPlan) -> list[sqlite3.Row]:
    terms = query_terms(plan.query)[:8]
    if not terms:
        return []
    clauses = []
    params: list[str] = []
    for term in terms:
        clauses.append("(path LIKE ? OR summary LIKE ? OR symbols LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%", f"%{term}%"])
    sql = "SELECT * FROM file_summaries WHERE " + " OR ".join(clauses)
    if plan.repo:
        sql += " AND repo = ?"
        params.append(plan.repo)
    sql += " ORDER BY updated_at DESC LIMIT 20"
    rows = conn.execute(sql, params).fetchall()
    if plan.intent not in {"keybind", "tool"}:
        return rows[:10]
    scored = []
    for row in rows:
        score = 0.0
        path_lower = row["path"].lower()
        summary_lower = row["summary"].lower()
        symbols_lower = (row["symbols"] or "").lower()
        if plan.intent == "keybind":
            if any(token in path_lower for token in ("hypr", "keybind", "cheatsheet")):
                score += 2.0
            if "keybind" in summary_lower or "bind:" in symbols_lower:
                score += 2.0
        elif plan.intent == "tool":
            if row["language"] == "shell":
                score += 2.0
            if "tool:" in symbols_lower:
                score += 2.0
        for term in terms:
            if term in path_lower or term in summary_lower or term in symbols_lower:
                score += 1.0
        scored.append((score, row))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [row for _score, row in scored[:10]]


def repo_memory_row(conn: sqlite3.Connection, repo: str | None) -> sqlite3.Row | None:
    if not repo:
        return None
    return conn.execute("SELECT * FROM repo_memory WHERE repo = ?", (repo,)).fetchone()


def limit_rows_per_file(rows: Sequence[sqlite3.Row], max_per_file: int) -> list[sqlite3.Row]:
    limited: list[sqlite3.Row] = []
    counts: dict[str, int] = {}
    for row in rows:
        key = row["path"]
        if counts.get(key, 0) >= max_per_file:
            continue
        counts[key] = counts.get(key, 0) + 1
        limited.append(row)
    return limited


def limit_rows_by_file_count(rows: Sequence[sqlite3.Row], max_files: int) -> list[sqlite3.Row]:
    limited: list[sqlite3.Row] = []
    seen_files: set[str] = set()
    for row in rows:
        if row["path"] not in seen_files and len(seen_files) >= max_files:
            continue
        seen_files.add(row["path"])
        limited.append(row)
    return limited


def reciprocal_rank_fusion(*rank_lists: Sequence[str]) -> dict[str, float]:
    scores: dict[str, float] = {}
    for rank_list in rank_lists:
        for rank, chunk_id in enumerate(rank_list, start=1):
            scores[chunk_id] = scores.get(chunk_id, 0.0) + 1.0 / (60 + rank)
    return scores


def load_chunks(conn: sqlite3.Connection, chunk_ids: Sequence[str]) -> list[sqlite3.Row]:
    if not chunk_ids:
        return []
    placeholders = ",".join("?" for _ in chunk_ids)
    rows = conn.execute(
        f"SELECT * FROM chunks WHERE chunk_id IN ({placeholders})",
        list(chunk_ids),
    ).fetchall()
    by_id = {row["chunk_id"]: row for row in rows}
    return [by_id[chunk_id] for chunk_id in chunk_ids if chunk_id in by_id]


def rerank_chunks(
    query: str,
    rows: Sequence[sqlite3.Row],
    base_scores: dict[str, float],
    config: dict,
    intent: str,
    fact_paths: set[str],
    summary_paths: set[str],
) -> list[sqlite3.Row]:
    reranker_config = config["reranker"]
    query_terms_set = set(query_terms(query))
    scored = []
    for row in rows:
        content_terms = set(query_terms(row["content"])) | set(query_terms(row["path"])) | set(
            query_terms(row["symbol"] or "")
        )
        overlap = len(query_terms_set & content_terms)
        path_lower = row["path"].lower()
        symbol = row["symbol"] or ""
        path_bonus = 2 if any(term in row["path"].lower() for term in query_terms_set) else 0
        symbol_bonus = 2 if symbol and any(term in symbol.lower() for term in query_terms_set) else 0
        final_score = (
            base_scores.get(row["chunk_id"], 0.0)
            + (overlap * reranker_config["content_weight"])
            + (path_bonus * reranker_config["path_weight"])
            + (symbol_bonus * reranker_config["symbol_weight"])
        )
        if intent == "keybind":
            if row["language"] == "hyprland":
                final_score += 0.24
            if row["kind"] == "config":
                final_score += 0.08
            if symbol.startswith("bind:") or symbol == "entries":
                final_score += 0.12
            if any(token in path_lower for token in ("hyprland.conf", "hyprland.yaml", "keybind", "cheatsheet")):
                final_score += 0.12
        elif intent == "tool":
            if symbol.startswith("tool:"):
                final_score += 0.2
            if row["language"] == "shell":
                final_score += 0.05
        if row["path"] in fact_paths:
            final_score += 0.18
        if row["path"] in summary_paths:
            final_score += 0.1
        scored.append((final_score, row))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [row for _score, row in scored[: reranker_config["top_k_output"]]]


def reranker_enabled(config: dict, override: bool | None) -> bool:
    if override is None:
        return bool(config["reranker"]["enabled"])
    return override


def collect_retrieval_candidates(
    conn: sqlite3.Connection,
    client: QdrantClient,
    config: dict,
    plan: RetrievalPlan,
) -> RetrievalCandidates:
    return RetrievalCandidates(
        plan=plan,
        semantic_ids=semantic_hits(client, config, plan),
        keyword_ids=keyword_hits(conn, config, plan),
        recent_ids=recent_hits(conn, config, plan),
        facts=fact_hits(conn, plan, config),
        summaries=file_summary_hits(conn, plan),
        memory=repo_memory_row(conn, plan.repo),
    )


def rank_retrieval_candidates(
    conn: sqlite3.Connection,
    config: dict,
    candidates: RetrievalCandidates,
    use_reranker: bool,
) -> RetrievalResult:
    fact_paths = {row["path"] for row in candidates.facts}
    summary_paths = {row["path"] for row in candidates.summaries}
    scores = reciprocal_rank_fusion(candidates.semantic_ids, candidates.keyword_ids, candidates.recent_ids)
    ranked_ids = [chunk_id for chunk_id, _ in sorted(scores.items(), key=lambda item: item[1], reverse=True)]
    rows = load_chunks(conn, ranked_ids[: config["reranker"]["top_k_input"]])
    selected_rows = (
        rerank_chunks(
            candidates.plan.query,
            rows,
            scores,
            config,
            candidates.plan.intent,
            fact_paths,
            summary_paths,
        )
        if use_reranker
        else rows[: config["reranker"]["top_k_output"]]
    )
    debug = {
        "rewrites": candidates.plan.rewrites,
        "semantic_hits": len(candidates.semantic_ids),
        "keyword_hits": len(candidates.keyword_ids),
        "recent_hits": len(candidates.recent_ids),
        "fact_hits": len(candidates.facts),
        "file_summary_hits": len(candidates.summaries),
        "memory_loaded": candidates.memory is not None,
        "merged_unique": len(scores),
        "ranking_enabled": use_reranker,
        "ranking_mode": config["reranker"]["mode"],
        "intent": candidates.plan.intent,
        "mode": candidates.plan.mode,
    }
    return RetrievalResult(
        plan=candidates.plan,
        rows=selected_rows,
        facts=candidates.facts,
        summaries=candidates.summaries,
        memory=candidates.memory,
        debug=debug,
    )


def retrieve(
    conn: sqlite3.Connection,
    client: QdrantClient,
    config: dict,
    query: str,
    repo: str | None,
    use_reranker: bool,
    mode: str = "quick",
) -> RetrievalResult:
    plan = build_retrieval_plan(query, repo, mode=mode, config=config)
    candidates = collect_retrieval_candidates(conn, client, config, plan)
    return rank_retrieval_candidates(conn, config, candidates, use_reranker)


def gather_context(
    rows: Sequence[sqlite3.Row],
    config: dict,
    facts: Sequence[sqlite3.Row] | None = None,
    summaries: Sequence[sqlite3.Row] | None = None,
    memory: str | None = None,
    operational_state: str | None = None,
    operational_state_tokens: int = 0,
) -> tuple[str, list[str]]:
    budgets = config["context_budget"]
    total_budget = budgets["total_tokens"]
    sections: list[str] = []
    seen_files: list[str] = []
    used = 0

    def append_block(block: str, file_ref: str | None = None, limit: int | None = None) -> bool:
        nonlocal used
        block_tokens = approx_tokens(block)
        if limit is not None and block_tokens > limit:
            return False
        if used + block_tokens > total_budget:
            return False
        sections.append(block)
        used += block_tokens
        if file_ref and file_ref not in seen_files:
            seen_files.append(file_ref)
        return True

    if operational_state:
        append_block(
            f"<operational_state>\n{operational_state}\n</operational_state>",
            limit=operational_state_tokens or budgets["memory_tokens"],
        )

    if memory:
        append_block(f"<repo_memory>\n{memory}\n</repo_memory>", limit=budgets["memory_tokens"])

    if facts:
        limited_facts = limit_rows_by_file_count(facts, config["retrieval"]["max_fact_files"])
        fact_blocks: list[str] = []
        fact_used = 0
        for index, fact in enumerate(limited_facts, start=1):
            block = (
                f"[FACT {index}] {fact['repo']}/{fact['path']}:{fact['line']}\n"
                f"kind={fact['kind']} key={fact['key']}\n"
                f"value={fact['value']}"
            )
            block_tokens = approx_tokens(block)
            if fact_used + block_tokens > budgets["facts_tokens"]:
                break
            fact_used += block_tokens
            fact_blocks.append(block)
            seen_files.append(f"{fact['repo']}/{fact['path']}:{fact['line']}")
        if fact_blocks:
            append_block("<facts>\n" + "\n\n".join(fact_blocks) + "\n</facts>", limit=budgets["facts_tokens"])

    if summaries:
        limited_summaries = limit_rows_by_file_count(summaries, config["retrieval"]["max_summary_files"])
        summary_blocks: list[str] = []
        summary_used = 0
        for index, summary in enumerate(limited_summaries, start=1):
            block = (
                f"[SUMMARY {index}] {summary['repo']}/{summary['path']}\n"
                f"kind={summary['kind']} language={summary['language']}\n"
                f"symbols={summary['symbols'] or '-'}\n"
                f"{summary['summary']}"
            )
            block_tokens = approx_tokens(block)
            if summary_used + block_tokens > budgets["file_summary_tokens"]:
                break
            summary_used += block_tokens
            summary_blocks.append(block)
            seen_files.append(f"{summary['repo']}/{summary['path']}")
        if summary_blocks:
            append_block(
                "<file_summaries>\n" + "\n\n".join(summary_blocks) + "\n</file_summaries>",
                limit=budgets["file_summary_tokens"],
            )

    chunk_blocks: list[str] = []
    chunk_used = 0
    for row in limit_rows_per_file(rows, config["retrieval"]["max_chunks_per_file"]):
        block = (
            f"[{len(chunk_blocks)+1}] {row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}\n"
            f"kind={row['kind']} language={row['language']} symbol={row['symbol'] or '-'}\n"
            f"{row['content']}"
        )
        block_tokens = approx_tokens(block)
        if chunk_used + block_tokens > budgets["chunk_tokens"]:
            break
        chunk_used += block_tokens
        chunk_blocks.append(block)
        file_ref = f"{row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}"
        if file_ref not in seen_files:
            seen_files.append(file_ref)
    if chunk_blocks:
        append_block("<chunks>\n" + "\n\n".join(chunk_blocks) + "\n</chunks>", limit=budgets["chunk_tokens"])
    return "\n\n".join(sections), list(dict.fromkeys(seen_files))


def print_retrieval_explain(debug: dict, rows: Sequence[sqlite3.Row]) -> None:
    console.print("[bold]Query rewrites:[/bold]")
    for rewrite in debug["rewrites"]:
        console.print(f"- {rewrite}")
    console.print("\n[bold]Retrieval:[/bold]")
    console.print(f"semantic hits: {debug['semantic_hits']}")
    console.print(f"keyword hits: {debug['keyword_hits']}")
    console.print(f"recent/path hits: {debug['recent_hits']}")
    console.print(f"fact hits: {debug['fact_hits']}")
    console.print(f"file summary hits: {debug['file_summary_hits']}")
    console.print(f"repo memory: {'loaded' if debug['memory_loaded'] else 'not loaded'}")
    console.print(f"merged unique: {debug['merged_unique']}")
    console.print(f"mode: {debug['mode']}")
    console.print(f"intent: {debug['intent']}")
    console.print(
        "ranking pass: "
        + (
            f"{debug['ranking_mode']} enabled"
            if debug["ranking_enabled"]
            else f"{debug['ranking_mode']} disabled"
        )
    )
    console.print("\n[bold]Selected:[/bold]")
    for index, row in enumerate(rows[:10], start=1):
        console.print(
            f"{index}. {row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']} "
            f"symbol={row['symbol'] or '-'} kind={row['kind']} language={row['language']}"
        )
