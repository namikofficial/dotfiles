"""Reranker for RAG retrieval results.

Supports two modes:
  heuristic — fast, no model, uses path/symbol/recency signals
  neural     — cross-encoder via fastembed (BAAI/bge-reranker-v2-m3)
  auto       — neural if available, else heuristic
"""
from __future__ import annotations

import re
import time
from pathlib import Path
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from .types import RetrievalResult

_neural_reranker = None
_neural_available: bool | None = None


def _field(result: Any, name: str, default: Any = "") -> Any:
    if isinstance(result, dict):
        return result.get(name, default)
    try:
        return result[name]
    except Exception:
        return getattr(result, name, default)


def _try_load_neural() -> bool:
    global _neural_reranker, _neural_available
    if _neural_available is not None:
        return _neural_available
    try:
        from fastembed.rerank.cross_encoder import TextCrossEncoder  # type: ignore
        _neural_reranker = TextCrossEncoder(model_name="BAAI/bge-reranker-v2-m3")
        _neural_available = True
    except Exception:
        _neural_available = False
    return bool(_neural_available)


# ── heuristic reranker ──────────────────────────────────────────────────────

def _symbol_overlap(query: str, text: str) -> float:
    """Fraction of query tokens (≥4 chars) found in text."""
    tokens = [t for t in re.findall(r"\b\w{4,}\b", query.lower()) if t]
    if not tokens:
        return 0.0
    found = sum(1 for t in tokens if t in text.lower())
    return found / len(tokens)


def _path_relevance(query: str, file_path: str) -> float:
    score = 0.0
    query_lower = query.lower()
    path_lower = file_path.lower()
    if "test" in path_lower and "test" not in query_lower:
        score -= 0.15
    if any(seg in path_lower for seg in ("src/", "lib/", "core/")):
        score += 0.05
    for token in re.findall(r"\b\w{4,}\b", query_lower):
        if token in path_lower:
            score += 0.10
    return score


def _recency_boost(file_path: str, now: float | None = None) -> float:
    """Small boost for recently modified files (up to +0.08)."""
    try:
        mtime = Path(file_path).stat().st_mtime
        age_days = ((now or time.time()) - mtime) / 86400
        if age_days < 1:
            return 0.08
        if age_days < 7:
            return 0.04
        if age_days < 30:
            return 0.02
    except OSError:
        pass
    return 0.0


def _definition_boost(query: str, chunk_text: str) -> float:
    """Boost if chunk is a definition of something named in the query."""
    for token in re.findall(r"\b[A-Za-z_]\w{3,}\b", query):
        pattern = rf"\b(def|class|function|const|type|interface)\s+{re.escape(token)}\b"
        if re.search(pattern, chunk_text, re.IGNORECASE):
            return 0.12
    return 0.0


def heuristic_score(query: str, result: "RetrievalResult") -> float:
    """Return a float score for a single retrieval result."""
    base = float(_field(result, "score", 0.5) or 0.5)
    text = _field(result, "text", "") or _field(result, "content", "") or ""
    path = _field(result, "file_path", "") or _field(result, "path", "") or ""
    score = base
    score += _symbol_overlap(query, text) * 0.20
    score += _path_relevance(query, path)
    score += _recency_boost(path)
    score += _definition_boost(query, text)
    return score


def rerank_heuristic(query: str, results: list) -> list:
    """Return results sorted by heuristic score descending."""
    scored = [(heuristic_score(query, r), r) for r in results]
    scored.sort(key=lambda x: x[0], reverse=True)
    return [r for _, r in scored]


def rerank_neural(query: str, results: list) -> list:
    """Rerank using cross-encoder. Falls back to heuristic if unavailable."""
    if not _try_load_neural():
        return rerank_heuristic(query, results)
    texts = [(_field(r, "text", "") or _field(r, "content", "") or "") for r in results]
    try:
        scores = list(_neural_reranker.rerank(query, texts))  # type: ignore[attr-defined]
        paired = sorted(zip(scores, results), key=lambda x: x[0], reverse=True)
        return [r for _, r in paired]
    except Exception:
        return rerank_heuristic(query, results)


def rerank(query: str, results: list, mode: str = "auto") -> list:
    """Rerank `results` for `query`. mode: auto|neural|heuristic."""
    if not results:
        return results
    if mode == "heuristic":
        return rerank_heuristic(query, results)
    if mode == "neural":
        return rerank_neural(query, results)
    if _try_load_neural():
        return rerank_neural(query, results)
    return rerank_heuristic(query, results)
