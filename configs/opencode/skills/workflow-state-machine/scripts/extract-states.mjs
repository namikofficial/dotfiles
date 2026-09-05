#!/usr/bin/env node
// extract-states.mjs
//
// Finds fields whose name suggests a workflow state (status, state, phase,
// step, stage) in TypeScript source and emits one finding per file/entity.
//
// Usage:
//   node extract-states.mjs --workdir <path> [--changed-files f1 f2 ...]

import { readFileSync, statSync } from "node:fs"
import { resolve, relative } from "node:path"
import { execSync } from "node:child_process"

const args = parseArgs(process.argv.slice(2))
const workdir = resolve(args.workdir ?? process.cwd())
const changedFiles = args["changed-files"] ?? []

const FIELD_PATTERNS = [
  /\bstatus\??\s*:\s*['"`]?(\w+)['"`]?/,
  /\bstate\??\s*:\s*['"`]?(\w+)['"`]?/,
  /\bphase\??\s*:\s*['"`]?(\w+)['"`]?/,
  /\bstep\??\s*:\s*['"`]?(\w+)['"`]?/,
  /\bstage\??\s*:\s*['"`]?(\w+)['"`]?/,
]

const TYPE_PATTERNS = [
  /\btype\s+(\w+State)\b/,
  /\btype\s+(\w+Status)\b/,
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

function getFiles(workdir, changedFiles) {
  if (changedFiles.length) {
    return changedFiles.map((f) => resolve(workdir, f))
  }
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

function scanFile(file) {
  let text
  try {
    text = readFileSync(file, "utf8")
  } catch {
    return []
  }
  const lines = text.split("\n")
  const findings = []
  for (let i = 0; i < lines.length; i++) {
    for (const p of FIELD_PATTERNS) {
      const m = lines[i].match(p)
      if (m) {
        findings.push({
          rule: "state-machine/field-found",
          severity: "advisory",
          confidence: 0.85,
          file: relative(workdir, file),
          line: i + 1,
          symbol: extractEntityName(file, lines),
          evidence: lines[i].trim().slice(0, 200),
          suggestedInvestigation:
            "verify this state field has an explicit state machine in a single transition function",
          meta: { field: "state", value: m[1] },
        })
        break
      }
    }
    for (const p of TYPE_PATTERNS) {
      const m = lines[i].match(p)
      if (m) {
        findings.push({
          rule: "state-machine/type-found",
          severity: "advisory",
          confidence: 0.9,
          file: relative(workdir, file),
          line: i + 1,
          symbol: m[1],
          evidence: lines[i].trim().slice(0, 200),
          suggestedInvestigation:
            "verify this state type has a corresponding TRANSITIONS map",
        })
      }
    }
  }
  return findings
}

function extractEntityName(file, lines) {
  // Try to find the surrounding interface/type/class name
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(/(?:interface|class|type)\s+(\w+)/)
    if (m) return m[1]
  }
  return ""
}

const files = getFiles(workdir, changedFiles)
for (const f of files) {
  try {
    statSync(f)
  } catch {
    continue
  }
  for (const finding of scanFile(f)) {
    console.log(JSON.stringify(finding))
  }
}
