from __future__ import annotations

import difflib
import json
import math
import re
import sqlite3
import subprocess
import time
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Iterable, Sequence

from qdrant_client import models

from .memory import taxonomy_terms_for_query
from .runtime import console
from .state import (
    extract_file_paths,
    extract_stack_symbols,
    fingerprint_error,
    list_memory_entries,
    normalize_error_text,
    upsert_git_context,
)
from .storage import get_embedder, git_branch_for, git_head_commit_for
from .types import SupportsQdrantQuery

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

TOKEN_PATTERN = re.compile(r"[A-Za-z0-9_./:#-]+")
PATH_EXTENSIONS = {
    "c",
    "cc",
    "conf",
    "cpp",
    "css",
    "go",
    "h",
    "hpp",
    "html",
    "ini",
    "java",
    "js",
    "json",
    "jsx",
    "kt",
    "md",
    "py",
    "rs",
    "sh",
    "sql",
    "toml",
    "ts",
    "tsx",
    "xml",
    "yaml",
    "yml",
    "zsh",
}


@dataclass(frozen=True)
class QueryAnalysis:
    raw_tokens: tuple[str, ...]
    terms: tuple[str, ...]
    split_terms: tuple[str, ...]
    expanded_terms: tuple[str, ...]
    path_terms: tuple[str, ...]
    symbol_terms: tuple[str, ...]
    corrected_terms: tuple[str, ...]
    preferred_languages: tuple[str, ...]
    preferred_kinds: tuple[str, ...]
    preferred_paths: tuple[str, ...]
    preferred_extensions: tuple[str, ...]
    preferred_fact_kinds: tuple[str, ...] = ()


@dataclass(frozen=True)
class RetrievalPlan:
    query: str
    repo: str | None
    rewrites: list[str]
    intent: str
    mode: str
    analysis: QueryAnalysis | None = None


@dataclass
class RetrievalCandidates:
    plan: RetrievalPlan
    semantic_ids: list[str]
    keyword_ids: list[str]
    semantic_line_ids: list[str] = field(default_factory=list)
    symbol_ids: list[str] = field(default_factory=list)
    recent_ids: list[str] = field(default_factory=list)
    facts: list[sqlite3.Row] = field(default_factory=list)
    summaries: list[sqlite3.Row] = field(default_factory=list)
    memory: sqlite3.Row | None = None
    git_context: sqlite3.Row | None = None
    github_refs: list[sqlite3.Row] = field(default_factory=list)
    test_failures: list[sqlite3.Row] = field(default_factory=list)
    error_matches: list[sqlite3.Row] = field(default_factory=list)
    timings_ms: dict[str, float] = field(default_factory=dict)


@dataclass
class RetrievalResult:
    plan: RetrievalPlan
    rows: list[sqlite3.Row]
    facts: list[sqlite3.Row]
    summaries: list[sqlite3.Row]
    memory: sqlite3.Row | None
    context_sources: list["ContextSource"]
    debug: dict


@dataclass(frozen=True)
class ContextSource:
    source_type: str
    title: str
    content: str
    file_refs: tuple[str, ...] = ()


def approx_tokens(text: str) -> int:
    return max(1, math.ceil(len(text) / 4))


def unique_terms(items: Iterable[str]) -> list[str]:
    return [item for item in dict.fromkeys(items) if item]


def split_symbol_tokens(token: str) -> list[str]:
    normalized = re.sub(r"::|->", " ", token)
    segments = re.split(r"[^A-Za-z0-9]+", normalized)
    parts: list[str] = []
    for segment in segments:
        parts.extend(re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?=[A-Z]|$)", segment))
    return [part.lower() for part in parts if len(part) > 1]


def raw_query_tokens(query: str) -> list[str]:
    return TOKEN_PATTERN.findall(query)


def query_terms(query: str) -> list[str]:
    return [token.lower() for token in raw_query_tokens(query) if token.lower() not in STOPWORDS]


def fts_match_terms(terms: Sequence[str], *, limit: int = 12) -> str:
    sanitized: list[str] = []
    for term in terms:
        cleaned = re.sub(r'[^A-Za-z0-9_*"]+', " ", term).strip()
        if not cleaned:
            continue
        sanitized.extend(part for part in cleaned.split() if part)
        if len(sanitized) >= limit:
            break
    return " OR ".join(sanitized[:limit])


def looks_like_path_token(token: str) -> bool:
    if "/" in token or token.startswith("."):
        return True
    match = re.search(r"\.([A-Za-z0-9]{1,6})$", token)
    return bool(match and match.group(1).lower() in PATH_EXTENSIONS)


def looks_like_symbol_token(token: str) -> bool:
    return any(marker in token for marker in ("::", "->", ".", "#")) or bool(re.search(r"[a-z][A-Z]", token))


def query_intelligence_config(config: dict | None) -> dict:
    if config is None:
        return {}
    return config.get("query_intelligence", {})


def expand_terms_via_mapping(terms: Sequence[str], mapping: dict[str, Sequence[str] | str]) -> list[str]:
    expanded: list[str] = []
    for term in terms:
        values = mapping.get(term)
        if values is None:
            continue
        if isinstance(values, str):
            expanded.append(values)
            continue
        expanded.extend(str(value) for value in values)
    return unique_terms(expanded)


def infer_file_type_preferences(terms: Sequence[str], config: dict | None) -> tuple[list[str], list[str], list[str], list[str]]:
    query_config = query_intelligence_config(config)
    languages: list[str] = []
    kinds: list[str] = []
    paths: list[str] = []
    extensions: list[str] = []
    term_set = set(terms)
    for hint in query_config.get("file_type_hints", {}).values():
        if not term_set.intersection(hint.get("terms", [])):
            continue
        languages.extend(hint.get("languages", []))
        kinds.extend(hint.get("kinds", []))
        paths.extend(hint.get("paths", []))
        extensions.extend(hint.get("extensions", []))
    return (
        unique_terms(languages),
        unique_terms(kinds),
        unique_terms(paths),
        unique_terms(extensions),
    )


