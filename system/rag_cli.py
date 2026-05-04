#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

from gitignore_parser import parse_gitignore
from pathspec import PathSpec
from qdrant_client import QdrantClient, models
from rich.console import Console
from rich.table import Table

try:
    from fastembed import TextEmbedding
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "fastembed is not installed in the RAG venv. Run setup/install-local-rag-stack.sh first."
    ) from exc


console = Console()
RAG_HOME = Path(os.environ.get("RAG_HOME", str(Path.home() / "ai-rag"))).expanduser()
CONFIG_PATH = RAG_HOME / "config.json"
DB_PATH = RAG_HOME / "rag.sqlite3"
DEFAULT_CONFIG = {
    "qdrant_url": "http://127.0.0.1:6333",
    "qdrant_collection": "local-rag-chunks",
    "answer_url": "http://127.0.0.1:8080/v1/chat/completions",
    "answer_model": "local",
    "embedding_model": "BAAI/bge-small-en-v1.5",
    "retrieval_context_tokens": 12000,
    "answer_max_tokens": 2500,
}

DEFAULT_IGNORE_PATTERNS = [
    "node_modules/",
    "dist/",
    "build/",
    ".next/",
    ".turbo/",
    ".git/",
    "coverage/",
    "target/",
    "vendor/",
    "*.lock",
    "pnpm-lock.yaml",
    "package-lock.json",
    "yarn.lock",
    "*.png",
    "*.jpg",
    "*.jpeg",
    "*.gif",
    "*.webp",
    "*.mp4",
    "*.zip",
    "*.tar",
    "*.sqlite",
    "*.db",
    ".env",
    ".env.*",
]

CODE_EXTENSIONS = {
    ".py": "python",
    ".ts": "typescript",
    ".tsx": "typescript",
    ".js": "javascript",
    ".jsx": "javascript",
    ".go": "go",
    ".rs": "rust",
    ".java": "java",
    ".cs": "csharp",
    ".rb": "ruby",
    ".php": "php",
    ".sh": "shell",
    ".zsh": "shell",
    ".lua": "lua",
    ".swift": "swift",
    ".kt": "kotlin",
    ".c": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".h": "c",
    ".hpp": "cpp",
}

MARKDOWN_EXTENSIONS = {".md", ".mdx", ".rst", ".txt"}
CONFIG_EXTENSIONS = {".json", ".yaml", ".yml", ".toml", ".ini", ".conf", ".env"}
LOG_EXTENSIONS = {".log", ".jsonl"}

SYMBOL_PATTERNS = [
    re.compile(r"^\s*(?:export\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:export\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:export\s+)?const\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?\("),
    re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:pub\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:type|enum|struct|impl)\s+([A-Za-z_][A-Za-z0-9_]*)"),
]

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


@dataclass
class Chunk:
    content: str
    start_line: int
    end_line: int
    symbol: str
    kind: str


def load_config() -> dict:
    config = DEFAULT_CONFIG.copy()
    if CONFIG_PATH.exists():
        config.update(json.loads(CONFIG_PATH.read_text()))
    return config


