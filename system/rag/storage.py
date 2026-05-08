from __future__ import annotations

import sqlite3
import subprocess
from pathlib import Path

from qdrant_client import QdrantClient, models

from .runtime import CHUNKER_NAME, DB_PATH, INDEX_SCHEMA, RAG_HOME
from .settings import DEFAULT_CONFIG

try:
    from fastembed import TextEmbedding
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "fastembed is not installed in the RAG venv. Run setup/install-local-rag-stack.sh first."
    ) from exc


def ensure_column(conn: sqlite3.Connection, table: str, column: str, column_type: str) -> None:
    columns = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    if column not in columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {column_type}")


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
            index_schema TEXT,
            embedding_model TEXT,
            chunker TEXT,
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

        CREATE TABLE IF NOT EXISTS facts (
            fact_id TEXT PRIMARY KEY,
            repo TEXT NOT NULL,
            path TEXT NOT NULL,
            kind TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            line INTEGER NOT NULL,
            confidence REAL NOT NULL DEFAULT 1.0,
            source TEXT NOT NULL DEFAULT 'extractor',
            file_hash TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_facts_repo_kind_key ON facts(repo, kind, key);
        CREATE INDEX IF NOT EXISTS idx_facts_repo_path ON facts(repo, path);
        CREATE INDEX IF NOT EXISTS idx_facts_value ON facts(value);

        CREATE TABLE IF NOT EXISTS file_summaries (
            repo TEXT NOT NULL,
            path TEXT NOT NULL,
            file_hash TEXT NOT NULL,
            language TEXT NOT NULL,
            kind TEXT NOT NULL,
            summary TEXT NOT NULL,
            symbols TEXT,
            facts_count INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL,
            PRIMARY KEY(repo, path)
        );

        CREATE TABLE IF NOT EXISTS repo_memory (
            repo TEXT PRIMARY KEY,
            root TEXT NOT NULL,
            summary TEXT NOT NULL,
            architecture TEXT,
            important_paths TEXT,
            conventions TEXT,
            updated_at REAL NOT NULL,
            index_schema TEXT NOT NULL,
            source_chunk_count INTEGER NOT NULL
        );
        """
    )
    ensure_column(conn, "chunks", "index_schema", "TEXT")
    ensure_column(conn, "chunks", "embedding_model", "TEXT")
    ensure_column(conn, "chunks", "chunker", "TEXT")
    conn.execute("UPDATE chunks SET index_schema = ? WHERE index_schema IS NULL", (INDEX_SCHEMA,))
    conn.execute(
        "UPDATE chunks SET embedding_model = ? WHERE embedding_model IS NULL",
        (DEFAULT_CONFIG["embedding_model"],),
    )
    conn.execute("UPDATE chunks SET chunker = ? WHERE chunker IS NULL", (CHUNKER_NAME,))
    conn.commit()


def connect_db(db_path: Path = DB_PATH) -> sqlite3.Connection:
    RAG_HOME.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 5000")
    ensure_db(conn)
    return conn


def get_qdrant(config: dict) -> QdrantClient:
    return QdrantClient(url=config["qdrant_url"])


_embedder: TextEmbedding | None = None
_embedder_model: str | None = None


def get_embedder(config: dict) -> TextEmbedding:
    global _embedder, _embedder_model
    model_name = config["embedding_model"]
    if _embedder is None or _embedder_model != model_name:
        _embedder = TextEmbedding(model_name=model_name)
        _embedder_model = model_name
    return _embedder


def collection_vector_size(collection_info) -> int:
    vectors = collection_info.config.params.vectors
    if hasattr(vectors, "size"):
        return int(vectors.size)
    if isinstance(vectors, dict):
        first = next(iter(vectors.values()))
        return int(first.size)
    raise SystemExit("Unable to determine Qdrant vector size from collection config")


def ensure_collection(client: QdrantClient, config: dict) -> None:
    collection = config["qdrant_collection"]
    embedder = get_embedder(config)
    sample = list(embedder.embed(["bootstrap vector size probe"]))[0]
    if client.collection_exists(collection):
        info = client.get_collection(collection)
        actual_size = collection_vector_size(info)
        expected_size = len(sample)
        if actual_size != expected_size:
            raise SystemExit(
                f"Qdrant collection vector size mismatch: expected {expected_size}, got {actual_size}. "
                "Run: rag clean --all && rag index <path>"
            )
        return
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


def resolve_repo_name(conn: sqlite3.Connection, explicit_repo: str | None) -> str | None:
    if explicit_repo:
        return explicit_repo
    inferred = infer_repo_filter(conn, None)
    if inferred:
        return inferred
    rows = conn.execute("SELECT repo FROM indexed_repos ORDER BY repo").fetchall()
    if len(rows) == 1:
        return rows[0]["repo"]
    return None
