from __future__ import annotations

from dataclasses import dataclass
import math


def recall_at_k(expected: set[str], ranked: list[str], k: int) -> float:
    if not expected:
        return 1.0
    top = set(ranked[:k])
    return len(expected & top) / len(expected)


def mean_reciprocal_rank(expected: set[str], ranked: list[str]) -> float:
    for index, path in enumerate(ranked, start=1):
        if path in expected:
            return 1.0 / index
    return 0.0


def ndcg_at_k(expected: set[str], ranked: list[str], k: int) -> float:
    if not expected:
        return 1.0
    dcg = 0.0
    for index, path in enumerate(ranked[:k], start=1):
        if path in expected:
            dcg += 1.0 / math.log2(index + 1)
    ideal_hits = min(len(expected), k)
    if ideal_hits == 0:
        return 0.0
    idcg = sum(1.0 / math.log2(index + 1) for index in range(1, ideal_hits + 1))
    return dcg / idcg if idcg else 0.0


def coverage_score(expected: set[str], ranked: list[str]) -> float:
    if not expected:
        return 1.0
    if not ranked:
        return 0.0
    overlap = expected & set(ranked)
    return len(overlap) / max(len(expected), min(len(ranked), len(expected)))


def aggregate_eval_metrics(results: list[dict]) -> dict[str, float | int | dict[str, float]]:
    if not results:
        return {
            "cases": 0,
            "recall_at_5": 0.0,
            "recall_at_10": 0.0,
            "mrr": 0.0,
            "ndcg": 0.0,
            "coverage_score": 0.0,
            "latency_ms": 0.0,
            "packed_token_count": 0.0,
            "candidate_counts_by_channel": {},
        }
    def avg(key: str) -> float:
        return sum(float(item.get(key, 0.0)) for item in results) / len(results)
    channel_counts: dict[str, float] = {}
    for item in results:
        for key, value in item.get("candidate_counts_by_channel", {}).items():
            channel_counts[key] = channel_counts.get(key, 0.0) + float(value)
    return {
        "cases": len(results),
        "recall_at_5": avg("recall_at_5"),
        "recall_at_10": avg("recall_at_10"),
        "mrr": avg("mrr"),
        "ndcg": avg("ndcg"),
        "coverage_score": avg("coverage_score"),
        "latency_ms": avg("latency_ms"),
        "packed_token_count": avg("packed_token_count"),
        "candidate_counts_by_channel": {
            key: value / len(results) for key, value in sorted(channel_counts.items())
        },
    }


@dataclass(frozen=True)
class RetrievalEvalResult:
    suite: str
    recall_at_5_regressed: bool
    mrr_delta: float
    p95_latency_overhead_ms: int
    citation_precision_regressed: bool

    @property
    def passes_reranker_gate(self) -> bool:
        return (
            not self.recall_at_5_regressed
            and self.mrr_delta >= 0.03
            and self.p95_latency_overhead_ms <= 400
            and not self.citation_precision_regressed
        )


def evaluate_reranker_gate(
    *,
    suite: str,
    mrr_delta: float,
    p95_latency_overhead_ms: int,
    recall_at_5_regressed: bool = False,
    citation_precision_regressed: bool = False,
) -> RetrievalEvalResult:
    return RetrievalEvalResult(
        suite=suite,
        recall_at_5_regressed=recall_at_5_regressed,
        mrr_delta=mrr_delta,
        p95_latency_overhead_ms=p95_latency_overhead_ms,
        citation_precision_regressed=citation_precision_regressed,
    )