def typo_vocabulary(conn: sqlite3.Connection, repo: str | None, config: dict | None) -> list[str]:
    if conn is None:
        return []
    typo_config = query_intelligence_config(config).get("typo_tolerance", {})
    limit = int(typo_config.get("candidate_limit", 4000))
    if repo:
        chunk_rows = conn.execute(
            "SELECT path, symbol FROM chunks WHERE repo = ? ORDER BY modified_at DESC LIMIT ?",
            (repo, limit),
        ).fetchall()
        fact_rows = conn.execute(
            "SELECT key, path FROM facts WHERE repo = ? ORDER BY updated_at DESC LIMIT ?",
            (repo, limit // 2 or 1),
        ).fetchall()
    else:
        chunk_rows = conn.execute(
            "SELECT path, symbol FROM chunks ORDER BY modified_at DESC LIMIT ?",
            (limit,),
        ).fetchall()
        fact_rows = conn.execute(
            "SELECT key, path FROM facts ORDER BY updated_at DESC LIMIT ?",
            (limit // 2 or 1,),
        ).fetchall()
    vocabulary: list[str] = []
    for row in chunk_rows:
        for value in (row["path"], row["symbol"] or ""):
            vocabulary.extend(query_terms(value))
            vocabulary.extend(split_symbol_tokens(value))
    for row in fact_rows:
        vocabulary.extend(query_terms(row["key"]))
        vocabulary.extend(split_symbol_tokens(row["key"]))
        vocabulary.extend(query_terms(row["path"]))
    return unique_terms(vocabulary)


def typo_correct_terms(
    terms: Sequence[str],
    conn: sqlite3.Connection | None,
    repo: str | None,
    config: dict | None,
) -> list[str]:
    typo_config = query_intelligence_config(config).get("typo_tolerance", {})
    if not typo_config.get("enabled", True) or conn is None:
        return []
    vocabulary = typo_vocabulary(conn, repo, config)
    if not vocabulary:
        return []
    known = set(vocabulary)
    min_length = int(typo_config.get("min_token_length", 4))
    cutoff = float(typo_config.get("cutoff", 0.82))
    max_length_delta = int(typo_config.get("max_length_delta", 2))
    corrected: list[str] = []
    for term in unique_terms(terms):
        if len(term) < min_length or term in known:
            continue
        matches = difflib.get_close_matches(term, vocabulary, n=1, cutoff=cutoff)
        if not matches:
            continue
        match = matches[0]
        if abs(len(match) - len(term)) > max_length_delta:
            continue
        corrected.append(match)
    return unique_terms(corrected)


def preferred_fact_kinds(intent: str, config: dict | None) -> list[str]:
    query_config = query_intelligence_config(config)
    fact_kinds = query_config.get("intent_fact_kinds", {})
    return unique_terms(fact_kinds.get(intent, []))


def dynamic_query_terms(conn: sqlite3.Connection | None, query: str, repo: str | None) -> list[str]:
    if conn is None:
        return []
    terms = set(query_terms(query))
    expanded: list[str] = []
    for row in list_memory_entries(conn, repo, scope="all", status="active", limit=24):
        subject = str(row["subject"])
        value = str(row["value"])
        subject_terms = set(query_terms(subject))
        value_terms = set(query_terms(value))
        if terms & (subject_terms | value_terms):
            expanded.extend([subject, value])
            continue
        if row["kind"] in {"known_stack", "tool_preferences"} and terms & {
            "backend",
            "frontend",
            "infra",
            "desktop",
            "kernel",
            "rust",
            "stack",
            "tool",
        }:
            expanded.extend([subject, value])
    expanded.extend(taxonomy_terms_for_query(conn, query))
    return unique_terms(expanded)


def build_query_analysis(
    query: str,
    config: dict | None = None,
    conn: sqlite3.Connection | None = None,
    repo: str | None = None,
) -> QueryAnalysis:
    raw_tokens = unique_terms(token.lower() for token in raw_query_tokens(query))
    terms = unique_terms(token for token in raw_tokens if token not in STOPWORDS)
    split_terms = unique_terms(
        part
        for token in raw_query_tokens(query)
        for part in split_symbol_tokens(token)
        if part not in STOPWORDS
    )
    query_config = query_intelligence_config(config)
    abbreviations = expand_terms_via_mapping(terms + split_terms, query_config.get("abbreviations", {}))
    developer_terms = expand_terms_via_mapping(
        terms + split_terms + abbreviations,
        query_config.get("developer_lexicon", {}),
    )
    corrected_terms = typo_correct_terms(terms + split_terms, conn, repo, config)
    path_terms = unique_terms(
        [
            *[token for token in terms if looks_like_path_token(token)],
            *[part for token in raw_query_tokens(query) if looks_like_path_token(token) for part in split_symbol_tokens(token)],
        ]
    )
    symbol_terms = unique_terms(
        [
            *[part for token in raw_query_tokens(query) if looks_like_symbol_token(token) for part in split_symbol_tokens(token)],
            *[part for part in split_terms if part.endswith(("service", "controller", "module", "hook", "repo", "client"))],
        ]
    )
    expanded_terms = unique_terms(terms + split_terms + abbreviations + developer_terms + corrected_terms)
    preferred_languages, preferred_kinds, preferred_paths, preferred_extensions = infer_file_type_preferences(
        expanded_terms,
        config,
    )
    return QueryAnalysis(
        raw_tokens=tuple(raw_tokens),
        terms=tuple(terms),
        split_terms=tuple(split_terms),
        expanded_terms=tuple(expanded_terms),
        path_terms=tuple(path_terms),
        symbol_terms=tuple(symbol_terms),
        corrected_terms=tuple(corrected_terms),
        preferred_languages=tuple(preferred_languages),
        preferred_kinds=tuple(preferred_kinds),
        preferred_paths=tuple(preferred_paths),
        preferred_extensions=tuple(preferred_extensions),
    )


def rewrite_queries(
    query: str,
    limit: int | None = None,
    config: dict | None = None,
    analysis: QueryAnalysis | None = None,
) -> list[str]:
    analysis = analysis or build_query_analysis(query, config)
    rewrites = [query.strip()]
    if analysis.terms:
        rewrites.append(" ".join(analysis.terms))
    expanded_only = [term for term in analysis.expanded_terms if term not in analysis.terms]
    if expanded_only:
        rewrites.append(" ".join(unique_terms([*analysis.terms, *expanded_only])))
    if analysis.split_terms:
        rewrites.append(" ".join(unique_terms([*analysis.split_terms])))
    if analysis.symbol_terms:
        rewrites.append(" ".join(unique_terms([*analysis.split_terms, *analysis.symbol_terms, *analysis.corrected_terms])))
    if analysis.path_terms:
        rewrites.append(" ".join(unique_terms([*analysis.path_terms, *analysis.expanded_terms[:6]])))
    if analysis.preferred_languages or analysis.preferred_paths:
        rewrites.append(
            " ".join(
                unique_terms(
                    [
                        *analysis.expanded_terms[:8],
                        *analysis.preferred_languages,
                        *analysis.preferred_paths,
                    ]
                )
            )
        )
    unique = [rewrite for rewrite in dict.fromkeys(rewrites) if rewrite.strip()]
    if limit is not None:
        return unique[:limit]
    return unique


def detect_intent(query: str, config: dict | None = None, analysis: QueryAnalysis | None = None) -> str:
    analysis = analysis or build_query_analysis(query, config)
    lowered = query.lower()
    query_config = query_intelligence_config(config)
    intent_markers = query_config.get("intent_markers", {})
    expanded_terms = set(analysis.expanded_terms)
    if any(token in lowered for token in intent_markers.get("keybind", ("super", "alt", "ctrl", "shift", "keybind", "shortcut", "xf86"))):
        return "keybind"
    if analysis.path_terms or any(token in lowered for token in intent_markers.get("path", ())):
        return "path"
    if analysis.symbol_terms or any(looks_like_symbol_token(token) for token in analysis.raw_tokens):
        return "symbol"
    if expanded_terms.intersection(intent_markers.get("config", ())) or any(token in lowered for token in intent_markers.get("config", ())):
        return "config"
    if expanded_terms.intersection(intent_markers.get("sql", ())) or any(token in lowered for token in intent_markers.get("sql", ())):
        return "sql"
    if expanded_terms.intersection(intent_markers.get("error", ())) or any(token in lowered for token in intent_markers.get("error", ())):
        return "error"
    if expanded_terms.intersection(intent_markers.get("tool", ("command", "cli tool", "binary", "docker", "gh", "opencode", "just"))) or any(
        token in lowered for token in intent_markers.get("tool", ("command", "cli tool", "binary", "docker", "gh", "opencode", "just"))
    ):
        return "tool"
    return "general"


def build_retrieval_plan(
    query: str,
    repo: str | None,
    mode: str = "quick",
    config: dict | None = None,
    conn: sqlite3.Connection | None = None,
) -> RetrievalPlan:
    rewrite_limit = None
    if config is not None:
        rewrite_limit = int(config["retrieval_pipeline"]["rewrite_limit"])
    extra_terms = dynamic_query_terms(conn, query, repo)
    expanded_query = query if not extra_terms else f"{query} {' '.join(extra_terms)}"
    analysis = build_query_analysis(expanded_query, config, conn=conn, repo=repo)
    intent = detect_intent(query, config=config, analysis=analysis)
    analysis = replace(analysis, preferred_fact_kinds=tuple(preferred_fact_kinds(intent, config)))
    rewrites = rewrite_queries(query, limit=rewrite_limit, config=config, analysis=analysis)
    if extra_terms:
        rewrites = unique_terms([*rewrites, expanded_query, *extra_terms[:2]])
    return RetrievalPlan(
        query=query,
        repo=repo,
        rewrites=rewrites[:rewrite_limit] if rewrite_limit is not None else rewrites,
        intent=intent,
        mode=mode,
        analysis=analysis,
    )


def qdrant_filter(repo: str | None) -> models.Filter | None:
    if not repo:
        return None
    return models.Filter(
        must=[models.FieldCondition(key="repo", match=models.MatchValue(value=repo))]
    )


def analysis_for_plan(plan: RetrievalPlan, config: dict | None = None) -> QueryAnalysis:
    if plan.analysis is not None:
        return plan.analysis
    analysis = build_query_analysis(plan.query, config, repo=plan.repo)
    return replace(analysis, preferred_fact_kinds=tuple(preferred_fact_kinds(plan.intent, config)))


def substring_match_count(text: str, terms: Sequence[str]) -> int:
    return sum(1 for term in unique_terms(terms)[:12] if term and term in text)


def row_path_match_count(path: str, analysis: QueryAnalysis) -> int:
    terms = list(analysis.path_terms or analysis.expanded_terms)
    score = substring_match_count(path, terms)
    score += sum(1 for ext in analysis.preferred_extensions if path.endswith(ext))
    score += substring_match_count(path, analysis.preferred_paths)
    return score


def row_symbol_match_count(symbol: str, analysis: QueryAnalysis) -> int:
    symbol_terms = unique_terms([*analysis.symbol_terms, *analysis.corrected_terms, *analysis.terms])
    return substring_match_count(symbol, symbol_terms)


def row_file_type_match_count(language: str, kind: str, path: str, analysis: QueryAnalysis) -> int:
    score = 0
    if language in analysis.preferred_languages:
        score += 1
    if kind in analysis.preferred_kinds:
        score += 1
    if any(path.endswith(ext) for ext in analysis.preferred_extensions):
        score += 1
    if any(segment in path for segment in analysis.preferred_paths):
        score += 1
    return score


def weak_recency_bonus(modified_at: float | None, max_modified_at: float, config: dict) -> float:
    if not modified_at or max_modified_at <= 0:
        return 0.0
    return (float(modified_at) / float(max_modified_at)) * float(
        query_intelligence_config(config).get("boosts", {}).get("recency_weight", 0.02)
    )


def truncate_text(text: str, limit: int) -> str:
    stripped = text.strip()
    if len(stripped) <= limit:
        return stripped
    return stripped[: limit - 3].rstrip() + "..."


def repo_index_row(conn: sqlite3.Connection, repo: str | None) -> sqlite3.Row | None:
    if not repo:
        return None
    return conn.execute("SELECT * FROM indexed_repos WHERE repo = ?", (repo,)).fetchone()


def capture_git_context(conn: sqlite3.Connection, repo: str | None) -> sqlite3.Row | None:
    repo_row = repo_index_row(conn, repo)
    if repo_row is None:
        return None
    root = Path(repo_row["root"])
    branch = git_branch_for(root)
    if not branch:
        return None

    def run_git(*args: str) -> str:
        try:
            return subprocess.check_output(
                ["git", "-C", str(root), *args],
                stderr=subprocess.DEVNULL,
                text=True,
            ).strip()
        except subprocess.CalledProcessError:
            return ""

    status_short = run_git("status", "--short")
    diff_text = run_git("diff", "--", ".")
    staged_diff_text = run_git("diff", "--staged", "--", ".")
    recent_log_text = run_git("log", "--oneline", "-20")
    changed_files = [
        line[3:].strip()
        for line in status_short.splitlines()
        if len(line.strip()) >= 4
    ]
    upsert_git_context(
        conn,
        str(repo),
        branch,
        head_commit=git_head_commit_for(root),
        indexed_branch=repo_row["last_indexed_branch"],
        indexed_commit=repo_row["last_indexed_commit"],
        dirty=bool(status_short.strip()),
        status_short=status_short,
        diff_text=diff_text,
        staged_diff_text=staged_diff_text,
        recent_log_text=recent_log_text,
        changed_files=changed_files,
    )
    return conn.execute(
        "SELECT * FROM git_context WHERE repo = ? AND branch = ?",
        (repo, branch),
    ).fetchone()


def git_context_relevant(plan: RetrievalPlan, row: sqlite3.Row | None) -> bool:
    if row is None:
        return False
    lowered = plan.query.lower()
    markers = (
        "diff",
        "staged",
        "unstaged",
        "branch",
        "working tree",
        "current work",
        "changed",
        "commit",
        "pr ",
        "issue ",
        "failing",
        "error",
        "broken",
    )
    return plan.mode in {"deep", "agent"} or bool(row["dirty"]) or any(marker in lowered for marker in markers)


def extract_reference_numbers(query: str) -> list[int]:
    numbers = [int(match) for match in re.findall(r"(?:#|pr\s+|issue\s+)(\d+)", query.lower())]
    return list(dict.fromkeys(numbers))


def github_context_hits(conn: sqlite3.Connection, plan: RetrievalPlan) -> list[sqlite3.Row]:
    clauses: list[str] = []
    params: list[object] = []
    if plan.repo:
        clauses.append("repo = ?")
        params.append(plan.repo)
    numbers = extract_reference_numbers(plan.query)
    if numbers:
        placeholders = ",".join("?" for _ in numbers)
        clauses.append(f"ref_number IN ({placeholders})")
        params.extend(numbers)
    else:
        analysis = analysis_for_plan(plan)
        term_clauses = []
        for term in list(analysis.expanded_terms)[:6]:
            term_clauses.append("(title LIKE ? OR body LIKE ? OR changed_files_json LIKE ? OR comments_json LIKE ?)")
            params.extend([f"%{term}%", f"%{term}%", f"%{term}%", f"%{term}%"])
        if term_clauses:
            clauses.append("(" + " OR ".join(term_clauses) + ")")
    sql = "SELECT * FROM github_context"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY updated_at DESC LIMIT 4"
    return conn.execute(sql, params).fetchall()


def exact_query_fingerprint(query: str) -> str | None:
    normalized = normalize_error_text(query)
    if len(normalized) < 12 or (
        "error" not in normalized and "failed" not in normalized and "traceback" not in normalized
    ):
        return None
    return fingerprint_error(normalized)


def test_failure_hits(conn: sqlite3.Connection, plan: RetrievalPlan) -> list[sqlite3.Row]:
    fingerprint = exact_query_fingerprint(plan.query)
    if fingerprint:
        rows = conn.execute(
            """
            SELECT * FROM test_failure_memory
            WHERE fingerprint_hash = ?
              AND (? IS NULL OR repo = ?)
            ORDER BY updated_at DESC
            LIMIT 4
            """,
            (fingerprint, plan.repo, plan.repo),
        ).fetchall()
        if rows:
            return rows
    analysis = analysis_for_plan(plan)
    terms = list(analysis.expanded_terms)[:6]
    if not terms and plan.intent != "error":
        return []
    clauses: list[str] = []
    params: list[object] = []
    if plan.repo:
        clauses.append("repo = ?")
        params.append(plan.repo)
    term_clauses = []
    for term in terms:
        term_clauses.append("(output_text LIKE ? OR command LIKE ? OR file_paths_json LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%", f"%{term}%"])
    if term_clauses:
        clauses.append("(" + " OR ".join(term_clauses) + ")")
    sql = "SELECT * FROM test_failure_memory"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY updated_at DESC LIMIT 4"
    return conn.execute(sql, params).fetchall()


def error_matches(conn: sqlite3.Connection, plan: RetrievalPlan) -> list[sqlite3.Row]:
    fingerprint = exact_query_fingerprint(plan.query)
    if fingerprint:
        rows = conn.execute(
            """
            SELECT * FROM error_memory
            WHERE fingerprint_hash = ?
              AND (? IS NULL OR repo = ?)
            ORDER BY updated_at DESC
            LIMIT 4
            """,
            (fingerprint, plan.repo, plan.repo),
        ).fetchall()
        if rows:
            return rows
    analysis = analysis_for_plan(plan)
    terms = list(analysis.expanded_terms)[:6]
    if not terms and plan.intent != "error":
        return []
    clauses: list[str] = []
    params: list[object] = []
    if plan.repo:
        clauses.append("repo = ?")
        params.append(plan.repo)
    term_clauses = []
    for term in terms:
        term_clauses.append("(error_text LIKE ? OR fix_text LIKE ? OR file_paths_json LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%", f"%{term}%"])
    if term_clauses:
        clauses.append("(" + " OR ".join(term_clauses) + ")")
    sql = "SELECT * FROM error_memory"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY updated_at DESC LIMIT 4"
    return conn.execute(sql, params).fetchall()


