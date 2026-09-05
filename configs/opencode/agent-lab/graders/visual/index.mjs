// Visual grader — produces a structured prompt asking the vision/vision-expert agent
// to score screenshots against the scenario's dimensions. The actual scoring is done
// by the LLM at run time; this module builds the prompt and parses the structured
// response into a GraderResult.
//
// Because we cannot call vision models from a non-interactive test runner in this
// OpenCode version, the visual grader is implemented as a prompt builder + response
// parser. The runner pipes the prompt to the configured vision agent.
//
// Schema of expected LLM response:
// {
//   "overall_status": "PASS" | "FAIL",
//   "dimension_scores": [{ "name": "...", "score": 0..10, "rationale": "..." }],
//   "findings": [{ "rule": "...", "severity": "error|warning|advisory",
//                  "file": "...", "evidence": "...", "suggestedInvestigation": "...",
//                  "provenance": "OBSERVED|INFERRED|..." }],
//   "summary": "..."
// }

import { aggregateDimensions, aggregateGates, dimension, finding, gate } from "../types.mjs"

/**
 * Build the prompt that should be sent to the vision agent.
 * @param {{scenario: any, screenshotPaths: string[], imageDimensions?: any}} args
 */
export function buildVisualPrompt({ scenario, screenshotPaths, imageDimensions }) {
  return [
    "# Visual evaluation task",
    "",
    `## Scenario: ${scenario.title}`,
    `Domain: ${scenario.domain}`,
    "",
    "## Prompt given to the implementation agent under test",
    "",
    scenario.prompt,
    "",
    "## Hard gates (each must PASS or FAIL with evidence)",
    ...(scenario.hard_gates ?? []).map((g, i) => `${i + 1}. ${g.name}${g.description ? ` — ${g.description}` : ""}`),
    "",
    "## Dimensions to score (0..10)",
    ...(scenario.dimensions ?? []).map((d, i) => `${i + 1}. ${d.name} (weight ${d.weight})${d.description ? ` — ${d.description}` : ""}`),
    "",
    "## Screenshots to evaluate",
    ...screenshotPaths.map((p, i) => `${i + 1}. ${p}`),
    "",
    "## Required response shape (return ONLY valid JSON, no prose)",
    "",
    "```json",
    JSON.stringify(
      {
        overall_status: "PASS or FAIL",
        dimension_scores: [{ name: "<dim name>", score: 0, rationale: "<one sentence>" }],
        findings: [
          {
            rule: "<short identifier>",
            severity: "error|warning|advisory",
            file: "<screenshot path or region>",
            evidence: "<what you saw>",
            suggestedInvestigation: "<what to do>",
            provenance: "OBSERVED|INFERRED|ASSUMED|UNVERIFIED",
          },
        ],
        summary: "<one-paragraph assessment>",
      },
      null,
      2,
    ),
    "",
    "```",
    "",
    "Provenance rules:",
    "- OBSERVED: directly visible in the screenshots",
    "- INFERRED: reasoning from observed facts",
    "- UNVERIFIED: claim you cannot support with the screenshots — flag explicitly",
    "",
    "Use hard-gate failure for: missing required state, keyboard-inaccessible primary action, no recoverable empty state, console-error indicators.",
  ].join("\n")
}

/**
 * Parse a structured JSON response from the vision agent into a GraderResult.
 * @param {string} jsonText
 * @param {{scenario: any}} ctx
 */
export function parseVisualResponse(jsonText, ctx) {
  let parsed
  try {
    parsed = JSON.parse(jsonText)
  } catch (e) {
    return {
      grader: "visual",
      status: "INCOMPLETE",
      gates: [],
      dimensions: [],
      findings: [
        finding({
          rule: "visual/response-parse-error",
          severity: "error",
          file: "(vision-agent)",
          evidence: jsonText.slice(0, 300),
          suggestedInvestigation: "vision agent did not return valid JSON",
        }),
      ],
      startedAt: new Date().toISOString(),
      finishedAt: new Date().toISOString(),
      meta: { parseError: String(e) },
    }
  }

  const dimMap = new Map((ctx.scenario.dimensions ?? []).map((d) => [d.name, d]))
  const dims = (parsed.dimension_scores ?? [])
    .map((ds) => {
      const def = dimMap.get(ds.name)
      if (!def) return null
      return dimension(ds.name, Math.max(0, Math.min(10, ds.score)), def.weight, [], ds.rationale)
    })
    .filter((d) => d !== null)

  const findings = (parsed.findings ?? []).map((f) =>
    finding({
      rule: f.rule ?? "visual/unspecified",
      severity: f.severity ?? "advisory",
      confidence: 0.7, // visual findings are inherently less confident
      file: f.file ?? "(screenshot)",
      evidence: f.evidence ?? "",
      suggestedInvestigation: f.suggestedInvestigation ?? "",
      provenance: f.provenance ?? "INFERRED",
    }),
  )

  const hardGates = (ctx.scenario.hard_gates ?? []).map((g) => {
    const matching = findings.filter((f) => f.rule.includes(g.name) || f.file === g.name)
    return gate(g.name, matching)
  })

  return {
    grader: "visual",
    status: parsed.overall_status === "FAIL" ? "FAIL" : aggregateGates(hardGates),
    gates: hardGates,
    dimensions: dims,
    findings,
    startedAt: new Date().toISOString(),
    finishedAt: new Date().toISOString(),
    meta: { summary: parsed.summary ?? "" },
  }
}
