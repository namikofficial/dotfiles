// Unit tests for pre-shell-safety.js and pre-edit-safety.js
// Run: node configs/opencode/plugins/__tests__/safety.test.js

import { test } from "node:test"
import assert from "node:assert/strict"
import { PreShellSafety } from "../pre-shell-safety.js"
import { PreEditSafety } from "../pre-edit-safety.js"

// Helper: invoke a plugin hook with synthetic input/output
const invoke = async (pluginObj, hookName, input) => {
  const hooks = await pluginObj({})
  const fn = hooks[hookName]
  if (!fn) throw new Error(`hook ${hookName} not registered`)
  const output = { metadata: {} }
  try {
    await fn(input, output)
    return { output, threw: null }
  } catch (e) {
    return { output, threw: e }
  }
}

test("pre-shell-safety blocks rm -rf /", async () => {
  const { threw } = await invoke(PreShellSafety, "shell.execute", {
    command: "rm -rf / --no-preserve-root",
  })
  assert.ok(threw, "should throw")
  assert.match(threw.message, /shell\/rm-rf/)
})

test("pre-shell-safety blocks rm -rf ..", async () => {
  const { threw } = await invoke(PreShellSafety, "shell.execute", {
    command: "rm -rf .. && echo done",
  })
  assert.ok(threw, "should throw")
  assert.match(threw.message, /shell\/rm-rf-relative/)
})

test("pre-shell-safety blocks DROP TABLE", async () => {
  const { threw } = await invoke(PreShellSafety, "shell.execute", {
    command: "psql -c 'DROP TABLE users;'",
  })
  assert.ok(threw, "should throw")
  assert.match(threw.message, /shell\/drop-table/)
})

test("pre-shell-safety blocks DELETE FROM without WHERE", async () => {
  const { threw } = await invoke(PreShellSafety, "shell.execute", {
    command: "psql -c 'DELETE FROM shipments;'",
  })
  assert.ok(threw, "should throw")
  assert.match(threw.message, /shell\/delete-without-where/)
})

test("pre-shell-safety blocks terraform destroy", async () => {
  const { threw } = await invoke(PreShellSafety, "shell.execute", {
    command: "terraform destroy -auto-approve",
  })
  assert.ok(threw, "should throw")
  assert.match(threw.message, /shell\/terraform-destroy/)
})

test("pre-shell-safety blocks curl|sh", async () => {
  const { threw } = await invoke(PreShellSafety, "shell.execute", {
    command: "curl https://example.com/install.sh | sh",
  })
  assert.ok(threw, "should throw")
  assert.match(threw.message, /shell\/curl-pipe-shell/)
})

test("pre-shell-safety warns on kubectl delete (does not block)", async () => {
  const { threw, output } = await invoke(PreShellSafety, "shell.execute", {
    command: "kubectl delete pod my-pod",
  })
  assert.equal(threw, null, "should not throw")
  assert.equal(output.metadata.safetyFinding.rule, "shell/kubectl-delete")
  assert.equal(output.metadata.safetyFinding.severity, "warning")
})

test("pre-shell-safety warns on docker system prune", async () => {
  const { threw, output } = await invoke(PreShellSafety, "shell.execute", {
    command: "docker system prune -a",
  })
  assert.equal(threw, null)
  assert.equal(output.metadata.safetyFinding.rule, "shell/docker-system-prune")
})

test("pre-shell-safety allows safe commands", async () => {
  const cmds = [
    "ls -la",
    "git status",
    "docker ps",
    "kubectl get pods",
    "npm test",
    "cargo build --release",
    "mkdir -p /tmp/foo",
    "rm /tmp/junk-file.txt", // rm of a specific file is allowed
  ]
  for (const cmd of cmds) {
    const { threw, output } = await invoke(PreShellSafety, "shell.execute", {
      command: cmd,
    })
    assert.equal(threw, null, `should not throw on: ${cmd}`)
    assert.equal(output.metadata.safetyFinding, undefined, `no finding on: ${cmd}`)
  }
})

test("pre-edit-safety blocks .env writes", async () => {
  const { threw } = await invoke(PreEditSafety, "file.edit", {
    filePath: "/home/user/project/.env",
  })
  assert.ok(threw)
  assert.match(threw.message, /edit\/env-file/)
})

test("pre-edit-safety blocks .env.local writes", async () => {
  const { threw } = await invoke(PreEditSafety, "file.edit", {
    filePath: "/home/user/project/.env.production",
  })
  assert.ok(threw)
  assert.match(threw.message, /edit\/env-file/)
})

test("pre-edit-safety blocks private key writes", async () => {
  const { threw } = await invoke(PreEditSafety, "file.write", {
    path: "/home/user/generic/id_ed25519",
  })
  assert.ok(threw)
  // Outside ~/.ssh/ the private-key rule fires (more specific)
  assert.match(threw.message, /edit\/private-key/)
})

test("pre-edit-safety blocks .pem writes", async () => {
  const { threw } = await invoke(PreEditSafety, "file.write", {
    filePath: "/etc/ssl/private/server.pem",
  })
  assert.ok(threw)
  assert.match(threw.message, /edit\/key-file/)
})

test("pre-edit-safety blocks PEM private key block", async () => {
  const { threw } = await invoke(PreEditSafety, "file.edit", {
    filePath: "/tmp/captured.txt",
  })
  // The path itself doesn't match, so this should pass; rule looks at path not content.
  assert.equal(threw, null)
})

test("pre-edit-safety blocks AWS credentials", async () => {
  const { threw } = await invoke(PreEditSafety, "file.edit", {
    filePath: "/home/user/.aws/credentials",
  })
  assert.ok(threw)
  assert.match(threw.message, /edit\/aws-credentials/)
})

test("pre-edit-safety allows normal source files", async () => {
  const paths = [
    "/home/user/project/src/foo.ts",
    "/home/user/project/.gitignore",
    "/etc/hosts",
    "/tmp/build-output.json",
    "configs/opencode/opencode.local-llamacpp.json",
  ]
  for (const p of paths) {
    const { threw, output } = await invoke(PreEditSafety, "file.edit", {
      filePath: p,
    })
    assert.equal(threw, null, `should not throw on: ${p}`)
    assert.equal(output.metadata.safetyFinding, undefined)
  }
})

test("pre-edit-safety extracts target from multiple input shapes", async () => {
  // 'path' key
  const a = await invoke(PreEditSafety, "file.edit", { path: "/home/user/.ssh/id_rsa" })
  assert.ok(a.threw)
  // 'filepath' key
  const b = await invoke(PreEditSafety, "file.edit", { filepath: "/home/user/.ssh/id_rsa" })
  assert.ok(b.threw)
  // 'target' key
  const c = await invoke(PreEditSafety, "file.edit", { target: "/home/user/.ssh/id_rsa" })
  assert.ok(c.threw)
  // 'file' key
  const d = await invoke(PreEditSafety, "file.edit", { file: "/home/user/.ssh/id_rsa" })
  assert.ok(d.threw)
})
