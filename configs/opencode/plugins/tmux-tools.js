import { mkdir, readFile, writeFile } from "node:fs/promises"
import { dirname, isAbsolute, join, relative, resolve } from "node:path"
import { tool } from "@opencode-ai/plugin"

const tmuxBinary = process.env.TMUX_BIN || "tmux"
const blockedCommand = /(^|[;&|\s])(sudo|ssh|rm\s+-rf|git\s+(reset|clean|push|rebase)|tmux\s+kill-server)(?=$|[;&|\s])/i
const safeName = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/
const safeKeys = new Set(["C-c", "C-d", "C-l", "C-z", "ENTER", "ESC", "UP", "DOWN", "LEFT", "RIGHT"])

function fail(message) {
  throw new Error(`tmux-tools: ${message}`)
}

function assertName(value, label) {
  if (!safeName.test(value)) fail(`${label} must contain only letters, numbers, '.', '_' or '-'`)
}

function assertCommand(command) {
  if (typeof command !== "string" || command.trim() === "") fail("command is required")
  if (blockedCommand.test(command)) fail("command is blocked by the tmux safety policy")
}

function projectPath(directory, requested) {
  const base = resolve(directory)
  const candidate = resolve(base, requested || ".")
  const outside = relative(base, candidate).startsWith("..")
  if (outside || isAbsolute(relative(base, candidate)) || candidate.includes("/.git/")) {
    fail("cwd must remain inside the current project")
  }
  return candidate
}

async function runTmux(args) {
  const process = Bun.spawn([tmuxBinary, ...args], { stdout: "pipe", stderr: "pipe" })
  const [exitCode, stdout, stderr] = await Promise.all([
    process.exited,
    process.stdout.text(),
    process.stderr.text(),
  ])
  if (exitCode !== 0) fail(stderr.trim() || `tmux exited with status ${exitCode}`)
  return stdout.trim()
}

async function hasSession(session) {
  try {
    await runTmux(["has-session", "-t", session])
    return true
  } catch {
    return false
  }
}

function target(session, window) {
  assertName(session, "session")
  assertName(window, "window")
  return `${session}:${window}`
}

async function statePath(directory) {
  const path = join(directory, ".opencode", "tmux-sessions.json")
  await mkdir(dirname(path), { recursive: true })
  return path
}

async function readState(directory) {
  try {
    return JSON.parse(await readFile(await statePath(directory), "utf8"))
  } catch {
    return { sessions: {} }
  }
}

async function markManaged(directory, session, window) {
  const path = await statePath(directory)
  const state = await readState(directory)
  state.sessions[session] = { window, updatedAt: new Date().toISOString() }
  await writeFile(path, `${JSON.stringify(state, null, 2)}\n`, { mode: 0o600 })
}

async function assertManagedSession(directory, session, action = "access") {
  const state = await readState(directory)
  if (!state.sessions[session]) fail(`refusing to ${action} an unregistered tmux session`)
}

async function readRegistry(directory) {
  const path = join(directory, ".opencode", "processes.json")
  let raw
  try {
    raw = await readFile(path, "utf8")
  } catch {
    fail(`process registry not found at ${path}`)
  }
  let registry
  try {
    registry = JSON.parse(raw)
  } catch {
    fail(`invalid process registry JSON at ${path}`)
  }
  return registry
}

function processEntry(registry, name) {
  assertName(name, "process")
  const entry = registry[name]
  if (!entry || typeof entry !== "object") fail(`process '${name}' is not defined in the registry`)
  assertName(entry.session, "registry session")
  assertName(entry.window, "registry window")
  assertCommand(entry.command)
  return entry
}

function cwdFor(directory, cwd) {
  return projectPath(directory, cwd)
}