def semantic_hits(client: SupportsQdrantQuery, config: dict, plan: RetrievalPlan) -> list[str]:
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
        match = fts_match_terms(tokens)
        if not match:
            continue
        sql = (
            "SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ?"
            + (" AND repo = ?" if plan.repo else "")
            + " LIMIT ?"
        )
        params = [match] + ([plan.repo] if plan.repo else []) + [limit]
        hits.extend(row["chunk_id"] for row in conn.execute(sql, params).fetchall())
    return hits


def semantic_line_hits(conn: sqlite3.Connection, config: dict, plan: RetrievalPlan) -> list[str]:
    hits: list[str] = []
    limit = int(config["retrieval_pipeline"]["keyword_limit"])
    for rewrite in plan.rewrites[: int(config["retrieval_pipeline"]["rewrite_limit"])]:
        tokens = query_terms(rewrite)
        if not tokens:
            continue
        match = fts_match_terms(tokens)
        if not match:
            continue
        sql = (
            "SELECT chunk_id FROM semantic_lines_fts WHERE semantic_lines_fts MATCH ?"
            + (" AND repo = ?" if plan.repo else "")
            + " LIMIT ?"
        )
        params = [match] + ([plan.repo] if plan.repo else []) + [limit]
        hits.extend(row["chunk_id"] for row in conn.execute(sql, params).fetchall())
    return hits


