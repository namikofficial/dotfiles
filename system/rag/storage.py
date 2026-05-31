from __future__ import annotations

import json
import sqlite3
import subprocess
import time
from pathlib import Path

from qdrant_client import QdrantClient, models

from .runtime import CHUNKER_NAME, DB_PATH, INDEX_SCHEMA, RAG_HOME
from .settings import DEFAULT_CONFIG
from .types import SupportsQdrantCollectionAdmin

try:
    from fastembed import TextEmbedding
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "fastembed is not installed in the RAG venv. Run setup/install-local-rag-stack.sh first."
    ) from exc


DEFAULT_TOOL_TAXONOMY: dict[str, list[tuple[str, list[str], str]]] = {
    "node_backend": [
        ("node", ["nodejs", "javascript", "typescript"], "Node.js runtime and package scripts"),
        ("pnpm", ["package-manager"], "Preferred JS package manager"),
        ("nest", ["nestjs"], "NestJS backend framework"),
        ("mikro-orm", ["mikroorm"], "MikroORM data layer"),
        ("psql", ["postgres", "postgresql"], "Postgres CLI access"),
    ],
    "rust_systems": [
        ("cargo", ["rust", "cargo-test"], "Rust package and build tool"),
        ("rustc", ["compiler"], "Rust compiler"),
        ("dkms", ["kernel-module"], "Kernel module build helper"),
        ("modprobe", ["kernel"], "Kernel module loader"),
        ("dmesg", ["kernel-log"], "Kernel/system log viewer"),
    ],
    "linux_desktop": [
        ("hyprctl", ["hyprland"], "Hyprland runtime control"),
        ("systemctl", ["systemd"], "Service manager"),
        ("journalctl", ["logs"], "System logs"),
        ("pactl", ["audio", "pipewire"], "PulseAudio/PipeWire control"),
    ],
    "observability": [
        ("grafana", ["dashboards"], "Grafana dashboards"),
        ("prometheus", ["metrics"], "Prometheus metrics store"),
        ("loki", ["logs"], "Loki log indexing"),
        ("promtool", ["prometheus-cli"], "Prometheus rule checker"),
    ],
}


def ensure_column(conn: sqlite3.Connection, table: str, column: str, column_type: str) -> None:
    columns = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    if column not in columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {column_type}")


