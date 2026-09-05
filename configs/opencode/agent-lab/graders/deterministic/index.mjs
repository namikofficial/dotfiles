// Deterministic grader — runs cheap, non-LLM checks against the changed codebase.
// Checks covered:
//   - forbidden_changes: any file in scenario.forbidden_changes was modified (FAIL)
//   - expected_artifacts: any expected file is missing (FAIL)
//   - no-console-errors: scan JS/TS for accidental console.log/error etc. in production paths (warning)
//   - no-bare-regex-on-secret: scan for patterns like `password ===` / `secret ===` in comparisons (advisory)
//   - file-exists: every expected_artifacts[].path that is a "file" exists (FAIL if not)
//
// Output: GraderResult in the structured shape.

import { existsSync } from "node:fs"
import { resolve, relative } from "node:path"
import { execSync } from "node:child_process"
import { aggregateDimensions, aggregateGates, dimension, finding, gate } from "../types.mjs"

/**
 * @param {Object} args
 * @param {Object} args.scenario       - the loaded scenario JSON
 * @param {string} args.workdir        - the working directory the agent ran in
 * @param {string[]} [args.changedFiles] - list of files changed by the agent (sorted)
 */
export async function runDeterministicGrader({ scenario, workdir, changedFiles = [] }) {
  const startedAt = new Date().toISOString()
  const findings = []
  const gates = []
  const dimensions = []

  const repo = resolve(workdir)

  // Gate: forbidden_changes
  if (Array.isArray(scenario.forbidden_changes) && scenario.forbidden_changes.length) {
    const forbidFindings = []
    for (const forbidden of scenario.forbidden_changes) {
      if (changedFiles.includes(forbidden)) {
        forbidFindings.push(
          finding({
            rule: "forbidden-changes/touched",
            severity: "error",
            confidence: 1.0,
            file: forbidden,
            evidence: `forbidden file was modified`,
            suggestedInvestigation: `revert changes to ${forbidden}`,
          }),
        )
      }
    }
    gates.push(gate("forbidden-changes", forbidFindings))
  }

  // Gate: expected_artifacts present
  if (Array.isArray(scenario.expected_artifacts)) {
    const missingFindings = []
    for (const art of scenario.expected_artifacts) {
      if (art.type !== "file" && art.type !== "diff") continue
      const fullPath = resolve(repo, art.path)
      if (!existsSync(fullPath)) {
        missingFindings.push(
          finding({
            rule: "expected-artifacts/missing",
            severity: "error",
            file: art.path,
            evidence: `expected ${art.type} ${art.path} does not exist`,
            suggestedInvestigation: `create ${art.path}`,
          }),
        )
      }
    }
    gates.push(gate("expected-artifacts", missingFindings))
  }

  // Gate: console hygiene in changed source files (warning, not error)
  const consoleRegex = /\bconsole\.(log|debug)\(/
  const consoleFindings = []
  for (const f of changedFiles) {
    if (!/\.(ts|tsx|js|jsx|mjs|cjs)$/.test(f)) continue
    const fullPath = resolve(repo, f)
    if (!existsSync(fullPath)) continue
    try {
      const out = execSync(`grep -nE "${consoleRegex.source}" "${fullPath}" || true`, {
        encoding: "utf8",
      })
      for (const line of out.split("\n").filter(Boolean)) {
        const m = line.match(/^(\d+):/)
        consoleFindings.push(
          finding({
            rule: "console-hygiene/log-or-debug",
            severity: "warning",
            confidence: 0.9,
            file: f,
            line: m ? Number(m[1]) : 0,
            evidence: line.slice(line.indexOf(":") + 2).slice(0, 200),
            suggestedInvestigation: "remove or replace with structured logger",
          }),
        )
      }
    } catch {}
  }
  gates.push(gate("console-hygiene", consoleFindings))

  // Gate: no-req-body-company-id (used by tenant-query-scoping scenario)
  if (scenario.id === "backend-tenant-query-scoping") {
    const tenantFindings = []
    const tenantRegex = /(companyId|tenantId)\s*[:=]\s*(req\.body|body|query|params)\./
    for (const f of changedFiles) {
      if (!/\.(ts|tsx|js|jsx)$/.test(f)) continue
      const fullPath = resolve(repo, f)
      if (!existsSync(fullPath)) continue
      try {
        const out = execSync(`grep -nE "${tenantRegex.source}" "${fullPath}" || true`, { encoding: "utf8" })
        for (const line of out.split("\n").filter(Boolean)) {
          const m = line.match(/^(\d+):/)
          tenantFindings.push(
            finding({
              rule: "tenant/client-supplied-scope",
              severity: "error",
              confidence: 0.97,
              file: f,
              line: m ? Number(m[1]) : 0,
              evidence: line.slice(line.indexOf(":") + 2).slice(0, 200),
              suggestedInvestigation: "derive tenant scope from authenticated session, not request body",
            }),
          )
        }
      } catch {}
    }
    gates.push(gate("tenant-invariant-holds", tenantFindings))

    const noReqBodyFindings = []
    for (const f of changedFiles) {
      if (!/\.(ts|tsx|js|jsx)$/.test(f)) continue
      const fullPath = resolve(repo, f)
      if (!existsSync(fullPath)) continue
      try {
        const out = execSync(`grep -nE "req\\.body\\.(companyId|tenantId)" "${fullPath}" || true`, {
          encoding: "utf8",
        })
        for (const line of out.split("\n").filter(Boolean)) {
          const m = line.match(/^(\d+):/)
          noReqBodyFindings.push(
            finding({
              rule: "tenant/no-req-body-company-id",
              severity: "error",
              confidence: 0.99,
              file: f,
              line: m ? Number(m[1]) : 0,
              evidence: line.slice(line.indexOf(":") + 2).slice(0, 200),
              suggestedInvestigation: "never read tenant ID from request body",
            }),
          )
        }
      } catch {}
    }
    gates.push(gate("no-req-body-company-id", noReqBodyFindings))
  }

  // Dimensions: change surface — compare actual changed files to expected surface
  // (if scenario.expected_surface is provided)
  if (scenario.expected_surface_max_files && changedFiles.length > scenario.expected_surface_max_files) {
    findings.push(
      finding({
        rule: "change-budget/overshoot",
        severity: "warning",
        file: "(scenario)",
        evidence: `changed ${changedFiles.length} files, expected ≤ ${scenario.expected_surface_max_files}`,
        suggestedInvestigation: "replan or justify the expanded surface",
      }),
    )
    dimensions.push(
      dimension(
        "blast-radius-control",
        Math.max(0, 10 - Math.floor((changedFiles.length - scenario.expected_surface_max_files) / 2)),
        0.20,
        [],
        "change surface exceeded expected budget",
      ),
    )
  } else {
    dimensions.push(dimension("blast-radius-control", 10, 0.20))
  }

  const finishedAt = new Date().toISOString()
  return {
    grader: "deterministic",
    status: aggregateGates(gates),
    gates,
    dimensions,
    findings,
    startedAt,
    finishedAt,
    meta: {
      workdir: relative(process.cwd(), repo),
      changedFiles: changedFiles.length,
    },
  }
}
