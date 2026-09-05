#!/usr/bin/env node
// scan-query-keys.mjs
//
// Detects TanStack Query / React Query keys that appear to be missing tenant
// scope. Heuristic: flags any queryKey whose array literal does NOT contain a
// variable matching /companyId|tenantId|workspaceId|orgId|accountId/.
//
// Scope: TS/JS source. False positives are expected; this is a warning-grade scan.

import { readFileSync, statSync } from "node:fs"
import { resolve, relative } from "node:path"
import { execSync } from "node:child_process"

const args = parseArgs(process.argv.slice(2))
const workdir = resolve(args.workdir ?? process.cwd())
const changedFiles = args["changed-files"] ?? []

const QUERY_KEY_PATTERN = /queryKey\s*:\s*\[([^\]]*)\]/
const SCOPE_VAR_PATTERN = /\b(companyId|tenantId|workspaceId|orgId|accountId)\b/

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
      `find "${workdir}" -type f \\( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \\) ` +
        `-not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*'`,
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
    const m = lines[i].match(QUERY_KEY_PATTERN)
    if (!m) continue

    // Multi-line queryKey (open bracket on this line, close on later)
    let keyBody = m[1]
    if (keyBody.includes("\n") === false && lines[i].includes("]") === false) {
      // open on this line, collect until we see ]
      let collected = keyBody
      let j = i + 1
      while (j < lines.length && !lines[j].includes("]")) {
        collected += "\n" + lines[j]
        j++
      }
      if (j < lines.length) {
        collected += "\n" + lines[j]
        keyBody = collected
      }
    }

    // Skip if the queryKey contains a scope variable
    if (SCOPE_VAR_PATTERN.test(keyBody)) continue

    findings.push({
      rule: "tenant/query-key-missing-scope",
      severity: "warning",
      confidence: 0.7,
      file: relative(workdir, file),
      line: i + 1,
      symbol: "(useQuery / useMutation)",
      evidence: lines[i].trim().slice(0, 200),
      suggestedInvestigation:
        "verify the queryKey includes a tenant identifier (companyId/tenantId/workspaceId/orgId/accountId)",
    })
  }
  return findings
}

const files = getFiles(workdir, changedFiles)
let count = 0
for (const f of files) {
  try {
    statSync(f)
  } catch {
    continue
  }
  for (const finding of scanFile(f)) {
    console.log(JSON.stringify(finding))
    count++
  }
}