def symbol_hits(conn: sqlite3.Connection, plan: RetrievalPlan) -> list[str]:
    terms = query_terms(plan.query)[:10]
    if not terms:
        return []
    match = fts_match_terms(terms, limit=10)
    if not match:
        return []
    sql = (
        "SELECT symbol_id FROM symbols_fts WHERE symbols_fts MATCH ?"
        + (" AND repo = ?" if plan.repo else "")
        + " LIMIT 20"
    )
    params = [match] + ([plan.repo] if plan.repo else [])
    symbol_rows = conn.execute(sql, params).fetchall()
    hits: list[str] = []
    for row in symbol_rows:
        chunk = conn.execute(
            """
            SELECT c.chunk_id
            FROM chunks c
            JOIN symbols s ON s.repo = c.repo AND s.path = c.path
            WHERE s.symbol_id = ?
              AND c.start_line <= s.end_line
              AND c.end_line >= s.start_line
            ORDER BY ABS(c.start_line - s.start_line), c.chunk_index
            LIMIT 1
            """,
            (row["symbol_id"],),
        ).fetchone()
        if chunk is not None:
            hits.append(chunk["chunk_id"])
    return hits


def recent_hits(conn: sqlite3.Connection, config: dict, plan: RetrievalPlan) -> list[str]:
    analysis = analysis_for_plan(plan, config)
    metadata_terms = unique_terms(
        [
            *analysis.expanded_terms,
            *analysis.path_terms,
            *analysis.symbol_terms,
            *analysis.preferred_paths,
        ]
    )[:10]
    if not metadata_terms and not analysis.preferred_languages and not analysis.preferred_kinds:
        return []
    clauses = []
    params: list[object] = []
    for term in metadata_terms:
        clauses.append("(path LIKE ? OR symbol LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%"])
    for language in analysis.preferred_languages[:4]:
        clauses.append("language = ?")
        params.append(language)
    for kind in analysis.preferred_kinds[:4]:
        clauses.append("kind = ?")
        params.append(kind)
    sql = "SELECT * FROM chunks WHERE (" + " OR ".join(clauses) + ")"
    if plan.repo:
        sql += " AND repo = ?"
        params.append(plan.repo)
    candidate_limit = int(config["retrieval_pipeline"]["recent_limit"]) * 8
    sql += " ORDER BY modified_at DESC LIMIT ?"
    params.append(candidate_limit)
    rows = conn.execute(sql, params).fetchall()
    if not rows:
        return []
    max_modified = max(float(row["modified_at"] or 0.0) for row in rows) or 1.0
    scored: list[tuple[float, str]] = []
    for row in rows:
        path_lower = row["path"].lower()
        symbol_lower = (row["symbol"] or "").lower()
        score = float(row_path_match_count(path_lower, analysis)) * 1.3
        score += float(row_symbol_match_count(symbol_lower, analysis)) * 1.5
        score += float(row_file_type_match_count(row["language"], row["kind"], path_lower, analysis))
        score += weak_recency_bonus(row["modified_at"], max_modified, config)
        if score <= 0:
            continue
        scored.append((score, row["chunk_id"]))
    ranked = [chunk_id for _score, chunk_id in sorted(scored, key=lambda item: item[0], reverse=True)]
    return unique_terms(ranked)[: int(config["retrieval_pipeline"]["recent_limit"])]


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
    analysis = analysis_for_plan(plan, config)
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
    terms = list(analysis.expanded_terms)[:10]
    if not terms:
        return []
    clauses = []
    params: list[str] = []
    for term in terms:
        clauses.append("(key LIKE ? OR value LIKE ? OR path LIKE ? OR kind LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%", f"%{term}%", f"%{term}%"])
    sql = "SELECT * FROM facts WHERE (" + " OR ".join(clauses) + ")"
    if plan.repo:
        sql += " AND repo = ?"
        params.append(plan.repo)
    sql += " ORDER BY confidence DESC, updated_at DESC LIMIT 48"
    rows = conn.execute(sql, params).fetchall()
    boosts = query_intelligence_config(config).get("boosts", {})
    scored: list[tuple[float, sqlite3.Row]] = []
    for row in rows:
        key_lower = row["key"].lower()
        value_lower = row["value"].lower()
        path_lower = row["path"].lower()
        kind_lower = row["kind"].lower()
        score = substring_match_count(key_lower, analysis.expanded_terms) * 2.6
        score += substring_match_count(value_lower, analysis.expanded_terms) * 1.2
        score += substring_match_count(path_lower, analysis.expanded_terms) * 1.3
        score += substring_match_count(kind_lower, analysis.expanded_terms) * 1.1
        if row["kind"] in analysis.preferred_fact_kinds:
            score += float(boosts.get("fact_kind_weight", 1.4))
        score += float(row_path_match_count(path_lower, analysis)) * 0.5
        if plan.intent == "tool" and row["kind"] in {"tool", "alias", "package-script", "compose-service"}:
            score += 1.2
        if plan.intent == "config" and row["kind"] in {"config-key", "config-section", "env", "compose-config", "compose-env"}:
            score += 1.0
        if plan.intent == "sql" and row["kind"] == "sql-object":
            score += 1.2
        if plan.intent == "symbol" and row["kind"] in {"function", "service", "entity", "module", "route-handler", "route-controller"}:
            score += 1.1
        if score > 0:
            scored.append((score, row))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [row for _score, row in scored[:12]]


