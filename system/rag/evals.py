from __future__ import annotations

from dataclasses import dataclass


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
