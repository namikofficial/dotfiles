from __future__ import annotations

import os
from pathlib import Path

from rich.console import Console

console = Console()
RAG_HOME = Path(os.environ.get("RAG_HOME", str(Path.home() / "ai-rag"))).expanduser()
CONFIG_PATH = RAG_HOME / "config.json"
DB_PATH = RAG_HOME / "rag.sqlite3"
INDEX_SCHEMA = "rag-v4"
CHUNKER_NAME = "semantic-lines-v4"
