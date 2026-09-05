// OpenCode runner — executes a scenario against a configured OpenCode agent.
//
// In a fully wired environment, this would call OpenCode's headless mode with the
// scenario.prompt as the user request and the scenario's fixture as the working
// directory. For now, the runner is a pipeline orchestrator that:
//
//  1. Loads the scenario JSON
//  2. Validates it against fixtures/scenario.schema.json
//  3. Resolves the workdir
//  4. Runs each grader in sequence
//  5. Aggregates results into a single GraderReport
//  6. Writes the report to results/runs/<timestamp>-<scenario-id>.json

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs"
import { resolve, basename, dirname, join } from "node:path"
import { fileURLToPath } from "node:url"
import { execSync } from "node:child_process"

import { runDeterministicGrader } from "../graders/deterministic/index.mjs"
import { runBrowserGrader } from "../graders/browser/index.mjs"
import { runSecurityGrader } from "../graders/security/index.mjs"
import { parseVisualResponse, buildVisualPrompt } from "../graders/visual/index.mjs"
import { parseLlmResponse, buildLlmPrompt } from "../graders/llm/index.mjs"
import { aggregateDimensions, aggregateGates, dimension, finding, gate } from "../graders/types.mjs"

const __dirname = dirname(fileURLToPath(import.meta.url))
const ROOT = resolve(__dirname, "..")
const RESULTS_DIR = resolve(ROOT, "results/runs")

/**
 * Run a scenario against a workdir with optional pre-captured browser evidence.
 *
 * @param {Object} args
 * @param {string} args.scenarioPath        - absolute path to the scenario JSON
 * @param {string} args.workdir             - absolute path to the repo under test
 * @param {string[]} [args.changedFiles]    - relative file paths changed by the agent
 * @param {Object} [args.browserEvidence]   - { screenshots, console, network }
 * @param {Object} [args.visualResponse]    - pre-computed JSON response from vision agent
 * @param {Object} [args.llmResponse]       - pre-computed JSON response from LLM grader
 * @returns {Promise<Object>} the aggregated GraderReport
 */
export async function runScenario({
  scenarioPath,
  workdir,
  changedFiles = [],
  browserEvidence,
  visualResponse,
  llmResponse,
}) {
  const scenario = JSON.parse(readFileSync(scenarioPath, "utf8"))

  const startedAt = new Date().toISOString()

  // Run deterministic + security graders first (these are pure code analysis)
  const [deterministicResult, securityResult] = await Promise.all([
    runDeterministicGrader({ scenario, workdir, changedFiles }),
    runSecurityGrader({ workdir, scenario }),
  ])

  // Browser grader — needs pre-captured evidence (produced by the agent that ran the eval)
  const browserResult = await runBrowserGrader({
    scenario,
    screenshots: browserEvidence?.screenshots ?? [],
    console: browserEvidence?.console ?? [],
    network: browserEvidence?.network ?? [],
  })

  // Visual grader — needs pre-computed vision agent response
  const visualResult = visualResponse
    ? parseVisualResponse(visualResponse, { scenario })
    : {
        grader: "visual",
        status: "INCOMPLETE",
        gates: [],
        dimensions: [],
        findings: [],
        startedAt: new Date().toISOString(),
        finishedAt: new Date().toISOString(),
        meta: { skipped: "no visual response provided" },
      }

  // LLM grader — needs pre-computed LLM response
  const llmResult = llmResponse
    ? parseLlmResponse(llmResponse, { scenario })
    : {
        grader: "llm",
        status: "INCOMPLETE",
        gates: [],
        dimensions: [],
        findings: [],
        startedAt: new Date().toISOString(),
        finishedAt: new Date().toISOString(),
        meta: { skipped: "no llm response provided" },
      }

  // Aggregate
  const allResults = [deterministicResult, securityResult, browserResult, visualResult, llmResult]
  const allGates = allResults.flatMap((r) => r.gates)
  const allDimensions = allResults.flatMap((r) => r.dimensions)
  const allFindings = allResults.flatMap((r) => r.findings)
  const overallStatus = aggregateGates(allGates)
  const overallScore = aggregateDimensions(allDimensions)

  const report = {
    scenario: { id: scenario.id, title: scenario.title, domain: scenario.domain },
    workdir,
    changedFiles,
    startedAt,
    finishedAt: new Date().toISOString(),
    overallStatus,
    overallScore,
    graderResults: allResults,
    gates: allGates,
    dimensions: allDimensions,
    findings: allFindings,
  }

  // Persist
  if (!existsSync(RESULTS_DIR)) mkdirSync(RESULTS_DIR, { recursive: true })
  const ts = startedAt.replace(/[:.]/g, "-")
  const resultPath = join(RESULTS_DIR, `${ts}-${scenario.id}.json`)
  writeFileSync(resultPath, JSON.stringify(report, null, 2))

  return { report, resultPath }
}

/**
 * Run multiple scenarios in sequence.
 */
export async function runSuite({ scenarioPaths, workdir, options = {} }) {
  const reports = []
  for (const sp of scenarioPaths) {
    const { report, resultPath } = await runScenario({
      scenarioPath: sp,
      workdir,
      ...options,
    })
    reports.push({ scenario: sp, report, resultPath })
  }
  return reports
}

/**
 * Run from CLI: `node runners/opencode.ts <scenario.json> <workdir> [--baseline]`
 */
const isMain = (() => {
  try {
    return fileURLToPath(import.meta.url) === process.argv[1]
  } catch {
    return false
  }
})()

if (isMain) {
  const [, , scenarioPath, workdir, ...rest] = process.argv
  if (!scenarioPath || !workdir) {
    console.error("Usage: node runners/opencode.mjs <scenario.json> <workdir> [--baseline]")
    process.exit(2)
  }
  const baseline = rest.includes("--baseline")
  const { report, resultPath } = await runScenario({
    scenarioPath: resolve(scenarioPath),
    workdir: resolve(workdir),
  })
  console.log(`Scenario: ${report.scenario.id}`)
  console.log(`Status:   ${report.overallStatus}`)
  console.log(`Score:    ${report.overallScore}/100`)
  console.log(`Gates:    ${report.gates.map((g) => `${g.name}=${g.status}`).join(", ") || "(none)"}`)
  console.log(`Report:   ${resultPath}`)
  if (baseline) {
    const baselinePath = resolve(ROOT, `results/baseline/${report.scenario.id}.json`)
    writeFileSync(baselinePath, JSON.stringify(report, null, 2))
    console.log(`Baseline: ${baselinePath}`)
  }
}