export const TmuxTools = async ({ client }) => {
  const log = async (message, extra = {}) => {
    await client.app.log({
      body: { service: "tmux-tools", level: "info", message, extra },
    })
  }

  return {
    tool: {
      tmux_create: tool({
        description: "Create a managed tmux session/window for a long-running process.",
        args: {
          session: tool.schema.string(),
          window: tool.schema.string(),
          cwd: tool.schema.string().optional(),
          command: tool.schema.string().optional(),
        },
        async execute(args, context) {
          const cwd = cwdFor(context.directory, args.cwd)
          const command = args.command || "${SHELL:-/bin/sh}"
          assertCommand(command)
          assertName(args.session, "session")
          assertName(args.window, "window")
          if (await hasSession(args.session)) {
            await runTmux(["new-window", "-d", "-t", args.session, "-n", args.window, "-c", cwd, command])
          } else {
            await runTmux(["new-session", "-d", "-s", args.session, "-n", args.window, "-c", cwd, command])
          }
          await markManaged(context.directory, args.session, args.window)
          await log("created tmux window", { session: args.session, window: args.window })
          return `Created managed tmux window ${args.session}:${args.window}`
        },
      }),

      tmux_run: tool({
        description: "Run a non-interactive command in a managed tmux window.",
        args: {
          session: tool.schema.string(),
          window: tool.schema.string(),
          command: tool.schema.string(),
        },
        async execute(args, context) {
          assertCommand(args.command)
          assertName(args.session, "session")
          await assertManagedSession(context.directory, args.session)
          await runTmux(["send-keys", "-t", target(args.session, args.window), "-l", "--", args.command])
          await runTmux(["send-keys", "-t", target(args.session, args.window), "ENTER"])
          return `Started command in ${args.session}:${args.window}`
        },
      }),

      tmux_send: tool({
        description: "Send a small approved key sequence or literal text to a managed tmux window.",
        args: {
          session: tool.schema.string(),
          window: tool.schema.string(),
          keys: tool.schema.string(),
          literal: tool.schema.boolean().optional(),
        },
        async execute(args, context) {
          const pane = target(args.session, args.window)
          await assertManagedSession(context.directory, args.session)
          if (args.literal) {
            if (args.keys.length > 4096) fail("literal input is limited to 4096 characters")
            await runTmux(["send-keys", "-t", pane, "-l", "--", args.keys])
          } else if (safeKeys.has(args.keys)) {
            await runTmux(["send-keys", "-t", pane, args.keys])
          } else {
            fail("key sequence is not approved; use literal=true for text")
          }
          return `Sent input to ${pane}`
        },
      }),

      tmux_capture: tool({
        description: "Capture bounded output from a tmux window.",
        args: {
          session: tool.schema.string(),
          window: tool.schema.string(),
          lines: tool.schema.number().optional(),
        },
        async execute(args, context) {
          const lines = Math.min(Math.max(Math.trunc(args.lines || 100), 1), 500)
          await assertManagedSession(context.directory, args.session)
          return runTmux(["capture-pane", "-p", "-J", "-t", target(args.session, args.window), "-S", `-${lines}`])
        },
      }),

      tmux_status: tool({
        description: "List tmux sessions and windows without attaching to them.",
        args: {},
        async execute() {
          return runTmux(["list-sessions", "-F", "#{session_name}"]) || "No tmux sessions"
        },
      }),

      tmux_kill: tool({
        description: "Kill a managed tmux session after explicit confirmation.",
        args: {
          session: tool.schema.string(),
          confirm: tool.schema.boolean(),
        },
        async execute(args, context) {
          if (!args.confirm) fail("confirm=true is required")
          assertName(args.session, "session")
          await assertManagedSession(context.directory, args.session, "kill")
          await runTmux(["kill-session", "-t", args.session])
          return `Killed managed tmux session ${args.session}`
        },
      }),

      process_start: tool({
        description: "Start a named process from the current project's .opencode/processes.json registry.",
        args: { process: tool.schema.string() },
        async execute(args, context) {
          const entry = processEntry(await readRegistry(context.directory), args.process)
          const cwd = cwdFor(context.directory, entry.cwd)
          if (await hasSession(entry.session)) {
            await runTmux(["new-window", "-d", "-t", entry.session, "-n", entry.window, "-c", cwd, entry.command])
          } else {
            await runTmux(["new-session", "-d", "-s", entry.session, "-n", entry.window, "-c", cwd, entry.command])
          }
          await markManaged(context.directory, entry.session, entry.window)
          return `Started registered process ${args.process}`
        },
      }),

      process_logs: tool({
        description: "Capture logs for a named registered process.",
        args: { process: tool.schema.string(), lines: tool.schema.number().optional() },
        async execute(args, context) {
          const entry = processEntry(await readRegistry(context.directory), args.process)
          await assertManagedSession(context.directory, entry.session)
          const lines = Math.min(Math.max(Math.trunc(args.lines || 100), 1), 500)
          return runTmux(["capture-pane", "-p", "-J", "-t", target(entry.session, entry.window), "-S", `-${lines}`])
        },
      }),

      process_restart: tool({
        description: "Stop and restart a named registered process in its existing window.",
        args: { process: tool.schema.string() },
        async execute(args, context) {
          const entry = processEntry(await readRegistry(context.directory), args.process)
          await assertManagedSession(context.directory, entry.session)
          const pane = target(entry.session, entry.window)
          await runTmux(["send-keys", "-t", pane, "C-c"])
          await runTmux(["send-keys", "-t", pane, "-l", "--", entry.command])
          await runTmux(["send-keys", "-t", pane, "ENTER"])
          return `Restarted registered process ${args.process}`
        },
      }),

      process_status: tool({
        description: "Show the tmux target for a named registered process.",
        args: { process: tool.schema.string() },
        async execute(args, context) {
          const entry = processEntry(await readRegistry(context.directory), args.process)
          await assertManagedSession(context.directory, entry.session)
          const pane = target(entry.session, entry.window)
          return runTmux(["display-message", "-p", "-t", pane, "#{session_name}:#{window_name} #{pane_current_command}"])
        },
      }),
    },
  }
}