def ensure_db(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS indexed_repos (
            repo TEXT PRIMARY KEY,
            root TEXT NOT NULL,
            last_indexed REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS chunks (
            chunk_id TEXT PRIMARY KEY,
            repo TEXT NOT NULL,
            root TEXT NOT NULL,
            path TEXT NOT NULL,
            language TEXT NOT NULL,
            kind TEXT NOT NULL,
            symbol TEXT,
            modified_at REAL NOT NULL,
            file_hash TEXT NOT NULL,
            chunk_index INTEGER NOT NULL,
            start_line INTEGER NOT NULL,
            end_line INTEGER NOT NULL,
            content TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_chunks_repo_path ON chunks(repo, path);

        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            chunk_id UNINDEXED,
            repo,
            path,
            symbol,
            content
        );
        """
    )
    conn.commit()


def connect_db() -> sqlite3.Connection:
    RAG_HOME.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    ensure_db(conn)
    return conn


def get_qdrant(config: dict) -> QdrantClient:
    return QdrantClient(url=config["qdrant_url"])


_embedder: TextEmbedding | None = None


def get_embedder(config: dict) -> TextEmbedding:
    global _embedder
    if _embedder is None:
        _embedder = TextEmbedding(model_name=config["embedding_model"])
    return _embedder


def ensure_collection(client: QdrantClient, config: dict) -> None:
    collection = config["qdrant_collection"]
    if client.collection_exists(collection):
        return
    embedder = get_embedder(config)
    sample = list(embedder.embed(["bootstrap vector size probe"]))[0]
    client.create_collection(
        collection_name=collection,
        vectors_config=models.VectorParams(size=len(sample), distance=models.Distance.COSINE),
    )


def git_root_for(path: Path) -> Path | None:
    try:
        output = subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        return None
    return Path(output)


def repo_identity(path: Path) -> tuple[Path, str]:
    root = git_root_for(path) or path.resolve()
    return root, root.name


def infer_repo_filter(conn: sqlite3.Connection, explicit_repo: str | None) -> str | None:
    if explicit_repo:
        return explicit_repo
    cwd_root = git_root_for(Path.cwd())
    if cwd_root is None:
        return None
    row = conn.execute(
        "SELECT repo FROM indexed_repos WHERE root = ?",
        (str(cwd_root),),
    ).fetchone()
    return row["repo"] if row else None


def build_ignore_matcher(root: Path):
    spec = PathSpec.from_lines("gitwildmatch", DEFAULT_IGNORE_PATTERNS)
    gitignore_matchers = []
    for candidate in (root / ".gitignore",):
        if candidate.exists():
            gitignore_matchers.append(parse_gitignore(str(candidate)))

    def ignored(full_path: Path) -> bool:
        rel = full_path.relative_to(root).as_posix()
        if rel == ".":
            return False
        if spec.match_file(rel):
            return True
        return any(matcher(str(full_path)) for matcher in gitignore_matchers)

    return ignored


def iter_text_files(root: Path) -> Iterable[Path]:
    ignored = build_ignore_matcher(root)
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if ignored(path):
            continue
        if path.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".pdf"}:
            continue
        yield path


def detect_kind(path: Path) -> tuple[str, str]:
    suffix = path.suffix.lower()
    if suffix in CODE_EXTENSIONS:
        return "code", CODE_EXTENSIONS[suffix]
    if suffix in MARKDOWN_EXTENSIONS:
        return "docs", "markdown"
    if suffix in LOG_EXTENSIONS:
        return "log", "log"
    if suffix in CONFIG_EXTENSIONS:
        return "config", suffix.lstrip(".")
    return "text", suffix.lstrip(".") or "text"


def approx_tokens(text: str) -> int:
    return max(1, math.ceil(len(text) / 4))


def hash_file(path: Path) -> str:
    digest = hashlib.sha1()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def batched(items: Sequence, size: int):
    for index in range(0, len(items), size):
        yield items[index : index + size]


def split_symbol_tokens(token: str) -> list[str]:
    parts = re.findall(r"[A-Z]?[a-z0-9]+|[A-Z]+(?=[A-Z]|$)", token)
    return [part.lower() for part in parts if len(part) > 1]


def extract_symbol(line: str) -> str:
    for pattern in SYMBOL_PATTERNS:
        match = pattern.search(line)
        if match:
            return match.group(1)
    return ""


def chunk_by_lines(lines: list[str], size: int, overlap: int, kind: str, symbol: str = "") -> list[Chunk]:
    chunks: list[Chunk] = []
    start = 0
    while start < len(lines):
        end = min(len(lines), start + size)
        text = "\n".join(lines[start:end]).strip()
        if text:
            chunks.append(
                Chunk(
                    content=text,
                    start_line=start + 1,
                    end_line=end,
                    symbol=symbol,
                    kind=kind,
                )
            )
        if end >= len(lines):
            break
        start = max(start + 1, end - overlap)
    return chunks


def chunk_markdown(text: str) -> list[Chunk]:
    lines = text.splitlines()
    sections: list[tuple[int, int]] = []
    start = 0
    for index, line in enumerate(lines):
        if index and re.match(r"^#{1,6}\s", line):
            sections.append((start, index))
            start = index
    sections.append((start, len(lines)))

    chunks: list[Chunk] = []
    for start, end in sections:
        section_lines = lines[start:end]
        if approx_tokens("\n".join(section_lines)) <= 1100:
            chunks.append(
                Chunk(
                    content="\n".join(section_lines).strip(),
                    start_line=start + 1,
                    end_line=end,
                    symbol=section_lines[0].strip("# ").strip() if section_lines else "",
                    kind="docs",
                )
            )
            continue
        chunks.extend(chunk_by_lines(section_lines, size=90, overlap=18, kind="docs"))
    return [chunk for chunk in chunks if chunk.content]


def chunk_code(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [(index, extract_symbol(line)) for index, line in enumerate(lines) if extract_symbol(line)]
    if not anchors:
        return chunk_by_lines(lines, size=220, overlap=40, kind="code")

    chunks: list[Chunk] = []
    boundaries = [index for index, _symbol in anchors] + [len(lines)]
    for anchor_index, (start, symbol) in enumerate(anchors):
        end = boundaries[anchor_index + 1]
        section = lines[start:end]
        if approx_tokens("\n".join(section)) <= 1400:
            chunks.append(
                Chunk(
                    content="\n".join(section).strip(),
                    start_line=start + 1,
                    end_line=end,
                    symbol=symbol,
                    kind="code",
                )
            )
        else:
            chunks.extend(chunk_by_lines(section, size=220, overlap=40, kind="code", symbol=symbol))
    return [chunk for chunk in chunks if chunk.content]


def chunk_text(path: Path, text: str, kind: str) -> list[Chunk]:
    if kind == "docs":
        return chunk_markdown(text)
    if kind == "code":
        return chunk_code(text)
    if kind == "log":
        return chunk_by_lines(text.splitlines(), size=350, overlap=50, kind="log")
    if kind == "config":
        return chunk_by_lines(text.splitlines(), size=260, overlap=40, kind="config")
    return chunk_by_lines(text.splitlines(), size=200, overlap=30, kind="text")


def read_text_file(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        try:
            return path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return None
    except OSError:
        return None


def remove_file_chunks(conn: sqlite3.Connection, client: QdrantClient, config: dict, repo: str, rel_path: str) -> None:
    rows = conn.execute(
        "SELECT chunk_id FROM chunks WHERE repo = ? AND path = ?",
        (repo, rel_path),
    ).fetchall()
    chunk_ids = [row["chunk_id"] for row in rows]
    if chunk_ids:
        client.delete(
            collection_name=config["qdrant_collection"],
            points_selector=models.PointIdsList(points=chunk_ids),
            wait=True,
        )
    conn.execute("DELETE FROM chunks WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM chunks_fts WHERE repo = ? AND path = ?", (repo, rel_path))


def index_repo(conn: sqlite3.Connection, client: QdrantClient, config: dict, root: Path, changed_only: bool) -> tuple[int, int]:
    ensure_collection(client, config)
    root, repo = repo_identity(root)
    existing = {
        row["path"]: row["file_hash"]
        for row in conn.execute(
            "SELECT path, file_hash FROM chunks WHERE repo = ? GROUP BY path, file_hash", (repo,)
        ).fetchall()
    }

    discovered: dict[str, str] = {}
    changed_files = 0
    total_chunks = 0

    for file_path in iter_text_files(root):
        rel_path = file_path.relative_to(root).as_posix()
        content = read_text_file(file_path)
        if not content or not content.strip():
            continue
        file_hash = hash_file(file_path)
        discovered[rel_path] = file_hash
        if changed_only and existing.get(rel_path) == file_hash:
            continue

        kind, language = detect_kind(file_path)
        chunks = chunk_text(file_path, content, kind)
        if not chunks:
            continue

        remove_file_chunks(conn, client, config, repo, rel_path)

        texts = [chunk.content for chunk in chunks]
        vectors = list(get_embedder(config).embed(texts))
        modified_at = file_path.stat().st_mtime
        points = []

        for index, (chunk, vector) in enumerate(zip(chunks, vectors)):
            chunk_key = f"{repo}:{rel_path}:{file_hash}:{index}:{chunk.start_line}:{chunk.end_line}"
            chunk_id = str(uuid.uuid5(uuid.NAMESPACE_URL, chunk_key))
            payload = {
                "repo": repo,
                "path": rel_path,
                "language": language,
                "kind": chunk.kind,
                "symbol": chunk.symbol,
                "modified_at": modified_at,
                "chunk_index": index,
                "start_line": chunk.start_line,
                "end_line": chunk.end_line,
            }
            points.append(models.PointStruct(id=chunk_id, vector=vector.tolist(), payload=payload))
            conn.execute(
                """
                INSERT INTO chunks (
                    chunk_id, repo, root, path, language, kind, symbol, modified_at,
                    file_hash, chunk_index, start_line, end_line, content
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    chunk_id,
                    repo,
                    str(root),
                    rel_path,
                    language,
                    chunk.kind,
                    chunk.symbol,
                    modified_at,
                    file_hash,
                    index,
                    chunk.start_line,
                    chunk.end_line,
                    chunk.content,
                ),
            )
            conn.execute(
                "INSERT INTO chunks_fts (chunk_id, repo, path, symbol, content) VALUES (?, ?, ?, ?, ?)",
                (chunk_id, repo, rel_path, chunk.symbol, chunk.content),
            )

        for batch in batched(points, 64):
            client.upsert(collection_name=config["qdrant_collection"], points=list(batch), wait=True)

        changed_files += 1
        total_chunks += len(chunks)

    removed_paths = set(existing) - set(discovered)
    for rel_path in removed_paths:
        remove_file_chunks(conn, client, config, repo, rel_path)

    conn.execute(
        "INSERT INTO indexed_repos (repo, root, last_indexed) VALUES (?, ?, ?) "
        "ON CONFLICT(repo) DO UPDATE SET root=excluded.root, last_indexed=excluded.last_indexed",
        (repo, str(root), time.time()),
    )
    conn.commit()
    return changed_files, total_chunks


def query_terms(query: str) -> list[str]:
    return [token.lower() for token in re.findall(r"[A-Za-z0-9_./:-]+", query) if token.lower() not in STOPWORDS]


def rewrite_queries(query: str) -> list[str]:
    terms = query_terms(query)
    rewrites = [query.strip()]
    if terms:
        rewrites.append(" ".join(dict.fromkeys(terms)))
        split_terms: list[str] = []
        for term in terms:
            split_terms.extend(split_symbol_tokens(term))
        if split_terms:
            rewrites.append(" ".join(dict.fromkeys(split_terms)))
    return [rewrite for rewrite in dict.fromkeys(rewrites) if rewrite]


def qdrant_filter(repo: str | None) -> models.Filter | None:
    if not repo:
        return None
    return models.Filter(
        must=[models.FieldCondition(key="repo", match=models.MatchValue(value=repo))]
    )


def semantic_hits(client: QdrantClient, config: dict, rewrites: list[str], repo: str | None) -> list[str]:
    hits: list[str] = []
    embedder = get_embedder(config)
    for rewrite in rewrites[:3]:
        vector = list(embedder.embed([rewrite]))[0].tolist()
        response = client.query_points(
            collection_name=config["qdrant_collection"],
            query=vector,
            query_filter=qdrant_filter(repo),
            limit=10,
            with_payload=True,
        )
        hits.extend(str(result.id) for result in response.points)
    return hits


def keyword_hits(conn: sqlite3.Connection, rewrites: list[str], repo: str | None) -> list[str]:
    hits: list[str] = []
    for rewrite in rewrites[:3]:
        tokens = query_terms(rewrite)
        if not tokens:
            continue
        match = " OR ".join(tokens[:12])
        sql = (
            "SELECT chunk_id FROM chunks_fts WHERE chunks_fts MATCH ?"
            + (" AND repo = ?" if repo else "")
            + " LIMIT 10"
        )
        params = [match] + ([repo] if repo else [])
        hits.extend(row["chunk_id"] for row in conn.execute(sql, params).fetchall())
    return hits


def recent_hits(conn: sqlite3.Connection, query: str, repo: str | None) -> list[str]:
    terms = query_terms(query)[:6]
    if not terms:
        return []
    like_clauses = []
    params: list[str] = []
    for term in terms:
        like_clauses.append("(path LIKE ? OR symbol LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%"])
    sql = "SELECT chunk_id FROM chunks WHERE " + " OR ".join(like_clauses)
    if repo:
        sql += " AND repo = ?"
        params.append(repo)
    sql += " ORDER BY modified_at DESC LIMIT 10"
    return [row["chunk_id"] for row in conn.execute(sql, params).fetchall()]


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


