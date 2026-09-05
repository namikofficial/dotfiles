// Security grader — runs the executable invariant scripts (Layer 3) and converts their
// output into the structured finding shape.
//
// For now, this is a thin wrapper that runs any *.mjs script under
// configs/opencode/skills/tenancy-invariants/scripts/ and parses a JSON-line output
// stream where each line is `{ "rule": ..., "severity": ..., "file": ..., "line": ...,
// "evidence": ..., "suggestedInvestigation": ... }`.

import { execSync } from "node:child_process"
import { resolve } from "node:path"
import { existsSync, readdirSync } from "node:fs"
import { aggregateDimensions, aggregateGates, dimension, finding, gate } from "../types.mjs"

const SCRIPTS_DIR = resolve(
  new URL("../../../skills/tenancy-invariants/scripts/", import.meta.url).pathname,
)
const FITNESS_SCRIPT = resolve(
  new URL("../../../skills/architecture-fitness/scripts/check-import-graph.mjs", import.meta.url).pathname,
)

/**
 * @param {{workdir: string, scenario: any}} args
 */
export async function runSecurityGrader({ workdir, scenario }) {
  const startedAt = new Date().toISOString()
  const findings = []
  const dimensions = []

  if (!existsSync(SCRIPTS_DIR)) {
    return {
      grader: "security",
      status: "INCOMPLETE",
      gates: [gate("security-invariants", [], "tenancy-invariants/scripts/ not yet present (Layer 3)")],
      dimensions: [dimension("invariant-coverage", 0, 0.30, [], "no scripts available")],
      findings: [
        finding({
          rule: "security/scripts-missing",
          severity: "advisory",
          file: SCRIPTS_DIR,
          evidence: "scripts directory not present",
          suggestedInvestigation: "Layer 3 must install tenancy-invariants/scripts/",
        }),
      ],
      startedAt,
      finishedAt: new Date().toISOString(),
      meta: { scriptsDir: SCRIPTS_DIR },
    }
  }

  const scripts = readdirSync(SCRIPTS_DIR).filter((f) => f.endsWith(".mjs"))

  // Also run the architecture-fitness script if it exists
  if (existsSync(FITNESS_SCRIPT)) {
    let out = ""
    let execError = null
    try {
      out = execSync(`node "${FITNESS_SCRIPT}" --workdir "${workdir}"`, {
        encoding: "utf8",
        timeout: 60_000,
      })
    } catch (e) {
      out = e.stdout?.toString() ?? ""
      execError = e
    }
    for (const line of out.split("\n").filter(Boolean)) {
      try {
        const ev = JSON.parse(line)
        findings.push(
          finding({
            rule: ev.rule ?? "arch/fitness",
            severity: ev.severity ?? "advisory",
            confidence: ev.confidence ?? 0.9,
            file: ev.file ?? "",
            line: ev.line ?? 0,
            symbol: ev.symbol ?? "",
            evidence: ev.evidence ?? "",
            suggestedInvestigation: ev.suggestedInvestigation ?? "",
            provenance: "OBSERVED",
          }),
        )
      } catch {}
    }
  }

  for (const script of scripts) {
    const scriptPath = resolve(SCRIPTS_DIR, script)
    let out = ""
    let execError = null
    try {
      out = execSync(`node "${scriptPath}" --workdir "${workdir}"`, {
        encoding: "utf8",
        timeout: 60_000,
      })
    } catch (e) {
      // Non-zero exit from the script (e.g. scan-client-tenant-input exits 1 on error findings).
      // The stdout is still meaningful — read it and process as findings.
      out = e.stdout?.toString() ?? ""
      execError = e
    }

    for (const line of out.split("\n").filter(Boolean)) {
      try {
        const ev = JSON.parse(line)
        findings.push(
          finding({
            rule: ev.rule ?? script,
            severity: ev.severity ?? "advisory",
            confidence: ev.confidence ?? 0.9,
            file: ev.file ?? "",
            line: ev.line ?? 0,
            symbol: ev.symbol ?? "",
            evidence: ev.evidence ?? "",
            suggestedInvestigation: ev.suggestedInvestigation ?? "",
            provenance: "OBSERVED",
          }),
        )
      } catch {
        // non-JSON line, ignore
      }
    }

    if (execError && findings.length === 0) {
      // The script crashed without emitting findings
      findings.push(
        finding({
          rule: `security/${script}/exec-error`,
          severity: "warning",
          file: scriptPath,
          evidence: execError?.message?.slice(0, 200) ?? "",
          suggestedInvestigation: `investigate why ${script} failed to run`,
        }),
      )
    }
  }

  // Hard gate: tenant-invariant-holds (or scenario-specific security gate)
  const errorFindings = findings.filter((f) => f.severity === "error")
  const gates = [gate("tenant-invariant-holds", errorFindings.filter((f) => f.rule.startsWith("tenant/")))]
  if (scenario.id === "backend-tenant-query-scoping") {
    gates.push(gate("tenant-invariant-holds", errorFindings))
  }

  dimensions.push(
    dimension(
      "invariant-coverage",
      Math.max(0, 10 - errorFindings.length * 2),
      0.30,
      errorFindings,
      `${errorFindings.length} invariant violations across ${scripts.length} scripts`,
    ),
  )

  const finishedAt = new Date().toISOString()
  return {
    grader: "security",
    status: aggregateGates(gates),
    gates,
    dimensions,
    findings,
    startedAt,
    finishedAt,
    meta: { scripts: scripts.length, scriptsDir: SCRIPTS_DIR },
  }
}
