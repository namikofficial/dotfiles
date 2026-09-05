// Smoke test for the agent-lab runner + graders.
// Runs a minimal scenario against the dotfiles repo itself as the workdir.
// Run: node configs/opencode/agent-lab/runners/__tests__/runner.test.mjs

import { test } from "node:test"
import assert from "node:assert/strict"
import { resolve, dirname } from "node:path"
import { fileURLToPath } from "node:url"
import { writeFileSync, mkdtempSync, mkdirSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

import { runScenario, runSuite } from "../opencode.mjs"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(__dirname, "../..") // agent-lab/
const SCENARIOS = resolve(ROOT, "scenarios")

test("deterministic grader flags console.log in changed file", async () => {
  const workdir = mkdtempSync(join(tmpdir(), "agent-lab-test-"))
  // Create a TypeScript file with console.log
  const fixturePath = join(workdir, "src/foo.ts")
  mkdirSync(join(workdir, "src"), { recursive: true })
  writeFileSync(fixturePath, 'console.log("hello")\nconst x = 1\n')

  // Use the shipment-table-redesign scenario for its scenario shape
  const scenarioPath = resolve(SCENARIOS, "ui/shipment-table-redesign.json")
  const { report } = await runScenario({
    scenarioPath,
    workdir,
    changedFiles: ["src/foo.ts"],
  })

  // We expect:
  // - forbidden-changes gate: PASS (no forbidden files modified)
  // - console-hygiene: WARNING (console.log found)
  const consoleGate = report.gates.find((g) => g.name === "console-hygiene")
  assert.ok(consoleGate, "console-hygiene gate should be present")
  assert.equal(consoleGate.status, "PASS", "warning-level findings do not fail the gate")
  const consoleFinding = consoleGate.findings.find((f) => f.file === "src/foo.ts")
  assert.ok(consoleFinding, "console.log should be flagged")
  assert.equal(consoleFinding.severity, "warning")
})

test("deterministic grader fails forbidden-changes when touched", async () => {
  const workdir = mkdtempSync(join(tmpdir(), "agent-lab-test-"))
  const scenarioPath = resolve(SCENARIOS, "ui/shipment-table-redesign.json")
  const { report } = await runScenario({
    scenarioPath,
    workdir,
    changedFiles: ["src/features/shipments/api.ts"], // this is in forbidden_changes
  })
  const forbidGate = report.gates.find((g) => g.name === "forbidden-changes")
  assert.ok(forbidGate)
  assert.equal(forbidGate.status, "FAIL")
})

test("deterministic grader flags req.body.companyId in tenant scenario", async () => {
  const workdir = mkdtempSync(join(tmpdir(), "agent-lab-test-"))
  mkdirSync(join(workdir, "src"), { recursive: true })
  const offender = join(workdir, "src/part-service.ts")
  writeFileSync(offender, "const scope = req.body.companyId;\n")

  const scenarioPath = resolve(SCENARIOS, "backend/tenant-query-scoping.json")
  const { report } = await runScenario({
    scenarioPath,
    workdir,
    changedFiles: ["src/part-service.ts"],
  })

  const noReqBodyGate = report.gates.find((g) => g.name === "no-req-body-company-id")
  assert.ok(noReqBodyGate)
  assert.equal(noReqBodyGate.status, "FAIL")
  assert.ok(
    noReqBodyGate.findings.some((f) => f.rule === "tenant/no-req-body-company-id"),
  )
})

test("runner produces a result file", async () => {
  const workdir = mkdtempSync(join(tmpdir(), "agent-lab-test-"))
  const scenarioPath = resolve(SCENARIOS, "ui/empty-state-recovery.json")
  const { resultPath } = await runScenario({
    scenarioPath,
    workdir,
    changedFiles: [],
  })
  assert.ok(existsSync(resultPath), `result file should exist at ${resultPath}`)
})

test("security grader reports PASS on empty repo (no findings = no violations)", async () => {
  const workdir = mkdtempSync(join(tmpdir(), "agent-lab-test-"))
  const scenarioPath = resolve(SCENARIOS, "backend/tenant-query-scoping.json")
  const { report } = await runScenario({
    scenarioPath,
    workdir,
    changedFiles: [],
  })
  const security = report.graderResults.find((r) => r.grader === "security")
  assert.ok(security)
  assert.equal(security.status, "PASS")
  assert.equal(security.meta.scripts >= 3, true, "should run ≥ 3 tenancy-invariants scripts")
})

test("security grader FAILS when scan-client-tenant-input finds violations", async () => {
  const workdir = mkdtempSync(join(tmpdir(), "agent-lab-test-"))
  mkdirSync(join(workdir, "src"), { recursive: true })
  writeFileSync(
    join(workdir, "src/bad.ts"),
    `app.post("/x", (req) => {
  const companyId = req.body.companyId
  return companyId
})
`,
  )
  const scenarioPath = resolve(SCENARIOS, "backend/tenant-query-scoping.json")
  const { report } = await runScenario({
    scenarioPath,
    workdir,
    changedFiles: ["src/bad.ts"],
  })
  const security = report.graderResults.find((r) => r.grader === "security")
  assert.ok(security)
  assert.equal(security.status, "FAIL")
  assert.ok(
    security.findings.some((f) => f.rule === "tenant/client-supplied-scope"),
  )
})

test("visual grader parses valid JSON response", async () => {
  const { parseVisualResponse } = await import("../../graders/visual/index.mjs")
  const scenario = {
    title: "test",
    domain: "ui",
    prompt: "test",
    dimensions: [{ name: "density", weight: 0.5 }, { name: "polish", weight: 0.5 }],
    hard_gates: [{ name: "no-console-errors" }],
  }
  const validJson = JSON.stringify({
    overall_status: "PASS",
    dimension_scores: [
      { name: "density", score: 8, rationale: "good" },
      { name: "polish", score: 7, rationale: "ok" },
    ],
    findings: [
      {
        rule: "density-test",
        severity: "warning",
        file: "test.png",
        evidence: "visible padding",
        suggestedInvestigation: "tighten",
        provenance: "OBSERVED",
      },
    ],
    summary: "looks good",
  })
  const result = parseVisualResponse(validJson, { scenario })
  assert.equal(result.status, "PASS")
  assert.equal(result.dimensions.length, 2)
  assert.equal(result.findings.length, 1)
})

test("runSuite runs multiple scenarios", async () => {
  const workdir = mkdtempSync(join(tmpdir(), "agent-lab-test-"))
  const scenarios = [
    resolve(SCENARIOS, "ui/empty-state-recovery.json"),
    resolve(SCENARIOS, "ui/form-validation-complete.json"),
  ]
  const reports = await runSuite({ scenarioPaths: scenarios, workdir })
  assert.equal(reports.length, 2)
})