def rerank_chunks(query: str, rows: Sequence[sqlite3.Row], base_scores: dict[str, float]) -> list[sqlite3.Row]:
    query_terms_set = set(query_terms(query))
    scored = []
    for row in rows:
        content_terms = set(query_terms(row["content"])) | set(query_terms(row["path"])) | set(
            query_terms(row["symbol"] or "")
        )
        overlap = len(query_terms_set & content_terms)
        path_bonus = 2 if any(term in row["path"].lower() for term in query_terms_set) else 0
        symbol_bonus = 2 if row["symbol"] and any(term in row["symbol"].lower() for term in query_terms_set) else 0
        final_score = base_scores.get(row["chunk_id"], 0.0) + (overlap * 0.03) + (path_bonus * 0.02) + (
            symbol_bonus * 0.02
        )
        scored.append((final_score, row))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [row for _score, row in scored[:15]]


def gather_context(rows: Sequence[sqlite3.Row], budget_tokens: int) -> tuple[str, list[str]]:
    chunks = []
    seen_files: list[str] = []
    used = 0
    for row in rows:
        block = (
            f"[{len(chunks)+1}] {row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}\n"
            f"kind={row['kind']} language={row['language']} symbol={row['symbol'] or '-'}\n"
            f"{row['content']}"
        )
        block_tokens = approx_tokens(block)
        if used + block_tokens > budget_tokens:
            break
        chunks.append(block)
        used += block_tokens
        seen_files.append(f"{row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}")
    return "\n\n".join(chunks), seen_files


