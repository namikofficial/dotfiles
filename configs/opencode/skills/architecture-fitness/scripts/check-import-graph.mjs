#!/usr/bin/env node
// check-import-graph.mjs
//
// Enforces monorepo import-graph rules. Emits JSON lines on stdout.
//
// Built-in rules (override via configs/engineering/architecture-fitness.yaml):
//   - apps/<a>/** must not import apps/<b>/**
//   - apps/<*>/src/domain/** must not import framework packages
//   - shared/** must not import apps/**
//
// Usage:
//   node check-import-graph.mjs --workdir <path>

import { readFileSync, statSync, existsSync } from "node:fs"
import { resolve, relative } from "node:path"
import { execSync } from "node:child_process"

const args = parseArgs(process.argv.slice(2))
const workdir = resolve(args.workdir ?? process.cwd())

const FRAMEWORK_PACKAGES = [
  "fastify",
  "express",
  "koa",
  "hapi",
  "@nestjs/core",
  "@nestjs/common",
  "@tanstack/react-query",
  "react-router-dom",
  "next",
  "gatsby",
  "@sveltejs/kit",
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

function loadRules() {
  const configPath = resolve(workdir, "configs/engineering/architecture-fitness.yaml")
  if (!existsSync(configPath)) return { deny: [] }
  try {
    const text = readFileSync(configPath, "utf8")
    // Minimal YAML-ish parser: extract the deny array. Production should use a real parser.
    const rules = []
    const lines = text.split("\n")
    let inDeny = false
    let current = null
    for (const line of lines) {
      if (/^deny:/.test(line)) {
        inDeny = true
        continue
      }
      if (inDeny && /^[^ -]/.test(line) && !/^  /.test(line)) {
        inDeny = false
      }
      if (!inDeny) continue
      const m = line.match(/^\s+-\s+from:\s*"?([^"]+)"?/)
      if (m) {
        if (current) rules.push(current)
        current = { from: m[1].trim(), import: "", reason: "" }
        continue
      }
      const im = line.match(/^\s+import:\s*"?([^"]+)"?/)
      if (im && current) current.import = im[1].trim()
      const rm = line.match(/^\s+reason:\s*"?(.+)"?/)
      if (rm && current) current.reason = rm[1].trim()
    }
    if (current) rules.push(current)
    return { deny: rules }
  } catch {
    return { deny: [] }
  }
}

const RULES = loadRules()

function globToRegex(glob) {
  // Convert a simple glob like "apps/*/src/domain/**" to a RegExp
  const re = glob
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*\*/g, ".*")
    .replace(/\*/g, "[^/]+")
  return new RegExp(`^${re}/`)
}

function getFiles(workdir) {
  try {
    const out = execSync(
      `find "${workdir}" -type f \\( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \\) ` +
        `-not -path '*/node_modules/*' -not -path '*/dist/*' -not -path '*/build/*' -not -path '*/.next/*' -not -path '*/target/*'`,
      { encoding: "utf8" },
    )
    return out.split("\n").filter(Boolean).map((f) => resolve(workdir, f))
  } catch {
    return []
  }
}

const IMPORT_REGEX = /(?:from\s+['"`]([^'"`]+)['""]|require\s*\(\s*['"`]([^'"`]+)['"`]\s*\))/

function scanFile(file) {
  let text
  try {
    text = readFileSync(file, "utf8")
  } catch {
    return []
  }
  const lines = text.split("\n")
  const relFile = relative(workdir, file)
  const findings = []

  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(IMPORT_REGEX)
    if (!m) continue
    const importPath = m[1] || m[2]
    if (!importPath) continue

    // Built-in rule: apps/<a> importing apps/<b>
    const appMatch = relFile.match(/^apps\/([^/]+)\//)
    if (appMatch) {
      const otherApp = importPath.match(/^apps\/([^/]+)\//)
      if (otherApp && otherApp[1] !== appMatch[1]) {
        findings.push({
          rule: "arch/apps-cross-import",
          severity: "error",
          confidence: 0.99,
          file: relFile,
          line: i + 1,
          symbol: "(import)",
          evidence: `importing "${importPath}" from apps/${otherApp[1]}`,
          suggestedInvestigation: "move shared code to shared/ packages",
        })
      }
    }

    // Built-in rule: domain layer not importing framework
    if (/^apps\/[^/]+\/src\/domain\//.test(relFile)) {
      for (const fw of FRAMEWORK_PACKAGES) {
        if (importPath === fw || importPath.startsWith(fw + "/")) {
          findings.push({
            rule: "arch/domain-imports-framework",
            severity: "error",
            confidence: 0.95,
            file: relFile,
            line: i + 1,
            symbol: "(import)",
            evidence: `domain layer imports framework "${fw}"`,
            suggestedInvestigation: "isolate framework code in an adapter or infrastructure layer",
          })
        }
      }
    }

    // Built-in rule: shared importing apps
    if (/^shared\//.test(relFile)) {
      if (/^apps\//.test(importPath)) {
        findings.push({
          rule: "arch/shared-imports-apps",
          severity: "error",
          confidence: 0.99,
          file: relFile,
          line: i + 1,
          symbol: "(import)",
          evidence: `shared package imports "${importPath}"`,
          suggestedInvestigation: "shared packages must not depend on apps",
        })
      }
    }

    // Custom rules from configs/engineering/architecture-fitness.yaml
    for (const rule of RULES.deny) {
      if (!rule.import) continue
      const fromRe = globToRegex(rule.from)
      if (fromRe.test(relFile)) {
        const importRe = globToRegex(rule.import)
        if (importRe.test(importPath)) {
          findings.push({
            rule: `arch/custom/${rule.from}/${rule.import}`,
            severity: "error",
            confidence: 0.95,
            file: relFile,
            line: i + 1,
            symbol: "(import)",
            evidence: `"${rule.from}" imports "${rule.import}" — ${rule.reason}`,
            suggestedInvestigation: rule.reason,
          })
        }
      }
    }
  }
  return findings
}

const files = getFiles(workdir)
let errorCount = 0
for (const f of files) {
  try {
    statSync(f)
  } catch {
    continue
  }
  for (const finding of scanFile(f)) {
    console.log(JSON.stringify(finding))
    if (finding.severity === "error") errorCount++
  }
}

if (errorCount > 0) process.exit(1)
