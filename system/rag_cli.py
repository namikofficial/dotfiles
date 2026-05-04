#!/usr/bin/env python3
# pyright: reportMissingImports=false
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
from datetime import datetime
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
    "key_aliases": {
        "mod": "SUPER",
        "mainmod": "SUPER",
        "win": "SUPER",
        "windows": "SUPER",
        "cmd": "SUPER",
        "ctrl": "CTRL",
        "control": "CTRL",
    },
    "retrieval": {
        "max_chunks_per_file": 3,
        "max_fact_files": 8,
        "max_summary_files": 8,
    },
    "context_budget": {
        "total_tokens": 12000,
        "memory_tokens": 1800,
        "facts_tokens": 1800,
        "file_summary_tokens": 2200,
        "chunk_tokens": 6000,
        "reserved_answer_tokens": 2200,
    },
    "indexing": {
        "profile": "balanced",
    },
    "index_profiles": {
        "fast": {
            "facts": True,
            "file_summaries": False,
            "repo_memory": False,
        },
        "balanced": {
            "facts": True,
            "file_summaries": True,
            "repo_memory": False,
        },
        "deep": {
            "facts": True,
            "file_summaries": True,
            "repo_memory": True,
        },
    },
    "reranker": {
        "enabled": True,
        "mode": "heuristic",
        "top_k_input": 30,
        "top_k_output": 12,
        "content_weight": 0.03,
        "path_weight": 0.02,
        "symbol_weight": 0.02,
    },
}
INDEX_SCHEMA = "rag-v4"
CHUNKER_NAME = "semantic-lines-v4"

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
    ".mts": "typescript",
    ".cts": "typescript",
    ".js": "javascript",
    ".jsx": "javascript",
    ".mjs": "javascript",
    ".cjs": "javascript",
    ".html": "html",
    ".htm": "html",
    ".css": "css",
    ".scss": "css",
    ".sass": "css",
    ".less": "css",
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
    ".kts": "kotlin",
    ".c": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".h": "c",
    ".hpp": "cpp",
    ".proto": "proto",
    ".sql": "sql",
    ".zig": "zig",
}

MARKDOWN_EXTENSIONS = {".md", ".mdx", ".rst", ".txt"}
CONFIG_EXTENSIONS = {".json", ".yaml", ".yml", ".toml", ".ini", ".conf", ".env", ".properties", ".xml", ".ui", ".glade"}
LOG_EXTENSIONS = {".log", ".jsonl"}
SPECIAL_CODE_FILENAMES = {
    "dockerfile": "dockerfile",
    "justfile": "just",
    "makefile": "make",
    "jenkinsfile": "groovy",
}
HYPRLAND_KEYWORDS = (
    "bind",
    "binde",
    "bindm",
    "bindel",
    "bindl",
    "bindr",
    "exec",
    "exec-once",
    "windowrule",
    "windowrulev2",
    "env",
)

SYMBOL_PATTERNS = [
    re.compile(r"^\s*(?:export\s+)?(?:default\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:export\s+)?(?:default\s+)?interface\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(
        r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?:async\s*)?(?:<[^>]+>\s*)?(?:\([^)]*\)|[A-Za-z_][A-Za-z0-9_]*)\s*=>"
    ),
    re.compile(r"^\s*(?:export\s+)?(?:type|enum|namespace)\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?(?:async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*fn\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:pub(?:\([^)]+\))?\s+)?(?:trait|enum|struct|mod)\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*impl(?:<[^>]+>)?\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:data\s+|sealed\s+|enum\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*object\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(r"^\s*(?:override\s+|suspend\s+|inline\s+)*fun\s+([A-Za-z_][A-Za-z0-9_]*)"),
    re.compile(
        r"^\s*create\s+(?:or\s+replace\s+)?(?:table|view|function|procedure|trigger|index)\s+([A-Za-z_][A-Za-z0-9_.]*)",
        re.IGNORECASE,
    ),
]
SHELL_FUNCTION_PATTERN = re.compile(
    r"^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_.-]*)\s*(?:\(\s*\))?\s*\{"
)
SHELL_ALIAS_PATTERN = re.compile(r"^\s*alias\s+([A-Za-z_][A-Za-z0-9_.-]*)=")
SHELL_EXPORT_PATTERN = re.compile(r"^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=")
SHELL_CASE_BRANCH_PATTERN = re.compile(r"^\s*([A-Za-z0-9_.-]+|\*)\)\s*$")
SHELL_TOOL_PATTERNS = [
    re.compile(r"^\s*(?:need_cmd|require_cmd|ensure_cmd|has_cmd)\s+['\"]?([A-Za-z0-9_.+-]+)"),
    re.compile(r"\bcommand -v\s+['\"]?([A-Za-z0-9_.+-]+)"),
]
TOML_SECTION_PATTERN = re.compile(r"^\s*\[([^\]]+)\]\s*$")
YAML_SECTION_PATTERN = re.compile(r"^[A-Za-z0-9_-]+:\s*(?:#.*)?$")
CSS_SELECTOR_PATTERN = re.compile(r"^\s*([^@/{][^{]+)\{\s*$")
CSS_AT_RULE_PATTERN = re.compile(r"^\s*(@[A-Za-z0-9_-]+[^{]*)\{\s*$")
HTML_SECTION_PATTERN = re.compile(r"^\s*<(main|section|article|nav|header|footer|aside|form|dialog|template)\b([^>]*)>")
XML_OBJECT_PATTERN = re.compile(r"^\s*<(object|template)\b([^>]*)>")

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


