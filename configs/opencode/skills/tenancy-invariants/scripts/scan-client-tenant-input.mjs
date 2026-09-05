#!/usr/bin/env node
// scan-client-tenant-input.mjs
//
// Detects client-supplied tenant identifiers being used as authorization scope.
// Emits JSON lines on stdout, one finding per line.
//
// Flags patterns like:
//   - req.body.companyId / req.body.tenantId / req.body.workspaceId
//   - req.query.tenant / req.query.company
//   - req.params.tenantId
//   - headers["x-tenant-id"] without an admin capability check
//
// Usage:
//   node scan-client-tenant-input.mjs --workdir <path> [--changed-files f1 f2 ...]
//   cat result.json | jq -r '. | select(.severity == "error")'

import { readFileSync, statSync } from "node:fs"
import { resolve, relative, join } from "node:path"
import { execSync } from "node:child_process"

const args = parseArgs(process.argv.slice(2))
const workdir = resolve(args.workdir ?? process.cwd())
const changedFiles = args["changed-files"] ?? []
const grepOnly = args["grep-only"] === true || args["grep-only"] === "true"

const TENANT_KEYS = [
  "companyId",
  "company_id",
  "tenantId",
  "tenant_id",
  "workspaceId",
  "workspace_id",
  "orgId",
  "org_id",
  "accountId",
  "account_id",
]

const PATTERNS = [
  // req.body.<tenant-key>
  ...TENANT_KEYS.map((k) => ({
    rule: "tenant/client-supplied-scope",
    pattern: new RegExp(`\\breq\\.body\\.${escapeRe(k)}\\b`),
    severity: "error",
    confidence: 0.97,
    suggested: "derive tenant scope from authenticated session",
  })),
  // req.query.<tenant-key>
  ...TENANT_KEYS.map((k) => ({
    rule: "tenant/client-supplied-scope",
    pattern: new RegExp(`\\breq\\.query\\.${escapeRe(k)}\\b`),
    severity: "error",
    confidence: 0.95,
    suggested: "derive tenant scope from authenticated session",
  })),
  // req.params.<tenant-key>
  ...TENANT_KEYS.map((k) => ({
    rule: "tenant/client-supplied-scope",
    pattern: new RegExp(`\\breq\\.params\\.${escapeRe(k)}\\b`),
    severity: "warning",
    confidence: 0.85,
    suggested: "verify tenant scope derivation before using path params as authorization",
  })),
  // headers["x-tenant-id"] / headers["x-company-id"]
  {
    rule: "tenant/client-supplied-header",
    pattern: /\bheaders?\[["'`](?:x-tenant-id|x-company-id|x-workspace-id|x-org-id)["'`]\]/i,
    severity: "warning",
    confidence: 0.85,
    suggested: "verify this is an admin/impersonation flow gated by capability",
  },
  // body.tenant / query.tenant (short form)
  ...TENANT_KEYS.map((k) => ({
    rule: "tenant/client-supplied-scope",
    pattern: new RegExp(`\\b(?:body|query|params)\\s*\\.\\s*['"\`]${escapeRe(k)}['"\`]`, "i"),
    severity: "warning",
    confidence: 0.7,
    suggested: "consider whether this is trusted input",
  })),
]

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function parseArgs(argv) {
  const result = {}
  const positional = []
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
    } else {
      positional.push(a)
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
        `-not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.next/*'`,
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
    const line = lines[i]
    // Skip commented-out code? No — agents often "comment out" violations. Scan everything.
    for (const p of PATTERNS) {
      if (p.pattern.test(line)) {
        findings.push({
          rule: p.rule,
          severity: p.severity,
          confidence: p.confidence,
          file: relative(workdir, file),
          line: i + 1,
          symbol: extractSymbol(file, i, lines),
          evidence: line.trim().slice(0, 200),
          suggestedInvestigation: p.suggested,
        })
      }
    }
  }
  return findings
}

function extractSymbol(file, lineIdx, lines) {
  // Walk back to find the enclosing function/declaration
  for (let i = lineIdx; i >= Math.max(0, lineIdx - 50); i--) {
    const m = lines[i].match(/(?:async\s+)?(?:function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=|(\w+)\s*\([^)]*\)\s*\{)/)
    if (m) return m[1] || m[2] || m[3] || ""
  }
  return ""
}

const files = getFiles(workdir, changedFiles)
let total = 0
const bySeverity = { error: 0, warning: 0, advisory: 0 }
for (const f of files) {
  try {
    statSync(f)
  } catch {
    continue
  }
  for (const finding of scanFile(f)) {
    console.log(JSON.stringify(finding))
    total++
    bySeverity[finding.severity]++
  }
}

// Exit code: 0 if no errors, 1 if any error-severity findings (so CI can block).
if (bySeverity.error > 0) process.exit(1)
