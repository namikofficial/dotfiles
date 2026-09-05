// LLM grader — uses a subscriber model (cheap, fast) to score qualitative dimensions
// like "decision-quality" or "evidence-grounded" against a written artifact.
//
// Same JSON contract as the visual grader but invoked for non-image tasks:
//   scenario.prompt is the task;
//   the implementation produces one or more text artifacts;
//   the LLM grader scores them against scenario.dimensions.

import { aggregateDimensions, aggregateGates, dimension, finding, gate } from "../types.mjs"

export function buildLlmPrompt({ scenario, artifactPaths, artifactContents }) {
  return [
    "# Qualitative evaluation task",
    "",
    `## Scenario: ${scenario.title}`,
    `Domain: ${scenario.domain}`,
    "",
    "## Task prompt given to the implementation agent under test",
    "",
    scenario.prompt,
    "",
    "## Artifacts produced by the implementation agent",
    ...artifactPaths.map((p, i) => {
      const content = artifactContents?.[i]
      const truncated = content && content.length > 4000 ? content.slice(0, 4000) + "\n...[truncated]" : content
      return `### ${p}\n\n${truncated ?? "(empty or unreadable)"}`
    }),
    "",
    "## Hard gates (each must PASS or FAIL with evidence)",
    ...(scenario.hard_gates ?? []).map((g, i) => `${i + 1}. ${g.name}${g.description ? ` — ${g.description}` : ""}`),
    "",
    "## Dimensions to score (0..10)",
    ...(scenario.dimensions ?? []).map((d, i) => `${i + 1}. ${d.name} (weight ${d.weight})${d.description ? ` — ${d.description}` : ""}`),
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
            file: "<artifact path>",
            evidence: "<quote>",
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
  ].join("\n")
}

export function parseLlmResponse(jsonText, ctx) {
  let parsed
  try {
    parsed = JSON.parse(jsonText)
  } catch (e) {
    return {
      grader: "llm",
      status: "INCOMPLETE",
      gates: [],
      dimensions: [],
      findings: [
        finding({
          rule: "llm/response-parse-error",
          severity: "error",
          file: "(llm-agent)",
          evidence: jsonText.slice(0, 300),
          suggestedInvestigation: "LLM agent did not return valid JSON",
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
      rule: f.rule ?? "llm/unspecified",
      severity: f.severity ?? "advisory",
      confidence: 0.6,
      file: f.file ?? "(artifact)",
      evidence: f.evidence ?? "",
      suggestedInvestigation: f.suggestedInvestigation ?? "",
      provenance: f.provenance ?? "INFERRED",
    }),
  )

  const hardGates = (ctx.scenario.hard_gates ?? []).map((g) => {
    const matching = findings.filter((f) => f.rule.includes(g.name))
    return gate(g.name, matching)
  })

  return {
    grader: "llm",
    status: parsed.overall_status === "FAIL" ? "FAIL" : aggregateGates(hardGates),
    gates: hardGates,
    dimensions: dims,
    findings,
    startedAt: new Date().toISOString(),
    finishedAt: new Date().toISOString(),
    meta: { summary: parsed.summary ?? "" },
  }
}