@dataclass
class Fact:
    kind: str
    key: str
    value: str
    line: int
    confidence: float = 1.0
    source: str = "extractor"


class IndexInterrupted(Exception):
    def __init__(self, changed_files: int, total_chunks: int):
        super().__init__("index interrupted")
        self.changed_files = changed_files
        self.total_chunks = total_chunks


def load_config() -> dict:
    config = json.loads(json.dumps(DEFAULT_CONFIG))
    raw_config: dict = {}
    if CONFIG_PATH.exists():
        raw_config = json.loads(CONFIG_PATH.read_text())
        config = merge_nested_dicts(config, raw_config)
    if "context_budget" not in raw_config and "retrieval_context_tokens" in raw_config:
        total_tokens = int(raw_config["retrieval_context_tokens"])
        config["context_budget"]["total_tokens"] = total_tokens
        config["context_budget"]["chunk_tokens"] = max(
            2000,
            total_tokens
            - config["context_budget"]["memory_tokens"]
            - config["context_budget"]["facts_tokens"]
            - config["context_budget"]["file_summary_tokens"],
        )
    if "context_budget" in raw_config and "total_tokens" not in raw_config["context_budget"]:
        config["context_budget"]["total_tokens"] = raw_config.get(
            "retrieval_context_tokens", config["context_budget"]["total_tokens"]
        )
    config["context_budget"]["reserved_answer_tokens"] = raw_config.get(
        "answer_max_tokens",
        config["context_budget"]["reserved_answer_tokens"],
    )
    return config


def merge_nested_dicts(base: dict, override: dict) -> dict:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = merge_nested_dicts(merged[key], value)
        else:
            merged[key] = value
    return merged


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


def ensure_column(conn: sqlite3.Connection, table: str, column: str, column_type: str) -> None:
    columns = {row[1] for row in conn.execute(f"PRAGMA table_info({table})")}
    if column not in columns:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {column_type}")


def connect_db() -> sqlite3.Connection:
    RAG_HOME.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout = 5000")
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


def collection_vector_size(collection_info) -> int:
    vectors = collection_info.config.params.vectors
    if hasattr(vectors, "size"):
        return int(vectors.size)
    if isinstance(vectors, dict):
        first = next(iter(vectors.values()))
        return int(first.size)
    raise SystemExit("Unable to determine Qdrant vector size from collection config")



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
    special_name = path.name.lower()
    if special_name in SPECIAL_CODE_FILENAMES:
        return "code", SPECIAL_CODE_FILENAMES[special_name]
    if special_name == "hyprland.conf":
        return "config", "hyprland"
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


def attr_value(fragment: str, attr: str) -> str:
    match = re.search(rf'{attr}="([^"]+)"', fragment)
    return match.group(1).strip() if match else ""


def normalize_hyprland_mods(mods: str) -> str:
    normalized = []
    for part in re.split(r"[+ ]+", mods):
        part = part.strip()
        if not part:
            continue
        normalized.append(part if part.startswith("$") else part.upper())
    return "+".join(normalized)


def hyprland_symbol(stripped: str) -> str:
    key, _, value = stripped.partition("=")
    key = key.strip()
    value = value.strip()
    if key.startswith("bind"):
        parts = [part.strip() for part in value.split(",")]
        if len(parts) >= 3:
            mods = normalize_hyprland_mods(parts[0])
            key_name = parts[1].strip().upper()
            action = parts[2].strip()
            return f"{key}:{mods}+{key_name}:{action}"
    if key in {"exec", "exec-once"}:
        command = value.split()[0] if value else "-"
        return f"{key}:{command}"
    if key.startswith("windowrule"):
        return f"{key}:{value[:80]}"
    if key == "env":
        env_key, _, _env_value = value.partition(",")
        return f"env:{env_key.strip()}"
    return key


