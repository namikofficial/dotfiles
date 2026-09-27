import assert from "node:assert/strict"
import { test } from "node:test"
import { filterQuotaLayer } from "../quota-v2/command-filter.mjs"

test("quota layer keeps quota diagnostics and non-slash commands", () => {
  const keyboard = { id: "quota.refresh" }
  const layer = filterQuotaLayer({
    commands: [
      { id: "quota.main", slash: { name: "quota" } },
      { id: "quota.status", slash: { name: "quota_status" } },
      { id: "quota.tokens", slash: { name: "tokens_today" } },
      keyboard,
    ],
    bindings: [{ key: "ctrl+r", command: "quota.refresh" }],
  })

  assert.deepEqual(
    layer.commands
      .map((command) => command.slashName ?? command.slash?.name)
      .filter(Boolean),
    ["quota", "quota_status"],
  )
  assert.ok(layer.commands.includes(keyboard))
  assert.deepEqual(layer.bindings, [{ key: "ctrl+r", command: "quota.refresh" }])
})
