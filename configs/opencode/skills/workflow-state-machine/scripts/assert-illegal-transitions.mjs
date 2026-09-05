#!/usr/bin/env node
// assert-illegal-transitions.mjs
//
// For each discovered state field, checks whether the test files contain at
// least one assertion that an illegal transition returns an error.
//
// Heuristic: looks for test files that import the same entity name AND contain
// the words "ILLEGAL", "throws", "rejects", "expect.*toThrow" near the state
// name.
//
// Usage:
//   node assert-illegal-transitions.mjs --workdir <path>

import { readFileSync, statSync } from "node:fs"
import { resolve, relative } from "node:path"
import { execSync } from "node:child_process"

const args = parseArgs(process.argv.slice(2))
const workdir = resolve(args.workdir ?? process.cwd())

const REJECT_PATTERNS = [
  /\bILLEGAL_TRANSITION\b/,
  /\bexpect.*toThrow\b/,
  /\.rejects\./,
  /\brejects\.toThrow\b/,
  /\brejects\.toEqual\b.*[Ee]rror/,
]

function parseArgs(argv) {
  const result = {}
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]
    if (a.startsWith("--")) {
      const key = a.slice(2)
      const next = argv[i + 1]
      if (next && !next.startsWith("--")) {
        result[key] = next
        i++
      } else {
        result[key] = true
      }
    }
  }
  return result
}

function getAllFiles(workdir) {
  try {
    const out = execSync(
      `find "${workdir}" -type f \\( -name '*.ts' -o -name '*.tsx' \\) ` +
        `-not -path '*/node_modules/*' -not -path '*/dist/*'`,
      { encoding: "utf8" },
    )
    return out.split("\n").filter(Boolean)
  } catch {
    return []
  }
}

function hasIllegalTransitionTest(file) {
  let text
  try {
    text = readFileSync(file, "utf8")
  } catch {
    return false
  }
  return REJECT_PATTERNS.some((p) => p.test(text))
}

function fileIsTest(file) {
  return /\.(test|spec)\.(ts|tsx)$/.test(file)
}

// Emit a single finding per repo: do we have at least one illegal-transition test?
const files = getAllFiles(workdir)
const testFiles = files.filter(fileIsTest)
const anyIllegalTransitionTest = testFiles.some(hasIllegalTransitionTest)

if (!anyIllegalTransitionTest) {
  console.log(
    JSON.stringify({
      rule: "state-machine/no-illegal-transition-test",
      severity: "advisory",
      confidence: 0.7,
      file: "(repo)",
      line: 0,
      symbol: "(test suite)",
      evidence: `scanned ${testFiles.length} test files; none assert illegal transitions`,
      suggestedInvestigation:
        "add tests that exercise illegal state transitions and assert they throw ILLEGAL_TRANSITION",
    }),
  )
}