def apply_migrations(conn: sqlite3.Connection) -> None:
    migrations_dir = Path(__file__).resolve().parent / "migrations"
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS _schema_migrations (
            id TEXT PRIMARY KEY,
            applied_at REAL NOT NULL
        )
        """
    )
    if not migrations_dir.is_dir():
        conn.commit()
        return
    applied = {row[0] for row in conn.execute("SELECT id FROM _schema_migrations").fetchall()}
    for path in sorted(migrations_dir.glob("*.sql")):
        migration_id = path.name
        if migration_id in applied:
            continue
        conn.executescript(path.read_text())
        conn.execute(
            "INSERT OR IGNORE INTO _schema_migrations (id, applied_at) VALUES (?, ?)",
            (migration_id, time.time()),
        )
    conn.commit()



def seed_tool_taxonomy(conn: sqlite3.Connection) -> None:
    now = time.time()
    for domain, tools in DEFAULT_TOOL_TAXONOMY.items():
        for tool, aliases, description in tools:
            conn.execute(
                """
                INSERT OR IGNORE INTO tool_taxonomy (
                    domain, tool, aliases, description, source, created_at, updated_at
                ) VALUES (?, ?, ?, ?, 'seed', ?, ?)
                """,
                (domain, tool, json.dumps(aliases), description, now, now),
            )


def seed_profiles(conn: sqlite3.Connection) -> None:
    from .profiles import BUILTIN_PROFILES

    now = time.time()
    for profile_id, profile in BUILTIN_PROFILES.items():
        conn.execute(
            """
            INSERT OR IGNORE INTO profiles (id, yaml_source, is_user_override, created_at)
            VALUES (?, ?, 0, ?)
            """,
            (profile_id, json.dumps(profile, sort_keys=True), now),
        )



def ensure_db(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS indexed_repos (
            repo TEXT PRIMARY KEY,
            root TEXT NOT NULL,
            last_indexed REAL NOT NULL,
            last_indexed_branch TEXT,
            last_indexed_commit TEXT
        );

        CREATE TABLE IF NOT EXISTS chunks (
            chunk_id TEXT PRIMARY KEY,
            repo TEXT NOT NULL,
            root TEXT NOT NULL,
            path TEXT NOT NULL,
            package TEXT,
            package_root TEXT,
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
            package TEXT,
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
            package TEXT,
            file_hash TEXT NOT NULL,
            language TEXT NOT NULL,
            kind TEXT NOT NULL,
            summary TEXT NOT NULL,
            symbols TEXT,
            facts_count INTEGER NOT NULL DEFAULT 0,
            updated_at REAL NOT NULL,
            PRIMARY KEY(repo, path)
        );

        CREATE TABLE IF NOT EXISTS symbols (
            symbol_id TEXT PRIMARY KEY,
            repo TEXT NOT NULL,
            path TEXT NOT NULL,
            package TEXT,
            package_root TEXT,
            language TEXT NOT NULL,
            kind TEXT NOT NULL,
            name TEXT NOT NULL,
            qualified_name TEXT NOT NULL,
            signature TEXT,
            docstring TEXT,
            visibility TEXT,
            parent_symbol TEXT,
            start_line INTEGER NOT NULL,
            end_line INTEGER NOT NULL,
            exported INTEGER NOT NULL DEFAULT 0,
            parser TEXT,
            file_hash TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_symbols_repo_path ON symbols(repo, path, start_line);
        CREATE INDEX IF NOT EXISTS idx_symbols_repo_name ON symbols(repo, name, kind);

        CREATE VIRTUAL TABLE IF NOT EXISTS symbols_fts USING fts5(
            symbol_id UNINDEXED,
            repo,
            path,
            package,
            name,
            qualified_name,
            kind,
            signature,
            docstring
        );

        CREATE TABLE IF NOT EXISTS semantic_lines (
            line_id TEXT PRIMARY KEY,
            chunk_id TEXT NOT NULL,
            repo TEXT NOT NULL,
            path TEXT NOT NULL,
            package TEXT,
            language TEXT NOT NULL,
            line_no INTEGER NOT NULL,
            symbol TEXT,
            content TEXT NOT NULL,
            file_hash TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_semantic_lines_repo_path ON semantic_lines(repo, path, line_no);

        CREATE VIRTUAL TABLE IF NOT EXISTS semantic_lines_fts USING fts5(
            line_id UNINDEXED,
            chunk_id UNINDEXED,
            repo,
            path,
            package,
            symbol,
            content
        );

        CREATE TABLE IF NOT EXISTS file_dependencies (
            edge_id TEXT PRIMARY KEY,
            repo TEXT NOT NULL,
            source_path TEXT NOT NULL,
            package TEXT,
            package_root TEXT,
            dependency TEXT NOT NULL,
            dependency_kind TEXT NOT NULL,
            target_path TEXT,
            line INTEGER NOT NULL,
            is_export INTEGER NOT NULL DEFAULT 0,
            is_internal INTEGER NOT NULL DEFAULT 0,
            file_hash TEXT NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_file_dependencies_repo_source ON file_dependencies(repo, source_path);
        CREATE INDEX IF NOT EXISTS idx_file_dependencies_repo_target ON file_dependencies(repo, target_path);

        CREATE TABLE IF NOT EXISTS package_summaries (
            repo TEXT NOT NULL,
            package TEXT NOT NULL,
            package_root TEXT,
            summary TEXT NOT NULL,
            symbols TEXT,
            dependencies TEXT,
            file_count INTEGER NOT NULL DEFAULT 0,
            paths TEXT,
            updated_at REAL NOT NULL,
            PRIMARY KEY(repo, package)
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
            source_chunk_count INTEGER NOT NULL,
            summary_commit TEXT,
            changed_files_json TEXT NOT NULL DEFAULT '[]',
            changed_symbols_json TEXT NOT NULL DEFAULT '[]',
            freshness_score REAL NOT NULL DEFAULT 1.0
        );

        CREATE TABLE IF NOT EXISTS task_todos (
            todo_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            title TEXT NOT NULL,
            detail TEXT,
            status TEXT NOT NULL DEFAULT 'open',
            source_session_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_task_todos_repo_status ON task_todos(repo, status, updated_at);

        CREATE TABLE IF NOT EXISTS task_decisions (
            decision_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            title TEXT NOT NULL,
            detail TEXT NOT NULL,
            rationale TEXT,
            source_session_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_task_decisions_repo_updated ON task_decisions(repo, updated_at);

        CREATE TABLE IF NOT EXISTS command_memory (
            command_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            command TEXT NOT NULL,
            purpose TEXT,
            notes TEXT,
            source_session_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_command_memory_repo_updated ON command_memory(repo, updated_at);

        CREATE TABLE IF NOT EXISTS error_memory (
            error_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            error_text TEXT NOT NULL,
            fix_text TEXT,
            notes TEXT,
            normalized_error TEXT,
            fingerprint_hash TEXT,
            stack_symbols_json TEXT NOT NULL DEFAULT '[]',
            file_paths_json TEXT NOT NULL DEFAULT '[]',
            command TEXT,
            exit_code INTEGER,
            source_session_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_error_memory_repo_updated ON error_memory(repo, updated_at);
        CREATE INDEX IF NOT EXISTS idx_error_memory_repo_hash ON error_memory(repo, fingerprint_hash, updated_at);

        CREATE TABLE IF NOT EXISTS task_sessions (
            session_id TEXT PRIMARY KEY,
            repo TEXT,
            mode TEXT NOT NULL,
            query TEXT NOT NULL,
            route_reason TEXT NOT NULL,
            output_kind TEXT NOT NULL,
            output_text TEXT NOT NULL,
            relevant_files_json TEXT NOT NULL DEFAULT '[]',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_task_sessions_repo_created ON task_sessions(repo, created_at);

        CREATE TABLE IF NOT EXISTS developer_memory (
            memory_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            kind TEXT NOT NULL,
            subject TEXT NOT NULL,
            normalized_subject TEXT NOT NULL,
            value TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'active',
            source_session_id TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            last_used_at REAL
        );
        CREATE INDEX IF NOT EXISTS idx_developer_memory_scope ON developer_memory(repo, kind, status, updated_at);
        CREATE INDEX IF NOT EXISTS idx_developer_memory_subject ON developer_memory(kind, normalized_subject, repo);

        CREATE TABLE IF NOT EXISTS context_packs (
            pack_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            name TEXT NOT NULL,
            agent_target TEXT NOT NULL DEFAULT 'generic',
            source TEXT NOT NULL DEFAULT 'generated',
            content TEXT NOT NULL,
            metadata_json TEXT NOT NULL DEFAULT '{}',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(repo, name, agent_target)
        );
        CREATE INDEX IF NOT EXISTS idx_context_packs_repo_name ON context_packs(repo, name, updated_at);

        CREATE TABLE IF NOT EXISTS session_compactions (
            compaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL UNIQUE,
            repo TEXT,
            mode TEXT NOT NULL,
            summary TEXT NOT NULL,
            extracted_json TEXT NOT NULL DEFAULT '{}',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_session_compactions_repo_updated ON session_compactions(repo, updated_at);

        CREATE TABLE IF NOT EXISTS tool_taxonomy (
            taxonomy_id INTEGER PRIMARY KEY AUTOINCREMENT,
            domain TEXT NOT NULL,
            tool TEXT NOT NULL,
            aliases TEXT NOT NULL DEFAULT '[]',
            description TEXT,
            source TEXT NOT NULL DEFAULT 'seed',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            UNIQUE(domain, tool)
        );
        CREATE INDEX IF NOT EXISTS idx_tool_taxonomy_domain ON tool_taxonomy(domain, tool);

        CREATE TABLE IF NOT EXISTS git_context (
            repo TEXT NOT NULL,
            branch TEXT NOT NULL,
            head_commit TEXT,
            indexed_branch TEXT,
            indexed_commit TEXT,
            dirty INTEGER NOT NULL DEFAULT 0,
            status_short TEXT NOT NULL DEFAULT '',
            diff_text TEXT NOT NULL DEFAULT '',
            staged_diff_text TEXT NOT NULL DEFAULT '',
            recent_log_text TEXT NOT NULL DEFAULT '',
            changed_files_json TEXT NOT NULL DEFAULT '[]',
            captured_at REAL NOT NULL,
            PRIMARY KEY(repo, branch)
        );
        CREATE INDEX IF NOT EXISTS idx_git_context_repo_captured ON git_context(repo, captured_at);

        CREATE TABLE IF NOT EXISTS github_context (
            repo TEXT,
            ref_type TEXT NOT NULL,
            ref_number INTEGER NOT NULL,
            title TEXT NOT NULL,
            body TEXT NOT NULL DEFAULT '',
            changed_files_json TEXT NOT NULL DEFAULT '[]',
            comments_json TEXT NOT NULL DEFAULT '[]',
            review_comments_json TEXT NOT NULL DEFAULT '[]',
            ci_logs_text TEXT NOT NULL DEFAULT '',
            linked_issues_json TEXT NOT NULL DEFAULT '[]',
            source TEXT NOT NULL DEFAULT 'manual',
            updated_at REAL NOT NULL,
            PRIMARY KEY(repo, ref_type, ref_number)
        );
        CREATE INDEX IF NOT EXISTS idx_github_context_repo_updated ON github_context(repo, updated_at);

        CREATE TABLE IF NOT EXISTS test_failure_memory (
            failure_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            runner TEXT,
            command TEXT NOT NULL,
            output_text TEXT NOT NULL,
            normalized_error TEXT NOT NULL,
            fingerprint_hash TEXT NOT NULL,
            stack_symbols_json TEXT NOT NULL DEFAULT '[]',
            file_paths_json TEXT NOT NULL DEFAULT '[]',
            exit_code INTEGER,
            source TEXT NOT NULL DEFAULT 'local',
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_test_failure_repo_updated ON test_failure_memory(repo, updated_at);
        CREATE INDEX IF NOT EXISTS idx_test_failure_repo_hash ON test_failure_memory(repo, fingerprint_hash, updated_at);

        CREATE TABLE IF NOT EXISTS eval_cases (
            case_id INTEGER PRIMARY KEY AUTOINCREMENT,
            repo TEXT,
            query TEXT NOT NULL,
            mode TEXT NOT NULL DEFAULT 'deep',
            expected_files_json TEXT NOT NULL DEFAULT '[]',
            notes TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_eval_cases_repo_updated ON eval_cases(repo, updated_at);
        """
    )
    apply_migrations(conn)
    ensure_column(conn, "indexed_repos", "last_indexed_branch", "TEXT")
    ensure_column(conn, "indexed_repos", "last_indexed_commit", "TEXT")
    ensure_column(conn, "chunks", "index_schema", "TEXT")
    ensure_column(conn, "chunks", "embedding_model", "TEXT")
    ensure_column(conn, "chunks", "chunker", "TEXT")
    ensure_column(conn, "chunks", "package", "TEXT")
    ensure_column(conn, "chunks", "package_root", "TEXT")
    ensure_column(conn, "facts", "package", "TEXT")
    ensure_column(conn, "file_summaries", "package", "TEXT")
    ensure_column(conn, "repo_memory", "summary_commit", "TEXT")
    ensure_column(conn, "repo_memory", "changed_files_json", "TEXT NOT NULL DEFAULT '[]'")
    ensure_column(conn, "repo_memory", "changed_symbols_json", "TEXT NOT NULL DEFAULT '[]'")
    ensure_column(conn, "repo_memory", "freshness_score", "REAL NOT NULL DEFAULT 1.0")
    ensure_column(conn, "error_memory", "normalized_error", "TEXT")
    ensure_column(conn, "error_memory", "fingerprint_hash", "TEXT")
    ensure_column(conn, "error_memory", "stack_symbols_json", "TEXT NOT NULL DEFAULT '[]'")
    ensure_column(conn, "error_memory", "file_paths_json", "TEXT NOT NULL DEFAULT '[]'")
    ensure_column(conn, "error_memory", "command", "TEXT")
    ensure_column(conn, "error_memory", "exit_code", "INTEGER")
    ensure_column(conn, "eval_cases", "expected_symbols_json", "TEXT NOT NULL DEFAULT '[]'")
    conn.execute("UPDATE chunks SET index_schema = ? WHERE index_schema IS NULL", (INDEX_SCHEMA,))
    conn.execute(
        "UPDATE chunks SET embedding_model = ? WHERE embedding_model IS NULL",
        (DEFAULT_CONFIG["embedding_model"],),
    )
    conn.execute("UPDATE chunks SET chunker = ? WHERE chunker IS NULL", (CHUNKER_NAME,))
    conn.execute(
        "UPDATE error_memory SET normalized_error = TRIM(LOWER(error_text)) WHERE normalized_error IS NULL"
    )
    conn.execute(
        "UPDATE error_memory SET fingerprint_hash = '' WHERE fingerprint_hash IS NULL"
    )
    seed_tool_taxonomy(conn)
    seed_profiles(conn)
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



def ensure_collection(client: SupportsQdrantCollectionAdmin, config: dict) -> None:
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



def git_branch_for(path: Path) -> str | None:
    try:
        output = subprocess.check_output(
            ["git", "-C", str(path), "branch", "--show-current"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        return None
    return output or None



def git_head_commit_for(path: Path) -> str | None:
    try:
        output = subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "HEAD"],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except subprocess.CalledProcessError:
        return None
    return output or None



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
