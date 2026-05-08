from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol, Sequence, TypedDict


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


class RepoMemoryStatus(TypedDict):
    repo: str
    root: str
    status: str
    reasons: list[str]
    memory_updated_at: float | None
    last_indexed: float
    chunk_count: int
    summary_commit: str | None
    current_commit: str | None
    changed_files: list[str]
    changed_symbols: list[str]
    freshness_score: float


class SupportsQdrantCollectionAdmin(Protocol):
    def collection_exists(self, collection_name: str) -> bool: ...

    def get_collection(self, collection_name: str) -> Any: ...

    def create_collection(self, collection_name: str, vectors_config: Any) -> Any: ...


class SupportsQdrantPointOps(Protocol):
    def upsert(self, collection_name: str, points: Sequence[Any], wait: bool = True) -> Any: ...

    def delete(self, collection_name: str, points_selector: Any, wait: bool = True) -> Any: ...


class IndexInterrupted(Exception):
    def __init__(self, changed_files: int, total_chunks: int):
        super().__init__("index interrupted")
        self.changed_files = changed_files
        self.total_chunks = total_chunks