def file_summary_hits(conn: sqlite3.Connection, plan: RetrievalPlan, config: dict | None = None) -> list[sqlite3.Row]:
    analysis = analysis_for_plan(plan, config)
    terms = list(analysis.expanded_terms)[:10]
    if not terms:
        return []
    clauses = []
    params: list[str] = []
    for term in terms:
        clauses.append("(path LIKE ? OR summary LIKE ? OR symbols LIKE ? OR language LIKE ? OR kind LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%", f"%{term}%", f"%{term}%", f"%{term}%"])
    sql = "SELECT * FROM file_summaries WHERE (" + " OR ".join(clauses) + ")"
    if plan.repo:
        sql += " AND repo = ?"
        params.append(plan.repo)
    sql += " ORDER BY updated_at DESC LIMIT 32"
    rows = conn.execute(sql, params).fetchall()
    scored = []
    summary_boost = float(query_intelligence_config(config).get("boosts", {}).get("summary_kind_weight", 1.0))
    for row in rows:
        score = 0.0
        path_lower = row["path"].lower()
        summary_lower = row["summary"].lower()
        symbols_lower = (row["symbols"] or "").lower()
        score += substring_match_count(summary_lower, analysis.expanded_terms) * 1.4
        score += float(row_path_match_count(path_lower, analysis)) * 1.2
        score += float(row_symbol_match_count(symbols_lower, analysis)) * 1.5
        score += float(row_file_type_match_count(row["language"], row["kind"], path_lower, analysis))
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
        elif plan.intent == "config" and row["kind"] == "config":
            score += summary_boost
        elif plan.intent == "symbol" and symbols_lower:
            score += summary_boost
        elif plan.intent == "sql" and (
            row["language"] == "sql" or any(token in path_lower for token in ("sql", "migration", "schema"))
        ):
            score += summary_boost
        scored.append((score, row))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [row for _score, row in scored[:10]]


def repo_memory_row(conn: sqlite3.Connection, repo: str | None) -> sqlite3.Row | None:
    if not repo:
        return None
    return conn.execute("SELECT * FROM repo_memory WHERE repo = ?", (repo,)).fetchone()


def json_list(value: str | None) -> list[str]:
    if not value:
        return []
    try:
        loaded = json.loads(value)
    except json.JSONDecodeError:
        return []
    if not isinstance(loaded, list):
        return []
    return [str(item) for item in loaded if str(item).strip()]


def primary_paths(rows: Sequence[sqlite3.Row]) -> list[str]:
    return list(dict.fromkeys(str(row["path"]) for row in rows if row["path"]))[:6]


def supporting_rows_for_paths(conn: sqlite3.Connection, repo: str | None, paths: Sequence[str]) -> list[sqlite3.Row]:
    if not repo or not paths:
        return []
    seen: set[str] = set()
    results: list[sqlite3.Row] = []
    for path in paths:
        row = conn.execute(
            """
            SELECT * FROM chunks
            WHERE repo = ? AND path = ?
            ORDER BY modified_at DESC, chunk_index ASC
            LIMIT 1
            """,
            (repo, path),
        ).fetchone()
        if row is not None and row["chunk_id"] not in seen:
            seen.add(str(row["chunk_id"]))
            results.append(row)
    return results


def supporting_summaries_for_paths(conn: sqlite3.Connection, repo: str | None, paths: Sequence[str]) -> list[sqlite3.Row]:
    if not repo or not paths:
        return []
    seen: set[tuple[str, str]] = set()
    results: list[sqlite3.Row] = []
    for path in paths:
        row = conn.execute(
            """
            SELECT * FROM file_summaries
            WHERE repo = ? AND path = ?
            ORDER BY updated_at DESC
            LIMIT 1
            """,
            (repo, path),
        ).fetchone()
        key = (repo, path)
        if row is not None and key not in seen:
            seen.add(key)
            results.append(row)
    return results


def supplementary_summary_search(
    conn: sqlite3.Connection,
    repo: str | None,
    terms: Sequence[str],
    *,
    kind: str | None = None,
    path_markers: Sequence[str] = (),
    limit: int = 3,
) -> list[sqlite3.Row]:
    clauses: list[str] = []
    params: list[object] = []
    if repo:
        clauses.append("repo = ?")
        params.append(repo)
    if kind:
        clauses.append("kind = ?")
        params.append(kind)
    marker_clauses = []
    for marker in path_markers:
        marker_clauses.append("path LIKE ?")
        params.append(f"%{marker}%")
    term_clauses = []
    for term in unique_terms(terms)[:6]:
        term_clauses.append("(path LIKE ? OR summary LIKE ? OR symbols LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%", f"%{term}%"])
    if marker_clauses:
        clauses.append("(" + " OR ".join(marker_clauses) + ")")
    if term_clauses:
        clauses.append("(" + " OR ".join(term_clauses) + ")")
    sql = "SELECT * FROM file_summaries"
    if clauses:
        sql += " WHERE " + " AND ".join(clauses)
    sql += " ORDER BY updated_at DESC LIMIT ?"
    params.append(limit)
    return conn.execute(sql, params).fetchall()


def expected_missing_context_categories(plan: RetrievalPlan) -> list[str]:
    desired: list[str] = []
    if plan.intent in {"symbol", "path", "general"}:
        desired.extend(["definition file", "caller file", "test file"])
    if plan.intent in {"config", "tool", "error"}:
        desired.append("config file")
    if plan.intent == "sql" or any(
        token in plan.query.lower() for token in ("schema", "entity", "model", "table", "migration", "orm")
    ):
        desired.append("schema/entity file")
    if plan.intent in {"error", "general", "symbol"}:
        desired.append("related docs")
    if plan.intent == "error":
        desired.append("error log")
    return unique_terms(desired)