def html_symbol(line: str) -> str:
    match = HTML_SECTION_PATTERN.search(line)
    if not match:
        return ""
    tag = match.group(1)
    attrs = match.group(2)
    element_id = attr_value(attrs, "id")
    class_name = attr_value(attrs, "class").split()[0] if attr_value(attrs, "class") else ""
    if element_id:
        return f"{tag}#{element_id}"
    if class_name:
        return f"{tag}.{class_name}"
    return tag


def xml_ui_symbol(line: str) -> str:
    match = XML_OBJECT_PATTERN.search(line)
    if not match:
        return ""
    tag = match.group(1)
    attrs = match.group(2)
    class_name = attr_value(attrs, "class")
    element_id = attr_value(attrs, "id")
    if class_name and element_id:
        return f"{tag}:{class_name}#{element_id}"
    if class_name:
        return f"{tag}:{class_name}"
    if element_id:
        return f"{tag}:#{element_id}"
    return tag


def normalize_fact_value(value: str) -> str:
    return value.strip().strip('"').strip("'")


def extract_shell_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if match := SHELL_ALIAS_PATTERN.search(line):
            _, _, value = stripped.partition("=")
            facts.append(Fact("alias", match.group(1), normalize_fact_value(value), line_no))
            continue
        if match := SHELL_EXPORT_PATTERN.search(line):
            _, _, value = stripped.partition("=")
            facts.append(Fact("env", match.group(1), normalize_fact_value(value), line_no))
            continue
        if match := SHELL_FUNCTION_PATTERN.search(line):
            facts.append(Fact("function", match.group(1), "defined", line_no))
        if match := SHELL_CASE_BRANCH_PATTERN.search(line):
            facts.append(Fact("case-branch", match.group(1), "case branch", line_no))
        for pattern in SHELL_TOOL_PATTERNS:
            if match := pattern.search(line):
                facts.append(Fact("tool", match.group(1), "required", line_no))
                break
    return facts


def extract_hyprland_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = [part.strip() for part in stripped.split("=", 1)]
        if key.startswith("bind"):
            parts = [part.strip() for part in value.split(",")]
            if len(parts) >= 4:
                mods = normalize_hyprland_mods(parts[0])
                key_name = parts[1].upper()
                action = ", ".join(parts[2:])
                facts.append(Fact("keybind", f"{mods}+{key_name}", action, line_no))
            continue
        if key in {"exec", "exec-once"}:
            command = value
            command_name = Path(command.split()[0]).name if command else "-"
            facts.append(Fact("startup" if key == "exec-once" else "exec", command_name, command, line_no))
            continue
        if key == "env":
            env_key, _, env_value = value.partition(",")
            facts.append(Fact("env", env_key.strip(), env_value.strip(), line_no))
            continue
        if key.startswith("windowrule"):
            facts.append(Fact("windowrule", value[:80], value, line_no))
    return facts


def extract_package_facts(text: str, manager: str) -> list[Fact]:
    facts: list[Fact] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        package = stripped.split("|", 1)[0].strip()
        facts.append(Fact("package", package, manager, line_no))
    return facts


def extract_toml_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    current_section = ""
    for line_no, line in enumerate(text.splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if match := TOML_SECTION_PATTERN.search(line):
            current_section = match.group(1).strip()
            facts.append(Fact("config-section", current_section, "section", line_no))
            continue
        if "=" in stripped:
            key, value = [part.strip() for part in stripped.split("=", 1)]
            full_key = f"{current_section}.{key}" if current_section else key
            facts.append(Fact("config-key", full_key, normalize_fact_value(value), line_no))
    return facts


def extract_yaml_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    current_section = ""
    for line_no, line in enumerate(text.splitlines(), start=1):
        if not line.strip() or line.strip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip(" "))
        stripped = line.strip()
        if indent == 0 and ":" in stripped:
            key, value = stripped.split(":", 1)
            current_section = key.strip()
            facts.append(Fact("config-section", current_section, "section", line_no))
            if value.strip():
                facts.append(Fact("config-key", current_section, normalize_fact_value(value), line_no))
        elif indent > 0 and ":" in stripped:
            key, value = stripped.split(":", 1)
            full_key = f"{current_section}.{key.strip()}" if current_section else key.strip()
            if value.strip():
                facts.append(Fact("config-key", full_key, normalize_fact_value(value), line_no))
    return facts