def ask_llm(config: dict, question: str, context: str) -> str:
    system_prompt = (
        "You are a repo-aware local coding assistant. Use the supplied context first, stay concrete, "
        "and cite file paths with line ranges in your answer when possible."
    )
    payload = json.dumps(
        {
            "model": config["answer_model"],
            "messages": [
                {"role": "system", "content": system_prompt},
                {
                    "role": "user",
                    "content": f"Question:\n{question}\n\nContext:\n{context}\n\nReturn a concise answer and cite files.",
                },
            ],
            "temperature": 0.1,
            "stream": False,
            "max_tokens": config["answer_max_tokens"],
        }
    ).encode()
    request = urllib.request.Request(
        config["answer_url"],
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=240) as response:
        body = json.load(response)
    return body.get("choices", [{}])[0].get("message", {}).get("content", "").strip()


def retrieve(conn: sqlite3.Connection, client: QdrantClient, config: dict, query: str, repo: str | None):
    rewrites = rewrite_queries(query)
    semantic = semantic_hits(client, config, rewrites, repo)
    keyword = keyword_hits(conn, rewrites, repo)
    recent = recent_hits(conn, query, repo)
    scores = reciprocal_rank_fusion(semantic, keyword, recent)
    ranked_ids = [chunk_id for chunk_id, _ in sorted(scores.items(), key=lambda item: item[1], reverse=True)]
    rows = load_chunks(conn, ranked_ids[:30])
    return rerank_chunks(query, rows, scores)


