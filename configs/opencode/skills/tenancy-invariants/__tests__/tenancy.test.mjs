// Unit tests for tenancy-invariants scripts.
// Run: node configs/opencode/skills/tenancy-invariants/__tests__/tenancy.test.mjs

import { test } from "node:test"
import assert from "node:assert/strict"
import { execSync } from "node:child_process"
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const SCRIPTS = join(import.meta.dirname, "..", "scripts")

const runScript = (scriptName, workdir, args = []) => {
  try {
    const out = execSync(
      `node "${join(SCRIPTS, scriptName)}" --workdir "${workdir}" ${args.map((a) => `"${a}"`).join(" ")}`,
      { encoding: "utf8" },
    )
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

test("scan-client-tenant-input flags req.body.companyId", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  mkdirSync(join(workdir, "src"), { recursive: true })
  writeFileSync(
    join(workdir, "src/parts.ts"),
    `app.post("/parts", (req, res) => {
  const companyId = req.body.companyId
  return partRepo.find({ where: { companyId } })
})
`,
  )
  const { stdout, code } = runScript("scan-client-tenant-input.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.length > 0, "should flag req.body.companyId")
  assert.equal(findings[0].rule, "tenant/client-supplied-scope")
  assert.equal(findings[0].severity, "error")
  assert.equal(code, 1, "should exit non-zero on error-severity findings")
})

test("scan-client-tenant-input flags req.query.tenantId", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  mkdirSync(join(workdir, "src"), { recursive: true })
  writeFileSync(
    join(workdir, "src/list.ts"),
    `app.get("/list", (req) => req.query.tenantId ? getTenantData(req.query.tenantId) : null)
`,
  )
  const { stdout, code } = runScript("scan-client-tenant-input.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.length > 0)
  assert.equal(findings[0].rule, "tenant/client-supplied-scope")
  assert.equal(code, 1)
})

test("scan-client-tenant-input flags x-tenant-id header", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  writeFileSync(
    join(workdir, "x.ts"),
    `const tenantId = headers["x-tenant-id"]
`,
  )
  const { stdout } = runScript("scan-client-tenant-input.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.some((f) => f.rule === "tenant/client-supplied-header"))
})

test("scan-client-tenant-input allows trusted derivation", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  writeFileSync(
    join(workdir, "good.ts"),
    `app.get("/parts", (req) => {
  const companyId = req.context.session.companyId
  return partRepo.find({ where: { companyId } })
})
`,
  )
  const { stdout, code } = runScript("scan-client-tenant-input.mjs", workdir)
  assert.equal(stdout.trim(), "", "should not flag trusted session derivation")
  assert.equal(code, 0)
})

test("scan-unscoped-queries flags query builder without tenant scope", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  writeFileSync(
    join(workdir, "svc.ts"),
    `class PartService {
  async list() {
    const parts = await prisma.part.findMany()
    return parts
  }
}
`,
  )
  const { stdout } = runScript("scan-unscoped-queries.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.length > 0)
  assert.equal(findings[0].rule, "tenant/query-may-be-unscoped")
  assert.equal(findings[0].severity, "warning")
})

test("scan-unscoped-queries does NOT flag queries with companyId", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  writeFileSync(
    join(workdir, "svc.ts"),
    `class PartService {
  async list(companyId) {
    const parts = await prisma.part.findMany({ where: { companyId } })
    return parts
  }
}
`,
  )
  const { stdout } = runScript("scan-unscoped-queries.mjs", workdir)
  assert.equal(stdout.trim(), "")
})

test("scan-query-keys flags queryKey without tenant scope", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  writeFileSync(
    join(workdir, "q.ts"),
    `const { data } = useQuery({ queryKey: ["parts"], queryFn: fetchParts })
`,
  )
  const { stdout } = runScript("scan-query-keys.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.length > 0, "should flag queryKey without companyId")
  assert.equal(findings[0].rule, "tenant/query-key-missing-scope")
})

test("scan-query-keys allows queryKey with companyId", () => {
  const workdir = mkdtempSync(join(tmpdir(), "tenancy-test-"))
  writeFileSync(
    join(workdir, "q.ts"),
    `const { data } = useQuery({ queryKey: ["parts", companyId], queryFn: fetchParts })
`,
  )
  const { stdout } = runScript("scan-query-keys.mjs", workdir)
  assert.equal(stdout.trim(), "")
})
