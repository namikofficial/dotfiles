import { mkdir, readFile, writeFile } from "node:fs/promises"
import { dirname, isAbsolute, join, relative, resolve } from "node:path"

const tmuxBinary = process.env.TMUX_BIN || "tmux"
const blockedCommand = /(^|[;&|\s])(sudo|ssh|rm\s+-rf|git\s+(reset|clean|push|rebase)|tmux\s+kill-server)(?=$|[;&|\s])/i
const safeName = /^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$/
const safeKeys = new Set(["C-c", "C-d", "C-l", "C-z", "ENTER", "ESC", "UP", "DOWN", "LEFT", "RIGHT"])
let tmuxServerArgs = []
let sharedSessions = new Set()

function fail(message) {
  throw new Error(`tmux-tools: ${message}`)
}

function assertName(value, label) {
  if (typeof value !== "string" || !safeName.test(value)) fail(`${label} must contain only letters, numbers, '.', '_' or '-'`)
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
  const process = Bun.spawn([tmuxBinary, ...tmuxServerArgs, ...args], { stdout: "pipe", stderr: "pipe" })
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
  if (sharedSessions.has(session)) {
    if (!(await hasSession(session))) fail(`configured shared tmux session '${session}' is not running`)
    return
  }
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
  try {
    return JSON.parse(raw)
  } catch {
    fail(`invalid process registry JSON at ${path}`)
  }
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

function textSchema(description) {
  return { type: "string", description }
}

function objectSchema(properties, required = Object.keys(properties)) {
  return { type: "object", properties, required, additionalProperties: false }
}

function response(content) {
  return { content }
}

const definitions = [
  {
    name: "tmux_create",
    description: "Create a managed tmux session/window for a long-running process.",
    input: objectSchema({
      session: textSchema("Managed tmux session name."),
      window: textSchema("Window name."),
      cwd: textSchema("Optional project-relative working directory."),
      command: textSchema("Optional command to start."),
    }, ["session", "window"]),
    async execute(args, context) {
      const cwd = projectPath(context.directory, args.cwd)
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
      return response(`Created managed tmux window ${args.session}:${args.window}`)
    },
  },
  {
    name: "tmux_run",
    description: "Run a non-interactive command in a managed tmux window.",
    input: objectSchema({
      session: textSchema("Managed tmux session name."),
      window: textSchema("Window name."),
      command: textSchema("Command to run."),
    }),
    async execute(args, context) {
      assertCommand(args.command)
      assertName(args.session, "session")
      await assertManagedSession(context.directory, args.session)
      await runTmux(["send-keys", "-t", target(args.session, args.window), "-l", "--", args.command])
      await runTmux(["send-keys", "-t", target(args.session, args.window), "ENTER"])
      return response(`Started command in ${args.session}:${args.window}`)
    },
  },
  {
    name: "tmux_send",
    description: "Send an approved key or literal text to a managed tmux window.",
    input: objectSchema({
      session: textSchema("Managed tmux session name."),
      window: textSchema("Window name."),
      keys: textSchema("Approved key name or literal text."),
      literal: { type: "boolean", description: "Treat keys as literal text." },
    }, ["session", "window", "keys"]),
    async execute(args, context) {
      const pane = target(args.session, args.window)
      await assertManagedSession(context.directory, args.session)
      if (args.literal) {
        if (args.keys.length > 4096) fail("literal input is limited to 4096 characters")
        await runTmux(["send-keys", "-t", pane, "-l", "--", args.keys])
      } else if (safeKeys.has(args.keys)) {
        await runTmux(["send-keys", "-t", pane, args.keys])
      } else {
        fail("key is not approved; use literal=true for text")
      }
      return response(`Sent input to ${pane}`)
    },
  },
  {
    name: "tmux_capture",
    description: "Capture bounded output from a managed tmux window.",
    input: objectSchema({
      session: textSchema("Managed tmux session name."),
      window: textSchema("Window name."),
      lines: { type: "number", description: "Number of recent lines, from 1 to 500." },
    }, ["session", "window"]),
    async execute(args, context) {
      const lines = Math.min(Math.max(Math.trunc(args.lines || 100), 1), 500)
      await assertManagedSession(context.directory, args.session)
      return response(await runTmux(["capture-pane", "-p", "-J", "-t", target(args.session, args.window), "-S", `-${lines}`]))
    },
  },
  {
    name: "tmux_status",
    description: "List tmux sessions and windows without attaching to them.",
    input: objectSchema({}),
    async execute() {
      return response(await runTmux(["list-sessions", "-F", "#{session_name}"]) || "No tmux sessions")
    },
  },
  {
    name: "tmux_kill",
    description: "Kill a managed tmux session after explicit confirmation.",
    input: objectSchema({
      session: textSchema("Managed tmux session name."),
      confirm: { type: "boolean", description: "Confirm stopping the managed session." },
    }),
    async execute(args, context) {
      if (!args.confirm) fail("confirm=true is required")
      assertName(args.session, "session")
      if (sharedSessions.has(args.session)) fail("refusing to kill a shared system tmux session")
      await assertManagedSession(context.directory, args.session, "kill")
      await runTmux(["kill-session", "-t", args.session])
      return response(`Killed managed tmux session ${args.session}`)
    },
  },
  {
    name: "process_start",
    description: "Start a named process from the current project's .opencode/processes.json registry.",
    input: objectSchema({ process: textSchema("Registered process name.") }),
    async execute(args, context) {
      const entry = processEntry(await readRegistry(context.directory), args.process)
      const cwd = projectPath(context.directory, entry.cwd)
      if (await hasSession(entry.session)) {
        await runTmux(["new-window", "-d", "-t", entry.session, "-n", entry.window, "-c", cwd, entry.command])
      } else {
        await runTmux(["new-session", "-d", "-s", entry.session, "-n", entry.window, "-c", cwd, entry.command])
      }
      await markManaged(context.directory, entry.session, entry.window)
      return response(`Started registered process ${args.process}`)
    },
  },
  {
    name: "process_logs",
    description: "Capture logs for a named registered process.",
    input: objectSchema({
      process: textSchema("Registered process name."),
      lines: { type: "number", description: "Number of recent lines, from 1 to 500." },
    }, ["process"]),
    async execute(args, context) {
      const entry = processEntry(await readRegistry(context.directory), args.process)
      await assertManagedSession(context.directory, entry.session)
      const lines = Math.min(Math.max(Math.trunc(args.lines || 100), 1), 500)
      return response(await runTmux(["capture-pane", "-p", "-J", "-t", target(entry.session, entry.window), "-S", `-${lines}`]))
    },
  },
  {
    name: "process_restart",
    description: "Stop and restart a named registered process in its existing window.",
    input: objectSchema({ process: textSchema("Registered process name.") }),
    async execute(args, context) {
      const entry = processEntry(await readRegistry(context.directory), args.process)
      await assertManagedSession(context.directory, entry.session)
      const pane = target(entry.session, entry.window)
      await runTmux(["send-keys", "-t", pane, "C-c"])
      await runTmux(["send-keys", "-t", pane, "-l", "--", entry.command])
      await runTmux(["send-keys", "-t", pane, "ENTER"])
      return response(`Restarted registered process ${args.process}`)
    },
  },
  {
    name: "process_status",
    description: "Show the tmux target for a named registered process.",
    input: objectSchema({ process: textSchema("Registered process name.") }),
    async execute(args, context) {
      const entry = processEntry(await readRegistry(context.directory), args.process)
      await assertManagedSession(context.directory, entry.session)
      const pane = target(entry.session, entry.window)
      return response(await runTmux(["display-message", "-p", "-t", pane, "#{session_name}:#{window_name} #{pane_current_command}"]))
    },
  },
]

export default {
  id: "nox.tmux-tools",
  async setup(ctx) {
    const socketName = ctx.options?.socketName
    if (typeof socketName !== "string" || !safeName.test(socketName)) {
      fail("plugin option socketName must be a valid tmux socket name")
    }
    const configuredSharedSessions = ctx.options?.sharedSessions
    if (!Array.isArray(configuredSharedSessions) || configuredSharedSessions.some((name) => typeof name !== "string" || !safeName.test(name))) {
      fail("plugin option sharedSessions must be an array of valid tmux session names")
    }
    tmuxServerArgs = ["-L", socketName]
    sharedSessions = new Set(configuredSharedSessions)
    await ctx.tool.transform((editor) => {
      for (const definition of definitions) editor.add(definition)
    })
  },
}