def cmd_index(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    root = Path(args.path).expanduser().resolve()
    changed_files, total_chunks = index_repo(conn, client, config, root, changed_only=False)
    console.print(f"[green]Indexed[/green] {changed_files} files and {total_chunks} chunks from {root}")
    return 0


def cmd_reindex(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    repos = conn.execute("SELECT root FROM indexed_repos ORDER BY repo").fetchall()
    if not repos:
        console.print("[yellow]No repos indexed yet.[/yellow]")
        return 0
    total_files = 0
    total_chunks = 0
    for row in repos:
        changed_files, chunks = index_repo(conn, client, config, Path(row["root"]), changed_only=True)
        total_files += changed_files
        total_chunks += chunks
    console.print(f"[green]Reindexed[/green] {total_files} changed files and {total_chunks} chunks")
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    config = load_config()
    conn = connect_db()
    client = get_qdrant(config)
    repo = infer_repo_filter(conn, args.repo)
    rows = retrieve(conn, client, config, args.query, repo)
    table = Table(title="RAG search results")
    table.add_column("#", justify="right")
    table.add_column("file")
    table.add_column("kind")
    table.add_column("symbol")
    table.add_column("preview")
    for index, row in enumerate(rows[:10], start=1):
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
    rows = retrieve(conn, client, config, args.query, repo)
    if not rows:
        console.print("[yellow]No indexed context matched that query.[/yellow]")
        return 1
    context, files = gather_context(rows, config["retrieval_context_tokens"])
    answer = ask_llm(config, args.query, context)
    console.print("[bold]Answer:[/bold]")
    console.print(answer or "[red]No answer returned.[/red]")
    console.print("\n[bold]Relevant files:[/bold]")
    for item in files:
        console.print(f"- {item}")
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
        health = client.get_collections()
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

    try:
        models_url = config["answer_url"].replace("/chat/completions", "/models")
        with urllib.request.urlopen(
            urllib.request.Request(
                models_url,
                headers={"Content-Type": "application/json"},
            ),
            timeout=5,
        ):
            pass
        table.add_row("answer model", "ok", config["answer_model"])
    except Exception as exc:  # pragma: no cover
        table.add_row("answer model", "fail", str(exc))

    table.add_row("embedding model", "ok", config["embedding_model"])
    console.print(table)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="rag")
    subparsers = parser.add_subparsers(dest="command", required=True)

    index_parser = subparsers.add_parser("index", help="Index a repo or folder")
    index_parser.add_argument("path")
    index_parser.set_defaults(func=cmd_index)

    ask_parser = subparsers.add_parser("ask", help="Ask a question against the local index")
    ask_parser.add_argument("query")
    ask_parser.add_argument("--repo", help="Filter to a repo name")
    ask_parser.set_defaults(func=cmd_ask)

    search_parser = subparsers.add_parser("search", help="Search indexed chunks")
    search_parser.add_argument("query")
    search_parser.add_argument("--repo", help="Filter to a repo name")
    search_parser.set_defaults(func=cmd_search)

    reindex_parser = subparsers.add_parser("reindex", help="Reindex only changed files")
    reindex_parser.add_argument("--changed", action="store_true", default=True)
    reindex_parser.set_defaults(func=cmd_reindex)

    doctor_parser = subparsers.add_parser("doctor", help="Check local RAG health")
    doctor_parser.set_defaults(func=cmd_doctor)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
