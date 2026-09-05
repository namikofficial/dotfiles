// Browser grader — scores pre-captured browser evidence (screenshots, console transcripts,
// network logs). The runner is responsible for producing this evidence via the browser MCP;
// this grader analyzes it.
//
// Inputs (passed via args):
//   - screenshots: Array<{ path: string, state: string }>
//   - console:    Array<{ level: string, message: string, url: string }>
//   - network:    Array<{ url: string, status: number, method: string, body?: any }>
//   - scenario:   the scenario JSON

import { existsSync, readFileSync, statSync } from "node:fs"
import { resolve } from "node:path"
import { aggregateDimensions, aggregateGates, dimension, finding, gate } from "../types.mjs"

/** @param {{scenario: any, screenshots?: any[], console?: any[], network?: any[]}} args */
export async function runBrowserGrader({ scenario, screenshots = [], console = [], network = [] }) {
  const startedAt = new Date().toISOString()
  const findings = []
  const gates = []
  const dimensions = []

  // Gate: no-console-errors
  const consoleErrors = console.filter((m) => m.level === "error")
  if (consoleErrors.length > 0) {
    for (const e of consoleErrors) {
      findings.push(
        finding({
          rule: "browser/console-error",
          severity: "error",
          confidence: 0.95,
          file: e.url ?? "(page)",
          evidence: e.message?.slice(0, 300) ?? "",
          suggestedInvestigation: "investigate console error",
        }),
      )
    }
  }
  gates.push(gate("no-console-errors", findings.filter((f) => f.rule === "browser/console-error")))

  // Gate: network 5xx
  const serverErrors = network.filter((r) => r.status >= 500)
  const netFindings = serverErrors.map((r) =>
    finding({
      rule: "browser/network-5xx",
      severity: "error",
      confidence: 0.95,
      file: r.url,
      evidence: `${r.method} ${r.url} → ${r.status}`,
      suggestedInvestigation: "investigate server error",
    }),
  )
  gates.push(gate("no-network-5xx", netFindings))

  // Gate: states-covered — check screenshots exist for required states
  if (Array.isArray(scenario.expected_artifacts)) {
    const requiredStates = scenario.expected_artifacts
      .filter((a) => a.type === "screenshot")
      .map((a) => a.path)
    const present = requiredStates.filter((p) => {
      try {
        return existsSync(p) && statSync(p).size > 0
      } catch {
        return false
      }
    })
    const missing = requiredStates.filter((p) => !present.includes(p))
    const missingFindings = missing.map((p) =>
      finding({
        rule: "states-covered/missing-screenshot",
        severity: "warning",
        file: p,
        evidence: `expected screenshot for state not captured`,
        suggestedInvestigation: `capture ${p}`,
      }),
    )
    gates.push(gate("states-covered", missingFindings))
  }

  // Dimensions: state coverage ratio
  if (screenshots.length > 0) {
    dimensions.push(
      dimension(
        "state-coverage",
        Math.min(10, screenshots.length * 2),
        0.30,
        [],
        `${screenshots.length} state screenshots captured`,
      ),
    )
  }

  // Dimensions: console hygiene
  const consoleWarns = console.filter((m) => m.level === "warning").length
  dimensions.push(
    dimension(
      "console-hygiene",
      Math.max(0, 10 - consoleErrors.length * 3 - consoleWarns),
      0.20,
      [],
      `${consoleErrors.length} errors, ${consoleWarns} warnings`,
    ),
  )

  // Dimensions: network correctness
  const totalCalls = network.length
  const failedCalls = serverErrors.length + network.filter((r) => r.status >= 400 && r.status < 500).length
  dimensions.push(
    dimension(
      "network-correctness",
      totalCalls === 0 ? 5 : Math.max(0, 10 - Math.round((failedCalls / totalCalls) * 10)),
      0.20,
      [],
      `${failedCalls}/${totalCalls} non-2xx responses`,
    ),
  )

  const finishedAt = new Date().toISOString()
  return {
    grader: "browser",
    status: aggregateGates(gates),
    gates,
    dimensions,
    findings,
    startedAt,
    finishedAt,
    meta: {
      screenshots: screenshots.length,
      consoleMessages: console.length,
      networkCalls: network.length,
    },
  }
}
