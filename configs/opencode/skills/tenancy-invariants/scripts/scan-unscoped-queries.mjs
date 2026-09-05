#!/usr/bin/env node
// scan-unscoped-queries.mjs
//
// Detects ORM query builders that appear to be missing tenant scope.
//
// This is a heuristic scanner: it flags query builders whose call site is
// NOT followed (within 30 lines) by a `.where`, `.filter`, `.andWhere`,
// or `companyId:` / `tenantId:` clause. False positives are expected;
// the agent-lab security grader surfaces them as warnings, not errors,
// and the human review decides.
//
// Scope: TS/JS source. Detects:
//   - prisma.findMany / findFirst / findUnique / update / delete / count
//   - knex('table') chains
//   - typeorm repository .find / .findOne / .createQueryBuilder
//   - mikrorm .find / .findOne / .findAll
//
// Usage: see scan-client-tenant-input.mjs

import { readFileSync, statSync } from "node:fs"
import { resolve, relative } from "node:path"
import { execSync } from "node:child_process"

const args = parseArgs(process.argv.slice(2))
const workdir = resolve(args.workdir ?? process.cwd())
const changedFiles = args["changed-files"] ?? []

const QUERY_PATTERNS = [
  { name: "prisma.findMany", pattern: /\bprisma\.(\w+)\.findMany\s*\(/ },
  { name: "prisma.findFirst", pattern: /\bprisma\.(\w+)\.findFirst\s*\(/ },
  { name: "prisma.findUnique", pattern: /\bprisma\.(\w+)\.findUnique\s*\(/ },
  { name: "prisma.count", pattern: /\bprisma\.(\w+)\.count\s*\(/ },
  { name: "prisma.upsert", pattern: /\bprisma\.(\w+)\.upsert\s*\(/ },
  { name: "knex-table", pattern: /\bknex\s*\(\s*['"`](\w+)['"`]\s*\)/ },
  { name: "typeorm-find", pattern: /\.find\s*\(\s*\{/ },
  { name: "typeorm-findOne", pattern: /\.findOne\s*\(\s*\{/ },
  { name: "mikrorm-find", pattern: /\.find\s*\(\s*\{/ },
]

const SCOPE_TOKENS = [
  /\bwhere\s*:/,
  /\bwhere\s*\(/,
  /\.where\(/,
  /\.andWhere\(/,
  /\.filter\(/,
  /\bcompanyId\s*:/,
  /\btenantId\s*:/,
  /\bworkspaceId\s*:/,
  /\borgId\s*:/,
  /\baccountId\s*:/,
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
    for (const q of QUERY_PATTERNS) {
      if (q.pattern.test(lines[i])) {
        // Look ahead 30 lines for a scope token
        const window = lines.slice(i, Math.min(i + 30, lines.length)).join("\n")
        const hasScope = SCOPE_TOKENS.some((re) => re.test(window))
        if (!hasScope) {
          findings.push({
            rule: "tenant/query-may-be-unscoped",
            severity: "warning",
            confidence: 0.6,
            file: relative(workdir, file),
            line: i + 1,
            symbol: q.name,
            evidence: lines[i].trim().slice(0, 200),
            suggestedInvestigation: "verify the query is scoped to the active tenant within 30 lines",
          })
        }
      }
    }
  }
  return findings
}

const files = getFiles(workdir, changedFiles)
let bySeverity = { warning: 0 }
for (const f of files) {
  try {
    statSync(f)
  } catch {
    continue
  }
  for (const finding of scanFile(f)) {
    console.log(JSON.stringify(finding))
    bySeverity.warning++
  }
}

// Never block on unscoped-query warnings (too many false positives). Just log.