def detect_missing_context(
    conn: sqlite3.Connection,
    plan: RetrievalPlan,
    rows: Sequence[sqlite3.Row],
    summaries: Sequence[sqlite3.Row],
    candidates: RetrievalCandidates,
) -> tuple[dict[str, list[str]], list[sqlite3.Row], list[sqlite3.Row]]:
    analysis = analysis_for_plan(plan)
    observed = {
        "test file": any("test" in row["path"].lower() or "spec" in row["path"].lower() for row in rows)
        or any("test" in row["path"].lower() or "spec" in row["path"].lower() for row in summaries),
        "config file": any(row["kind"] == "config" for row in rows)
        or any(row["kind"] == "config" for row in summaries),
        "related docs": any(row["kind"] == "docs" or row["path"].lower().endswith(".md") for row in rows)
        or any(row["kind"] == "docs" or row["path"].lower().endswith(".md") for row in summaries),
        "schema/entity file": any(
            any(marker in row["path"].lower() for marker in ("schema", "entity", "model", "migration"))
            for row in [*rows, *summaries]
        ),
        "definition file": any(row["symbol"] for row in rows) or plan.intent == "path",
        "caller file": any(
            "test" in row["path"].lower() or "spec" in row["path"].lower()
            for row in [*rows, *summaries]
        ),
        "error log": bool(candidates.test_failures or candidates.error_matches),
    }
    selected_paths = primary_paths(rows)
    desired = expected_missing_context_categories(plan)
    added: list[str] = []
    extra_summaries: list[sqlite3.Row] = []
    extra_rows: list[sqlite3.Row] = []
    term_seed = [*analysis.expanded_terms, *selected_paths]

    def add_summaries(category: str, rows_to_add: Sequence[sqlite3.Row]) -> None:
        if rows_to_add:
            added.append(category)
            extra_summaries.extend(rows_to_add)

    missing = [category for category in desired if not observed.get(category, False)]
    for category in missing:
        if category == "test file":
            stems = [Path(path).stem.replace(".test", "").replace(".spec", "") for path in selected_paths]
            add_summaries(category, supplementary_summary_search(conn, plan.repo, stems or term_seed, path_markers=("test", "spec", "__tests__"), limit=2))
        elif category == "config file":
            add_summaries(category, supplementary_summary_search(conn, plan.repo, term_seed, kind="config", limit=2))
        elif category == "related docs":
            doc_rows = supplementary_summary_search(
                conn,
                plan.repo,
                term_seed,
                kind="docs",
                path_markers=("docs", "readme"),
                limit=2,
            )
            if not doc_rows:
                doc_rows = supplementary_summary_search(
                    conn,
                    plan.repo,
                    [],
                    kind="docs",
                    path_markers=("docs", "readme"),
                    limit=2,
                )
            add_summaries(category, doc_rows)
        elif category == "schema/entity file":
            add_summaries(category, supplementary_summary_search(conn, plan.repo, term_seed, path_markers=("schema", "entity", "model", "migration"), limit=2))
        elif category == "definition file" and plan.repo:
            definition_rows = supporting_rows_for_paths(conn, plan.repo, selected_paths[:1])
            if definition_rows:
                added.append(category)
                extra_rows.extend(definition_rows)
        elif category == "caller file" and plan.repo and selected_paths:
            caller_rows = conn.execute(
                f"""
                SELECT source_path
                FROM file_dependencies
                WHERE repo = ?
                  AND source_path != target_path
                  AND target_path IN ({",".join("?" for _ in selected_paths)})
                ORDER BY updated_at DESC
                LIMIT 2
                """,
                [plan.repo, *selected_paths],
            ).fetchall()
            caller_paths = [str(row["source_path"]) for row in caller_rows]
            supporting = supporting_rows_for_paths(conn, plan.repo, caller_paths)
            if supporting:
                added.append(category)
                extra_rows.extend(supporting)
                continue
            caller_summaries = supporting_summaries_for_paths(conn, plan.repo, caller_paths)
            if caller_summaries:
                added.append(category)
                extra_summaries.extend(caller_summaries)
    unresolved = [category for category in desired if category not in added and not observed.get(category, False)]
    unique_extra_rows = {row["chunk_id"]: row for row in extra_rows}
    unique_extra_summaries = {(row["repo"], row["path"]): row for row in extra_summaries}
    return {"desired": desired, "added": added, "missing": unresolved}, list(unique_extra_rows.values()), list(unique_extra_summaries.values())