def extract_json_facts(path: Path, text: str) -> list[Fact]:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return []
    if not isinstance(parsed, dict):
        return []
    facts: list[Fact] = []
    for key, value in parsed.items():
        if isinstance(value, (str, int, float, bool)):
            facts.append(Fact("config-key", key, str(value), 1))
        elif isinstance(value, dict):
            facts.append(Fact("config-section", key, "object", 1))
            for nested_key, nested_value in list(value.items())[:12]:
                if isinstance(nested_value, (str, int, float, bool)):
                    facts.append(Fact("config-key", f"{key}.{nested_key}", str(nested_value), 1))
        elif isinstance(value, list) and value and all(isinstance(item, str) for item in value[:5]):
            facts.append(Fact("config-key", key, ", ".join(value[:5]), 1))
    return facts


def extract_sql_facts(text: str) -> list[Fact]:
    facts: list[Fact] = []
    pattern = re.compile(
        r"^\s*create\s+(?:or\s+replace\s+)?(?P<kind>table|view|function|procedure|trigger|index)\s+(?P<name>[A-Za-z_][A-Za-z0-9_.]*)",
        re.IGNORECASE,
    )
    for line_no, line in enumerate(text.splitlines(), start=1):
        if match := pattern.search(line):
            facts.append(Fact("sql-object", match.group("name"), match.group("kind").lower(), line_no))
    return facts


def extract_facts(path: Path, text: str, language: str, kind: str) -> list[Fact]:
    if language == "shell":
        return extract_shell_facts(text)
    if language == "hyprland":
        return extract_hyprland_facts(text)
    if path.name == "pacman-packages.txt":
        return extract_package_facts(text, manager="pacman")
    if path.name == "aur-packages.txt":
        return extract_package_facts(text, manager="aur")
    if path.suffix.lower() == ".toml":
        return extract_toml_facts(text)
    if path.suffix.lower() in {".yaml", ".yml"}:
        return extract_yaml_facts(text)
    if path.suffix.lower() == ".json":
        return extract_json_facts(path, text)
    if language == "sql":
        return extract_sql_facts(text)
    return []


def summarize_file(
    rel_path: str,
    language: str,
    kind: str,
    chunks: Sequence[Chunk],
    facts: Sequence[Fact],
) -> tuple[str, str]:
    symbols = list(dict.fromkeys(chunk.symbol for chunk in chunks if chunk.symbol))[:12]
    fact_labels = list(dict.fromkeys(f"{fact.kind}:{fact.key}" for fact in facts))[:8]
    summary_bits = [f"{Path(rel_path).name} is a {language} {kind} file"]
    if symbols:
        summary_bits.append("covering " + ", ".join(symbols[:5]))
    if fact_labels:
        summary_bits.append("with notable facts " + ", ".join(fact_labels[:5]))
    return ". ".join(summary_bits) + ".", " | ".join(symbols)


