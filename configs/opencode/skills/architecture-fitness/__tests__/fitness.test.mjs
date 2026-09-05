// Tests for architecture-fitness check-import-graph.mjs
// Run: node configs/opencode/skills/architecture-fitness/__tests__/fitness.test.mjs

import { test } from "node:test"
import assert from "node:assert/strict"
import { execSync } from "node:child_process"
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const SCRIPT = join(import.meta.dirname, "..", "scripts", "check-import-graph.mjs")

const runScript = (workdir) => {
  try {
    const out = execSync(`node "${SCRIPT}" --workdir "${workdir}"`, { encoding: "utf8" })
    return { stdout: out, code: 0 }
  } catch (e) {
    return { stdout: e.stdout?.toString() ?? "", code: e.status ?? 1 }
  }
}

const parseLines = (stdout) =>
  stdout
    .split("\n")
    .filter(Boolean)
    .map((l) => JSON.parse(l))

test("flags app-a importing app-b", () => {
  const workdir = mkdtempSync(join(tmpdir(), "fit-test-"))
  mkdirSync(join(workdir, "apps/web/src"), { recursive: true })
  mkdirSync(join(workdir, "apps/api/src"), { recursive: true })
  writeFileSync(
    join(workdir, "apps/web/src/foo.ts"),
    `import { helper } from "apps/api/src/helper"
`,
  )
  const { stdout, code } = runScript(workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.some((f) => f.rule === "arch/apps-cross-import"))
  assert.equal(code, 1)
})

test("allows app importing its own subpath", () => {
  const workdir = mkdtempSync(join(tmpdir(), "fit-test-"))
  mkdirSync(join(workdir, "apps/web/src"), { recursive: true })
  writeFileSync(
    join(workdir, "apps/web/src/foo.ts"),
    `import { helper } from "./helper"
`,
  )
  const { stdout, code } = runScript(workdir)
  assert.equal(stdout.trim(), "")
  assert.equal(code, 0)
})

test("flags domain importing framework", () => {
  const workdir = mkdtempSync(join(tmpdir(), "fit-test-"))
  mkdirSync(join(workdir, "apps/web/src/domain"), { recursive: true })
  writeFileSync(
    join(workdir, "apps/web/src/domain/part.ts"),
    `import { FastifyInstance } from "fastify"
`,
  )
  const { stdout } = runScript(workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.some((f) => f.rule === "arch/domain-imports-framework"))
})

test("flags shared importing apps", () => {
  const workdir = mkdtempSync(join(tmpdir(), "fit-test-"))
  mkdirSync(join(workdir, "shared/utils/src"), { recursive: true })
  mkdirSync(join(workdir, "apps/web/src"), { recursive: true })
  writeFileSync(
    join(workdir, "shared/utils/src/index.ts"),
    `import { something } from "apps/web/src/whatever"
`,
  )
  const { stdout } = runScript(workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.some((f) => f.rule === "arch/shared-imports-apps"))
})

test("empty repo produces no findings", () => {
  const workdir = mkdtempSync(join(tmpdir(), "fit-test-"))
  const { stdout, code } = runScript(workdir)
  assert.equal(stdout.trim(), "")
  assert.equal(code, 0)
})