def build_context_sources(
    candidates: RetrievalCandidates,
    missing_report: dict[str, list[str]],
) -> list[ContextSource]:
    sources: list[ContextSource] = []
    git_row = candidates.git_context
    if git_row is not None and git_context_relevant(candidates.plan, git_row):
        changed_files = json_list(git_row["changed_files_json"])
        branch_note = ""
        if git_row["indexed_branch"] and git_row["indexed_branch"] != git_row["branch"]:
            branch_note = f"\nindexed_branch={git_row['indexed_branch']} (mismatch)"
        sources.append(
            ContextSource(
                source_type="git",
                title=f"git branch {git_row['branch']}",
                content=(
                    f"branch={git_row['branch']} head={git_row['head_commit'] or '-'} dirty={'yes' if git_row['dirty'] else 'no'}"
                    f"{branch_note}\nindexed_commit={git_row['indexed_commit'] or '-'}\n"
                    f"changed_files={', '.join(changed_files[:8]) or '-'}\n"
                    f"status:\n{truncate_text(git_row['status_short'], 400) or '-'}\n"
                    f"unstaged diff:\n{truncate_text(git_row['diff_text'], 600) or '-'}\n"
                    f"staged diff:\n{truncate_text(git_row['staged_diff_text'], 600) or '-'}\n"
                    f"recent log:\n{truncate_text(git_row['recent_log_text'], 400) or '-'}"
                ),
                file_refs=tuple(changed_files[:8]),
            )
        )
    for row in candidates.github_refs:
        changed_files = json_list(row["changed_files_json"])
        comments = json_list(row["comments_json"])
        review_comments = json_list(row["review_comments_json"])
        linked = json_list(row["linked_issues_json"])
        sources.append(
            ContextSource(
                source_type="github",
                title=f"{row['ref_type']} #{row['ref_number']}",
                content=(
                    f"title={row['title']}\nbody={truncate_text(row['body'], 500) or '-'}\n"
                    f"changed_files={', '.join(changed_files[:8]) or '-'}\n"
                    f"linked={', '.join(linked[:6]) or '-'}\n"
                    f"comments={truncate_text(' | '.join(comments[:3]), 300) or '-'}\n"
                    f"review_comments={truncate_text(' | '.join(review_comments[:3]), 300) or '-'}\n"
                    f"ci={truncate_text(row['ci_logs_text'], 300) or '-'}"
                ),
                file_refs=tuple(changed_files[:8]),
            )
        )
    for row in candidates.test_failures:
        file_refs = tuple(json_list(row["file_paths_json"])[:8])
        stack_symbols = json_list(row["stack_symbols_json"])
        sources.append(
            ContextSource(
                source_type="test_failure",
                title=f"test failure {row['fingerprint_hash']}",
                content=(
                    f"command={row['command']} exit_code={row['exit_code'] if row['exit_code'] is not None else '-'} "
                    f"runner={row['runner'] or '-'} source={row['source']}\n"
                    f"files={', '.join(file_refs) or '-'}\n"
                    f"symbols={', '.join(stack_symbols[:6]) or '-'}\n"
                    f"output={truncate_text(row['output_text'], 700)}"
                ),
                file_refs=file_refs,
            )
        )
    for row in candidates.error_matches:
        file_refs = tuple(json_list(row["file_paths_json"])[:8])
        stack_symbols = json_list(row["stack_symbols_json"])
        sources.append(
            ContextSource(
                source_type="error",
                title=f"error {row['fingerprint_hash'] or '-'}",
                content=(
                    f"normalized={truncate_text(row['normalized_error'] or normalize_error_text(row['error_text']), 240)}\n"
                    f"command={row['command'] or '-'} exit_code={row['exit_code'] if row['exit_code'] is not None else '-'}\n"
                    f"files={', '.join(file_refs) or '-'}\n"
                    f"symbols={', '.join(stack_symbols[:6]) or '-'}\n"
                    f"fix={truncate_text(row['fix_text'] or '', 220) or '-'}"
                ),
                file_refs=file_refs,
            )
        )
    if missing_report.get("desired"):
        sources.append(
            ContextSource(
                source_type="missing_context",
                title="missing context detector",
                content=(
                    f"desired={', '.join(missing_report['desired']) or '-'}\n"
                    f"added={', '.join(missing_report.get('added', [])) or '-'}\n"
                    f"still_missing={', '.join(missing_report.get('missing', [])) or '-'}"
                ),
            )
        )
    return sources


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
    plan: RetrievalPlan,
    rows: Sequence[sqlite3.Row],
    base_scores: dict[str, float],
    config: dict,
    fact_paths: set[str],
    summary_paths: set[str],
) -> list[sqlite3.Row]:
    reranker_config = config["reranker"]
    analysis = analysis_for_plan(plan, config)
    query_terms_set = set(analysis.expanded_terms or analysis.terms)
    boosts = query_intelligence_config(config).get("boosts", {})
    max_modified = max((float(row["modified_at"] or 0.0) for row in rows), default=1.0) or 1.0
    scored = []
    for row in rows:
        content_terms = set(query_terms(row["content"])) | set(query_terms(row["path"])) | set(
            query_terms(row["symbol"] or "")
        )
        overlap = len(query_terms_set & content_terms)
        path_lower = row["path"].lower()
        symbol = row["symbol"] or ""
        symbol_lower = symbol.lower()
        path_bonus = row_path_match_count(path_lower, analysis)
        symbol_bonus = row_symbol_match_count(symbol_lower, analysis)
        file_type_bonus = row_file_type_match_count(row["language"], row["kind"], path_lower, analysis)
        final_score = (
            base_scores.get(row["chunk_id"], 0.0)
            + (overlap * reranker_config["content_weight"])
            + (path_bonus * reranker_config["path_weight"])
            + (symbol_bonus * reranker_config["symbol_weight"])
            + (file_type_bonus * float(boosts.get("file_type_weight", 0.05)))
            + weak_recency_bonus(row["modified_at"], max_modified, config)
        )
        if plan.intent == "keybind":
            if row["language"] == "hyprland":
                final_score += 0.24
            if row["kind"] == "config":
                final_score += 0.08
            if symbol.startswith("bind:") or symbol == "entries":
                final_score += 0.12
            if any(token in path_lower for token in ("hyprland.conf", "hyprland.yaml", "keybind", "cheatsheet")):
                final_score += 0.12
        elif plan.intent == "tool":
            if symbol.startswith("tool:"):
                final_score += 0.2
            if row["language"] == "shell":
                final_score += 0.05
        elif plan.intent == "config" and row["kind"] == "config":
            final_score += 0.08
        elif plan.intent == "sql" and row["language"] == "sql":
            final_score += 0.08
        elif plan.intent == "symbol" and symbol_bonus:
            final_score += float(boosts.get("symbol_weight", 0.08))
        elif plan.intent == "path" and path_bonus:
            final_score += float(boosts.get("path_weight", 0.08))
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
    client: SupportsQdrantQuery,
    config: dict,
    plan: RetrievalPlan,
) -> RetrievalCandidates:
    timings_ms: dict[str, float] = {}
    started = time.perf_counter()
    git_row = capture_git_context(conn, plan.repo)
    timings_ms["git_context"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    semantic_ids = semantic_hits(client, config, plan)
    timings_ms["semantic"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    keyword_ids = keyword_hits(conn, config, plan)
    timings_ms["keyword"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    semantic_line_ids = semantic_line_hits(conn, config, plan)
    timings_ms["semantic_lines"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    symbol_ids = symbol_hits(conn, plan)
    timings_ms["symbol_lookup"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    recent_ids = recent_hits(conn, config, plan)
    timings_ms["recent"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    facts = fact_hits(conn, plan, config)
    timings_ms["facts"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    summaries = file_summary_hits(conn, plan, config)
    timings_ms["summaries"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    memory = repo_memory_row(conn, plan.repo)
    timings_ms["memory"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    github_refs = github_context_hits(conn, plan)
    timings_ms["github"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    test_failures = test_failure_hits(conn, plan)
    timings_ms["test_failures"] = (time.perf_counter() - started) * 1000

    started = time.perf_counter()
    errors = error_matches(conn, plan)
    timings_ms["errors"] = (time.perf_counter() - started) * 1000
    return RetrievalCandidates(
        plan=plan,
        semantic_ids=semantic_ids,
        keyword_ids=keyword_ids,
        semantic_line_ids=semantic_line_ids,
        symbol_ids=symbol_ids,
        recent_ids=recent_ids,
        facts=facts,
        summaries=summaries,
        memory=memory,
        git_context=git_row if git_context_relevant(plan, git_row) else None,
        github_refs=github_refs,
        test_failures=test_failures,
        error_matches=errors,
        timings_ms=timings_ms,
    )


def rank_retrieval_candidates(
    conn: sqlite3.Connection,
    config: dict,
    candidates: RetrievalCandidates,
    use_reranker: bool,
) -> RetrievalResult:
    started = time.perf_counter()
    fact_paths = {row["path"] for row in candidates.facts}
    summary_paths = {row["path"] for row in candidates.summaries}
    scores = reciprocal_rank_fusion(
        candidates.semantic_ids,
        candidates.keyword_ids,
        candidates.semantic_line_ids,
        candidates.symbol_ids,
        candidates.recent_ids,
    )
    ranked_ids = [chunk_id for chunk_id, _ in sorted(scores.items(), key=lambda item: item[1], reverse=True)]
    rows = load_chunks(conn, ranked_ids[: config["reranker"]["top_k_input"]])
    candidates.timings_ms["load_chunks"] = (time.perf_counter() - started) * 1000
    started = time.perf_counter()
    selected_rows = (
        rerank_chunks(
            candidates.plan,
            rows,
            scores,
            config,
            fact_paths,
            summary_paths,
        )
        if use_reranker
        else rows[: config["reranker"]["top_k_output"]]
    )
    candidates.timings_ms["rerank"] = (time.perf_counter() - started) * 1000
    started = time.perf_counter()
    missing_report, extra_rows, extra_summaries = detect_missing_context(
        conn,
        candidates.plan,
        selected_rows,
        candidates.summaries,
        candidates,
    )
    candidates.timings_ms["missing_context"] = (time.perf_counter() - started) * 1000
    if extra_rows:
        merged_rows = list(selected_rows)
        seen_chunk_ids = {row["chunk_id"] for row in merged_rows}
        for row in extra_rows:
            if row["chunk_id"] not in seen_chunk_ids:
                seen_chunk_ids.add(row["chunk_id"])
                merged_rows.append(row)
        selected_rows = merged_rows
    if extra_summaries:
        seen_summaries = {(row["repo"], row["path"]) for row in candidates.summaries}
        for row in extra_summaries:
            key = (row["repo"], row["path"])
            if key not in seen_summaries:
                seen_summaries.add(key)
                candidates.summaries.append(row)
    context_sources = build_context_sources(candidates, missing_report)
    debug = {
        "rewrites": candidates.plan.rewrites,
        "semantic_hits": len(candidates.semantic_ids),
        "keyword_hits": len(candidates.keyword_ids),
        "semantic_line_hits": len(candidates.semantic_line_ids),
        "symbol_hits": len(candidates.symbol_ids),
        "recent_hits": len(candidates.recent_ids),
        "fact_hits": len(candidates.facts),
        "file_summary_hits": len(candidates.summaries),
        "memory_loaded": candidates.memory is not None,
        "merged_unique": len(scores),
        "ranking_enabled": use_reranker,
        "ranking_mode": config["reranker"]["mode"],
        "intent": candidates.plan.intent,
        "mode": candidates.plan.mode,
        "typo_corrections": list(candidates.plan.analysis.corrected_terms) if candidates.plan.analysis else [],
        "preferred_languages": list(candidates.plan.analysis.preferred_languages) if candidates.plan.analysis else [],
        "git_context": bool(candidates.git_context),
        "github_refs": len(candidates.github_refs),
        "test_failures": len(candidates.test_failures),
        "error_matches": len(candidates.error_matches),
        "missing_context_desired": missing_report.get("desired", []),
        "missing_context_added": missing_report.get("added", []),
        "missing_context_remaining": missing_report.get("missing", []),
        "timings_ms": {key: round(value, 2) for key, value in candidates.timings_ms.items()},
    }
    return RetrievalResult(
        plan=candidates.plan,
        rows=selected_rows,
        facts=candidates.facts,
        summaries=candidates.summaries,
        memory=candidates.memory,
        context_sources=context_sources,
        debug=debug,
    )


def retrieve(
    conn: sqlite3.Connection,
    client: SupportsQdrantQuery,
    config: dict,
    query: str,
    repo: str | None,
    use_reranker: bool,
    mode: str = "quick",
) -> RetrievalResult:
    plan = build_retrieval_plan(query, repo, mode=mode, config=config, conn=conn)
    candidates = collect_retrieval_candidates(conn, client, config, plan)
    return rank_retrieval_candidates(conn, config, candidates, use_reranker)


def gather_context(
    rows: Sequence[sqlite3.Row],
    config: dict,
    facts: Sequence[sqlite3.Row] | None = None,
    summaries: Sequence[sqlite3.Row] | None = None,
    context_sources: Sequence[ContextSource] | None = None,
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

    def add_operational_state() -> None:
        if operational_state:
            append_block(
                f"<operational_state>\n{operational_state}\n</operational_state>",
                limit=operational_state_tokens or budgets["memory_tokens"],
            )

    def add_repo_memory() -> None:
        if memory:
            append_block(f"<repo_memory>\n{memory}\n</repo_memory>", limit=budgets["memory_tokens"])

    def add_context_sources() -> None:
        if not context_sources:
            return
        source_blocks: list[str] = []
        source_used = 0
        source_limit = int(budgets.get("context_source_tokens", budgets["file_summary_tokens"]))
        for index, source in enumerate(context_sources, start=1):
            block = f"[SOURCE {index}] type={source.source_type} title={source.title}\n{source.content}"
            block_tokens = approx_tokens(block)
            if source_used + block_tokens > source_limit:
                break
            source_used += block_tokens
            source_blocks.append(block)
            for file_ref in source.file_refs:
                if file_ref not in seen_files:
                    seen_files.append(file_ref)
        if source_blocks:
            append_block("<context_sources>\n" + "\n\n".join(source_blocks) + "\n</context_sources>", limit=source_limit)

    def add_facts() -> None:
        if not facts:
            return
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

    def add_file_summaries() -> None:
        if not summaries:
            return
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

    def add_chunks() -> None:
        chunk_blocks: list[str] = []
        chunk_used = 0
        for row in limit_rows_per_file(rows, config["retrieval"]["max_chunks_per_file"]):
            block = (
                f"[{len(chunk_blocks)+1}] {row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}\n"
                f"kind={row['kind']} language={row['language']} package={(row['package'] if 'package' in row.keys() else '') or '-'} symbol={row['symbol'] or '-'}\n"
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

    mode_name = str(config.get("answer", {}).get("style", "default"))
    default_order = ["operational_state", "repo_memory", "context_sources", "facts", "file_summaries", "chunks"]
    configured_order = config.get("context_pack_order", {}).get(mode_name, default_order)
    section_builders = {
        "operational_state": add_operational_state,
        "repo_memory": add_repo_memory,
        "context_sources": add_context_sources,
        "facts": add_facts,
        "file_summaries": add_file_summaries,
        "chunks": add_chunks,
    }
    for section_name in configured_order:
        builder = section_builders.get(section_name)
        if builder:
            builder()
    if "chunks" not in configured_order:
        add_chunks()
    return "\n\n".join(sections), list(dict.fromkeys(seen_files))


def print_retrieval_explain(debug: dict, rows: Sequence[sqlite3.Row]) -> None:
    console.print("[bold]Query rewrites:[/bold]")
    for rewrite in debug["rewrites"]:
        console.print(f"- {rewrite}")
    console.print("\n[bold]Retrieval:[/bold]")
    console.print(f"semantic hits: {debug['semantic_hits']}")
    console.print(f"keyword hits: {debug['keyword_hits']}")
    console.print(f"semantic line hits: {debug['semantic_line_hits']}")
    console.print(f"symbol hits: {debug['symbol_hits']}")
    console.print(f"recent/path hits: {debug['recent_hits']}")
    console.print(f"fact hits: {debug['fact_hits']}")
    console.print(f"file summary hits: {debug['file_summary_hits']}")
    console.print(f"repo memory: {'loaded' if debug['memory_loaded'] else 'not loaded'}")
    console.print(f"git context: {'loaded' if debug.get('git_context') else 'not loaded'}")
    console.print(f"github refs: {debug.get('github_refs', 0)}")
    console.print(f"test failures: {debug.get('test_failures', 0)}")
    console.print(f"error matches: {debug.get('error_matches', 0)}")
    console.print(f"merged unique: {debug['merged_unique']}")
    console.print(f"mode: {debug['mode']}")
    console.print(f"intent: {debug['intent']}")
    if debug.get("typo_corrections"):
        console.print(f"typo corrections: {', '.join(debug['typo_corrections'])}")
    if debug.get("preferred_languages"):
        console.print(f"preferred languages: {', '.join(debug['preferred_languages'])}")
    console.print(
        "ranking pass: "
        + (
            f"{debug['ranking_mode']} enabled"
            if debug["ranking_enabled"]
            else f"{debug['ranking_mode']} disabled"
        )
    )
    if debug.get("missing_context_desired"):
        console.print(f"missing-context desired: {', '.join(debug['missing_context_desired'])}")
        console.print(f"missing-context added: {', '.join(debug.get('missing_context_added', [])) or '-'}")
        console.print(f"missing-context remaining: {', '.join(debug.get('missing_context_remaining', [])) or '-'}")
    timings = debug.get("timings_ms") or {}
    if timings:
        console.print(
            "timings (ms): "
            + ", ".join(f"{name}={value:.2f}" if isinstance(value, float) else f"{name}={value}" for name, value in timings.items())
        )
    console.print("\n[bold]Selected:[/bold]")
    for index, row in enumerate(rows[:10], start=1):
        console.print(
            f"{index}. {row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']} "
            f"symbol={row['symbol'] or '-'} kind={row['kind']} language={row['language']}"
        )