def replace_file_facts(
    conn: sqlite3.Connection,
    repo: str,
    rel_path: str,
    file_hash: str,
    facts: Sequence[Fact],
) -> None:
    conn.execute("DELETE FROM facts WHERE repo = ? AND path = ?", (repo, rel_path))
    now = time.time()
    for fact in facts:
        fact_key = f"{repo}:{rel_path}:{fact.kind}:{fact.key}:{fact.line}:{file_hash}"
        fact_id = str(uuid.uuid5(uuid.NAMESPACE_URL, fact_key))
        conn.execute(
            """
            INSERT INTO facts (
                fact_id, repo, path, kind, key, value, line,
                confidence, source, file_hash, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                fact_id,
                repo,
                rel_path,
                fact.kind,
                fact.key,
                fact.value,
                fact.line,
                fact.confidence,
                fact.source,
                file_hash,
                now,
            ),
        )


def replace_file_summary(
    conn: sqlite3.Connection,
    repo: str,
    rel_path: str,
    file_hash: str,
    language: str,
    kind: str,
    summary: str,
    symbols: str,
    facts_count: int,
) -> None:
    conn.execute(
        """
        INSERT INTO file_summaries (
            repo, path, file_hash, language, kind, summary, symbols, facts_count, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(repo, path) DO UPDATE SET
            file_hash=excluded.file_hash,
            language=excluded.language,
            kind=excluded.kind,
            summary=excluded.summary,
            symbols=excluded.symbols,
            facts_count=excluded.facts_count,
            updated_at=excluded.updated_at
        """,
        (repo, rel_path, file_hash, language, kind, summary, symbols, facts_count, time.time()),
    )


def chunk_by_anchors(lines: list[str], anchors: list[tuple[int, str]], size: int, overlap: int, kind: str) -> list[Chunk]:
    if not anchors:
        return chunk_by_lines(lines, size=size, overlap=overlap, kind=kind)

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
                    kind=kind,
                )
            )
        else:
            chunks.extend(chunk_by_lines(section, size=size, overlap=overlap, kind=kind, symbol=symbol))
    return [chunk for chunk in chunks if chunk.content]


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
    return chunk_by_anchors(lines, anchors, size=220, overlap=40, kind="code")


def chunk_shell(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if match := SHELL_FUNCTION_PATTERN.search(line):
            anchors.append((index, match.group(1)))
        elif line.strip().startswith("case ") and line.strip().endswith(" in"):
            anchors.append((index, line.strip()))
        elif match := SHELL_CASE_BRANCH_PATTERN.search(line):
            anchors.append((index, f"case:{match.group(1)}"))
        elif match := SHELL_ALIAS_PATTERN.search(line):
            anchors.append((index, f"alias {match.group(1)}"))
        elif match := SHELL_EXPORT_PATTERN.search(line):
            anchors.append((index, f"env {match.group(1)}"))
        else:
            for pattern in SHELL_TOOL_PATTERNS:
                if match := pattern.search(line):
                    anchors.append((index, f"tool:{match.group(1)}"))
                    break
    return chunk_by_anchors(lines, anchors, size=180, overlap=32, kind="code")


def chunk_toml(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [(index, match.group(1)) for index, line in enumerate(lines) if (match := TOML_SECTION_PATTERN.search(line))]
    return chunk_by_anchors(lines, anchors, size=180, overlap=28, kind="config")


def chunk_yaml(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [
        (index, line.split(":", 1)[0].strip())
        for index, line in enumerate(lines)
        if YAML_SECTION_PATTERN.search(line)
    ]
    return chunk_by_anchors(lines, anchors, size=180, overlap=28, kind="config")


def chunk_hyprland(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("$") and "=" in stripped:
            anchors.append((index, stripped.split("=", 1)[0].strip()))
            continue
        keyword = stripped.split("=", 1)[0].strip()
        if any(keyword.startswith(prefix) for prefix in HYPRLAND_KEYWORDS):
            anchors.append((index, hyprland_symbol(stripped)))
    return chunk_by_anchors(lines, anchors, size=120, overlap=18, kind="config")


def chunk_css(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors: list[tuple[int, str]] = []
    for index, line in enumerate(lines):
        if match := CSS_AT_RULE_PATTERN.search(line):
            anchors.append((index, match.group(1).strip()))
        elif match := CSS_SELECTOR_PATTERN.search(line):
            anchors.append((index, match.group(1).strip()))
    return chunk_by_anchors(lines, anchors, size=180, overlap=24, kind="code")


def chunk_html(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [(index, html_symbol(line)) for index, line in enumerate(lines) if html_symbol(line)]
    return chunk_by_anchors(lines, anchors, size=200, overlap=28, kind="code")


def chunk_xml_ui(text: str) -> list[Chunk]:
    lines = text.splitlines()
    anchors = [(index, xml_ui_symbol(line)) for index, line in enumerate(lines) if xml_ui_symbol(line)]
    return chunk_by_anchors(lines, anchors, size=200, overlap=28, kind="config")


def chunk_text(path: Path, text: str, kind: str, language: str) -> list[Chunk]:
    if kind == "docs":
        return chunk_markdown(text)
    if kind == "code":
        if language == "shell":
            return chunk_shell(text)
        if language == "css":
            return chunk_css(text)
        if language == "html":
            return chunk_html(text)
        return chunk_code(text)
    if kind == "log":
        return chunk_by_lines(text.splitlines(), size=350, overlap=50, kind="log")
    if kind == "config":
        if language == "hyprland":
            return chunk_hyprland(text)
        if path.suffix.lower() == ".toml":
            return chunk_toml(text)
        if path.suffix.lower() in {".yaml", ".yml"}:
            return chunk_yaml(text)
        if path.suffix.lower() in {".xml", ".ui", ".glade"}:
            return chunk_xml_ui(text)
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
    conn.execute("DELETE FROM facts WHERE repo = ? AND path = ?", (repo, rel_path))
    conn.execute("DELETE FROM file_summaries WHERE repo = ? AND path = ?", (repo, rel_path))


def index_repo(
    conn: sqlite3.Connection,
    client: QdrantClient,
    config: dict,
    root: Path,
    changed_only: bool,
    profile: dict,
) -> tuple[int, int]:
    ensure_collection(client, config)
    root, repo = repo_identity(root)
    existing = {
        row["path"]: {
            "file_hash": row["file_hash"],
            "index_schema": row["index_schema"],
            "embedding_model": row["embedding_model"],
            "chunker": row["chunker"],
        }
        for row in conn.execute(
            "SELECT path, file_hash, index_schema, embedding_model, chunker FROM chunks "
            "WHERE repo = ? GROUP BY path, file_hash, index_schema, embedding_model, chunker",
            (repo,),
        ).fetchall()
    }

    discovered: dict[str, str] = {}
    changed_files = 0
    total_chunks = 0

    try:
        for file_path in iter_text_files(root):
            rel_path = file_path.relative_to(root).as_posix()
            content = read_text_file(file_path)
            if not content or not content.strip():
                continue
            file_hash = hash_file(file_path)
            discovered[rel_path] = file_hash
            existing_file = existing.get(rel_path)
            if changed_only and existing_file == {
                "file_hash": file_hash,
                "index_schema": INDEX_SCHEMA,
                "embedding_model": config["embedding_model"],
                "chunker": CHUNKER_NAME,
            }:
                continue

            kind, language = detect_kind(file_path)
            chunks = chunk_text(file_path, content, kind, language)
            if not chunks:
                continue
            facts = extract_facts(file_path, content, language, kind) if profile["facts"] else []

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
                    "index_schema": INDEX_SCHEMA,
                    "embedding_model": config["embedding_model"],
                    "chunker": CHUNKER_NAME,
                }
                points.append(models.PointStruct(id=chunk_id, vector=vector.tolist(), payload=payload))
                conn.execute(
                    """
                    INSERT INTO chunks (
                        chunk_id, repo, root, path, language, kind, symbol, modified_at,
                        file_hash, index_schema, embedding_model, chunker, chunk_index,
                        start_line, end_line, content
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        INDEX_SCHEMA,
                        config["embedding_model"],
                        CHUNKER_NAME,
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

            if profile["facts"]:
                replace_file_facts(conn, repo, rel_path, file_hash, facts)
            if profile["file_summaries"]:
                summary, symbols = summarize_file(rel_path, language, kind, chunks, facts)
                replace_file_summary(conn, repo, rel_path, file_hash, language, kind, summary, symbols, len(facts))
            else:
                conn.execute("DELETE FROM file_summaries WHERE repo = ? AND path = ?", (repo, rel_path))

            for batch in batched(points, 64):
                client.upsert(collection_name=config["qdrant_collection"], points=list(batch), wait=True)

            changed_files += 1
            total_chunks += len(chunks)
            conn.commit()
    except KeyboardInterrupt as exc:
        conn.rollback()
        raise IndexInterrupted(changed_files, total_chunks) from exc

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


def detect_intent(query: str) -> str:
    lowered = query.lower()
    if any(token in lowered for token in ("super", "alt", "ctrl", "shift", "keybind", "shortcut", "xf86")):
        return "keybind"
    if any(token in lowered for token in ("command", "cli tool", "binary", "docker", "gh", "opencode", "just")):
        return "tool"
    return "general"


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


def normalize_query_keybind_tokens(query: str, config: dict) -> list[str]:
    normalized = []
    mapping = {
        "super": "SUPER",
        "alt": "ALT",
        "shift": "SHIFT",
        "grave": "GRAVE",
        **config["key_aliases"],
    }
    for token in query_terms(query):
        normalized.append(mapping.get(token, token.upper() if len(token) == 1 else token))
    return list(dict.fromkeys(normalized))


def fact_hits(conn: sqlite3.Connection, query: str, repo: str | None, intent: str, config: dict) -> list[sqlite3.Row]:
    if intent == "keybind":
        sql = "SELECT * FROM facts WHERE kind = 'keybind'" + (" AND repo = ?" if repo else "")
        rows = conn.execute(sql, [repo] if repo else []).fetchall()
        query_tokens = normalize_query_keybind_tokens(query, config)
        scored = []
        for row in rows:
            score = 0.0
            key_upper = row["key"].upper()
            value_lower = row["value"].lower()
            path_lower = row["path"].lower()
            for token in query_tokens:
                if token in key_upper:
                    score += 3.0
            if "scratchpad" in value_lower:
                score += 2.0
            if "hypr" in path_lower:
                score += 1.0
            if score > 0:
                scored.append((score, row))
        scored.sort(key=lambda item: item[0], reverse=True)
        return [row for _score, row in scored[:12]]
    if intent == "tool":
        sql = "SELECT * FROM facts WHERE kind = 'tool'" + (" AND repo = ?" if repo else "")
        rows = conn.execute(sql, [repo] if repo else []).fetchall()
        terms = query_terms(query)
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
    terms = query_terms(query)[:8]
    if not terms:
        return []
    clauses = []
    params: list[str] = []
    for term in terms:
        clauses.append("(key LIKE ? OR value LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%"])
    sql = "SELECT * FROM facts WHERE " + " OR ".join(clauses)
    if repo:
        sql += " AND repo = ?"
        params.append(repo)
    sql += " ORDER BY confidence DESC, updated_at DESC LIMIT 12"
    return conn.execute(sql, params).fetchall()


def file_summary_hits(conn: sqlite3.Connection, query: str, repo: str | None, intent: str) -> list[sqlite3.Row]:
    terms = query_terms(query)[:8]
    if not terms:
        return []
    clauses = []
    params: list[str] = []
    for term in terms:
        clauses.append("(path LIKE ? OR summary LIKE ? OR symbols LIKE ?)")
        params.extend([f"%{term}%", f"%{term}%", f"%{term}%"])
    sql = "SELECT * FROM file_summaries WHERE " + " OR ".join(clauses)
    if repo:
        sql += " AND repo = ?"
        params.append(repo)
    sql += " ORDER BY updated_at DESC LIMIT 20"
    rows = conn.execute(sql, params).fetchall()
    if intent not in {"keybind", "tool"}:
        return rows[:10]
    scored = []
    for row in rows:
        score = 0.0
        path_lower = row["path"].lower()
        summary_lower = row["summary"].lower()
        symbols_lower = (row["symbols"] or "").lower()
        if intent == "keybind":
            if any(token in path_lower for token in ("hypr", "keybind", "cheatsheet")):
                score += 2.0
            if "keybind" in summary_lower or "bind:" in symbols_lower:
                score += 2.0
        elif intent == "tool":
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


def get_index_profile(config: dict, override: str | None) -> tuple[str, dict]:
    profile_name = override or config["indexing"]["profile"]
    profile = config["index_profiles"].get(profile_name)
    if profile is None:
        raise SystemExit(f"Unknown index profile: {profile_name}")
    return profile_name, profile


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


def gather_context(
    rows: Sequence[sqlite3.Row],
    budget_tokens: int,
    facts: Sequence[sqlite3.Row] | None = None,
    summaries: Sequence[sqlite3.Row] | None = None,
    memory: str | None = None,
) -> tuple[str, list[str]]:
    sections: list[str] = []
    seen_files: list[str] = []
    used = 0

    def append_block(block: str, file_ref: str | None = None) -> bool:
        nonlocal used
        block_tokens = approx_tokens(block)
        if used + block_tokens > budget_tokens:
            return False
        sections.append(block)
        used += block_tokens
        if file_ref and file_ref not in seen_files:
            seen_files.append(file_ref)
        return True

    if memory:
        append_block(f"<repo_memory>\n{memory}\n</repo_memory>")

    if facts:
        fact_blocks: list[str] = []
        for index, fact in enumerate(facts, start=1):
            fact_blocks.append(
                f"[FACT {index}] {fact['repo']}/{fact['path']}:{fact['line']}\n"
                f"kind={fact['kind']} key={fact['key']}\n"
                f"value={fact['value']}"
            )
            seen_files.append(f"{fact['repo']}/{fact['path']}:{fact['line']}")
        append_block("<facts>\n" + "\n\n".join(fact_blocks) + "\n</facts>")

    if summaries:
        summary_blocks: list[str] = []
        for index, summary in enumerate(summaries, start=1):
            summary_blocks.append(
                f"[SUMMARY {index}] {summary['repo']}/{summary['path']}\n"
                f"kind={summary['kind']} language={summary['language']}\n"
                f"symbols={summary['symbols'] or '-'}\n"
                f"{summary['summary']}"
            )
            seen_files.append(f"{summary['repo']}/{summary['path']}")
        append_block("<file_summaries>\n" + "\n\n".join(summary_blocks) + "\n</file_summaries>")

    chunk_blocks: list[str] = []
    for row in rows:
        block = (
            f"[{len(chunk_blocks)+1}] {row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}\n"
            f"kind={row['kind']} language={row['language']} symbol={row['symbol'] or '-'}\n"
            f"{row['content']}"
        )
        prospective = "<chunks>\n" + "\n\n".join(chunk_blocks + [block]) + "\n</chunks>"
        if used + approx_tokens(prospective) > budget_tokens:
            break
        chunk_blocks.append(block)
        file_ref = f"{row['repo']}/{row['path']}:{row['start_line']}-{row['end_line']}"
        if file_ref not in seen_files:
            seen_files.append(file_ref)
    if chunk_blocks:
        append_block("<chunks>\n" + "\n\n".join(chunk_blocks) + "\n</chunks>")
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


def complete_llm(config: dict, system_prompt: str, user_prompt: str, max_tokens: int | None = None) -> str:
    payload = json.dumps(
        {
            "model": config["answer_model"],
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "temperature": 0.1,
            "stream": False,
            "max_tokens": max_tokens or config["answer_max_tokens"],
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


def ask_llm(config: dict, question: str, context: str) -> str:
    system_prompt = (
        "You are a repo-aware local coding assistant. Use the supplied context first, stay concrete, "
        "prefer code and runtime config over prose docs when they disagree, and cite file paths with "
        "line ranges in your answer when possible."
    )
    user_prompt = f"Question:\n{question}\n\nContext:\n{context}\n\nReturn a concise answer and cite files."
    return complete_llm(config, system_prompt, user_prompt)


def retrieve(
    conn: sqlite3.Connection,
    client: QdrantClient,
    config: dict,
    query: str,
    repo: str | None,
    use_reranker: bool,
) -> tuple[list[sqlite3.Row], list[sqlite3.Row], list[sqlite3.Row], sqlite3.Row | None, dict]:
    rewrites = rewrite_queries(query)
    intent = detect_intent(query)
    semantic = semantic_hits(client, config, rewrites, repo)
    keyword = keyword_hits(conn, rewrites, repo)
    recent = recent_hits(conn, query, repo)
    facts = fact_hits(conn, query, repo, intent, config)
    summaries = file_summary_hits(conn, query, repo, intent)
    memory = repo_memory_row(conn, repo)
    fact_paths = {row["path"] for row in facts}
    summary_paths = {row["path"] for row in summaries}
    scores = reciprocal_rank_fusion(semantic, keyword, recent)
    ranked_ids = [chunk_id for chunk_id, _ in sorted(scores.items(), key=lambda item: item[1], reverse=True)]
    rows = load_chunks(conn, ranked_ids[: config["reranker"]["top_k_input"]])
    debug = {
        "rewrites": rewrites,
        "semantic_hits": len(semantic),
        "keyword_hits": len(keyword),
        "recent_hits": len(recent),
        "fact_hits": len(facts),
        "file_summary_hits": len(summaries),
        "memory_loaded": memory is not None,
        "merged_unique": len(scores),
        "ranking_enabled": use_reranker,
        "ranking_mode": config["reranker"]["mode"],
        "intent": intent,
    }
    if use_reranker:
        return (
            rerank_chunks(query, rows, scores, config, intent, fact_paths, summary_paths),
            facts,
            summaries,
            memory,
            debug,
        )
    return rows[: config["reranker"]["top_k_output"]], facts, summaries, memory, debug


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
    rows, facts, summaries, memory, debug = retrieve(conn, client, config, args.query, repo, reranker_enabled(config, args.rerank))
    if args.explain:
        print_retrieval_explain(debug, rows)
        console.print()
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
    rows, facts, summaries, memory, debug = retrieve(conn, client, config, args.query, repo, reranker_enabled(config, args.rerank))
    if not rows:
        console.print("[yellow]No indexed context matched that query.[/yellow]")
        return 1
    context, files = gather_context(
        rows,
        config["retrieval_context_tokens"],
        facts=facts,
        summaries=summaries,
        memory=memory["summary"] if args.memory and memory else None,
    )
    if args.show_context:
        print_retrieval_explain(debug, rows)
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
    fact_count = conn.execute("SELECT COUNT(*) AS count FROM facts").fetchone()["count"]
    summary_count = conn.execute("SELECT COUNT(*) AS count FROM file_summaries").fetchone()["count"]
    memory_count = conn.execute("SELECT COUNT(*) AS count FROM repo_memory").fetchone()["count"]
    table.add_row("memory", "ok", f"{fact_count} facts, {summary_count} file summaries, {memory_count} repo memories")

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
    table.add_row(
        "reranker",
        "ok" if config["reranker"]["enabled"] else "off",
        f"{config['reranker']['mode']} (top {config['reranker']['top_k_output']})",
    )
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

    memory_parser = subparsers.add_parser("memory", help="Show, refresh, or clear repo memory")
    memory_parser.add_argument("memory_command", choices=["show", "refresh", "clear"])
    memory_parser.add_argument("--repo", help="Target repo name")
    memory_parser.add_argument("--all", action="store_true", help="Apply clear to all repos")
    memory_parser.set_defaults(func=cmd_memory)

    facts_parser = subparsers.add_parser("facts", help="List or query structured facts")
    facts_parser.add_argument("subject", help="Use `list` or a fact kind like alias, keybind, env, tool, sql-object")
    facts_parser.add_argument("query", nargs="*", help="Search text when querying a fact kind")
    facts_parser.add_argument("--repo", help="Filter to one repo")
    facts_parser.add_argument("--kind", help="Fact kind filter when using `rag facts list`")
    facts_parser.set_defaults(func=cmd_facts)

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


if __name__ == "__main__":
    sys.exit(main())
