#!/usr/bin/env node
// Tiny smoke test for workflow-state-machine scripts.
// Run: node configs/opencode/skills/workflow-state-machine/__tests__/state-machine.test.mjs

import { test } from "node:test"
import assert from "node:assert/strict"
import { execSync } from "node:child_process"
import { mkdtempSync, writeFileSync, mkdirSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const SCRIPTS = join(import.meta.dirname, "..", "scripts")

const runScript = (scriptName, workdir) => {
  try {
    const out = execSync(`node "${join(SCRIPTS, scriptName)}" --workdir "${workdir}"`, {
      encoding: "utf8",
    })
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

test("extract-states finds status field", () => {
  const workdir = mkdtempSync(join(tmpdir(), "sm-test-"))
  mkdirSync(join(workdir, "src"), { recursive: true })
  writeFileSync(
    join(workdir, "src/shipment.ts"),
    `interface Shipment {
  id: string
  status: ShipmentState
  state?: string
}
`,
  )
  const { stdout } = runScript("extract-states.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.length >= 1, "should find status field")
  assert.equal(findings[0].rule, "state-machine/field-found")
})

test("extract-states finds ShipmentState type", () => {
  const workdir = mkdtempSync(join(tmpdir(), "sm-test-"))
  writeFileSync(
    join(workdir, "types.ts"),
    `export type ShipmentState = "DRAFT" | "IN_TRANSIT" | "RECEIVED"
`,
  )
  const { stdout } = runScript("extract-states.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.some((f) => f.rule === "state-machine/type-found"))
})

test("assert-illegal-transitions flags repos with no illegal-transition tests", () => {
  const workdir = mkdtempSync(join(tmpdir(), "sm-test-"))
  mkdirSync(join(workdir, "tests"), { recursive: true })
  writeFileSync(
    join(workdir, "tests/foo.test.ts"),
    `test("smoke", () => { expect(1).toBe(1) })
`,
  )
  const { stdout } = runScript("assert-illegal-transitions.mjs", workdir)
  const findings = parseLines(stdout)
  assert.ok(findings.length > 0, "should flag missing illegal-transition tests")
  assert.equal(findings[0].rule, "state-machine/no-illegal-transition-test")
})

test("assert-illegal-transitions is silent when illegal-transition tests exist", () => {
  const workdir = mkdtempSync(join(tmpdir(), "sm-test-"))
  mkdirSync(join(workdir, "tests"), { recursive: true })
  writeFileSync(
    join(workdir, "tests/shipment.test.ts"),
    `test("rejects illegal transition", async () => {
  await expect(transition(s, "COMPLETED")).rejects.toThrow("ILLEGAL_TRANSITION")
})
`,
  )
  const { stdout } = runScript("assert-illegal-transitions.mjs", workdir)
  assert.equal(stdout.trim(), "", "should not flag when illegal-transition tests exist")
})
