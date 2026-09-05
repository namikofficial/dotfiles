// Shared types and helpers for the agent-lab grader interface.
// All graders must emit findings with the structured shape documented in
// ../../../configs/opencode/agent-lab/README.md.

/**
 * @typedef {Object} Finding
 * @property {string} rule
 * @property {"error" | "warning" | "advisory"} severity
 * @property {number} confidence       0..1
 * @property {string} file             path or identifier (e.g. "(bash)" for shell findings)
 * @property {number} line             0 if not applicable
 * @property {string} symbol           symbol name, path, or "(shell)"/"(path)"/"(scenario)"
 * @property {string} evidence         the actual matched text/command/payload
 * @property {string} suggestedInvestigation
 * @property {"OBSERVED" | "INFERRED" | "ASSUMED" | "UNVERIFIED"} [provenance]
 * @property {Record<string, unknown>} [meta]
 */

/**
 * @typedef {Object} GateResult
 * @property {string} name
 * @property {"PASS" | "FAIL" | "NOT_CONFIGURED"} status
 * @property {string} [reason]
 * @property {Finding[]} findings
 */

/**
 * @typedef {Object} DimensionScore
 * @property {string} name
 * @property {number} score          0..10
 * @property {number} weight
 * @property {string} [rationale]
 * @property {Finding[]} findings
 */

/**
 * @typedef {Object} GraderResult
 * @property {string} grader
 * @property {"PASS" | "FAIL" | "INCOMPLETE"} status
 * @property {GateResult[]} gates
 * @property {DimensionScore[]} dimensions
 * @property {Finding[]} findings
 * @property {string} startedAt
 * @property {string} finishedAt
 * @property {Record<string, unknown>} [meta]
 */

/** @param {Partial<Finding>} input */
export const finding = (input) => ({
  rule: input.rule ?? "unknown",
  severity: input.severity ?? "advisory",
  confidence: input.confidence ?? 1.0,
  file: input.file ?? "",
  line: input.line ?? 0,
  symbol: input.symbol ?? "",
  evidence: input.evidence ?? "",
  suggestedInvestigation: input.suggestedInvestigation ?? "",
  provenance: input.provenance ?? "OBSERVED",
  meta: input.meta ?? {},
})

/** @param {string} name @param {Finding[]} [findings] @param {string} [reason] */
export const gate = (name, findings = [], reason) => ({
  name,
  status: findings.some((f) => f.severity === "error") ? "FAIL" : "PASS",
  reason,
  findings,
})

/** @param {string} name @param {number} score @param {number} weight @param {Finding[]} [findings] */
export const dimension = (name, score, weight, findings = [], rationale) => ({
  name,
  score,
  weight,
  findings,
  rationale,
})

/** Aggregate gates to a single PASS/FAIL */
export const aggregateGates = (gates) => {
  if (gates.some((g) => g.status === "FAIL")) return "FAIL"
  if (gates.some((g) => g.status === "NOT_CONFIGURED")) return "INCOMPLETE"
  return "PASS"
}

/** Aggregate dimensions to a 0..100 weighted score (for reporting only — not the gate) */
export const aggregateDimensions = (dimensions) => {
  const total = dimensions.reduce((acc, d) => acc + d.score * d.weight, 0)
  const weights = dimensions.reduce((acc, d) => acc + d.weight, 0)
  return weights === 0 ? 0 : Math.round((total / weights) * 10) // out of 100
}
