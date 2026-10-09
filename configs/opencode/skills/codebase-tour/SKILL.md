---
name: codebase-tour
description: Give a quick orientation of an unfamiliar repo. Use when the user says "what is this project", "where is X handled", "give me a tour", or first opens a project.
---

# Codebase Tour

## When to use

- User opens a new project and asks "what is this?"
- User asks "where is X handled?" (auth, caching, routing, etc.)
- User wants a quick orientation before diving in
- User is onboarding a new dev to a project

## Output format

Produce a 4-section report. Keep it **terse** — bullet points, not paragraphs.

### 1. Identity (1-3 lines)

- **Name** of the project
- **One-sentence purpose** (from the README or `package.json` description)
- **Primary language** and **framework** (if any)
- **Repo URL** (if git origin is set)

### 2. Layout (tree of top-level dirs only)

```
src/          — application code
apps/         — (for monorepos) app entry points
packages/     — (for monorepos) shared packages
tests/        — test files
docs/         — documentation
scripts/      — helper scripts
config/       — configuration
```

For each non-empty top-level dir, give **one-line purpose**.

### 3. Key entry points (3-7 files)

The files a new contributor should read first:

- `README.md` (always)
- `package.json` / `Cargo.toml` / `pyproject.toml` — manifest
- `src/main.ts` / `cmd/server/main.go` / `manage.py` — entry
- `src/index.ts` / `lib/foo.rb` — root module
- `tests/` — sample test (so they know the test style)
- `docs/architecture.md` or `docs/overview.md` — if it exists

For each, say **one line** about why it matters.

### 4. Where to look for common questions

Pre-empt the things a new dev will ask:

| Question | Where to look |
|---|---|
| "How is auth handled?" | `src/auth/`, `middleware/`, `src/server/auth.ts` |
| "Where is the DB schema?" | `prisma/schema.prisma`, `migrations/`, `db/schema.sql` |
| "How do I run tests?" | `package.json` scripts, `tests/README.md` |
| "How do I add a route?" | `src/routes/`, `apps/api/src/server.ts` |
| "How do I deploy?" | `Dockerfile`, `k8s/`, `scripts/deploy.sh`, `.github/workflows/` |
| "What's the testing stack?" | `vitest.config.ts`, `jest.config.*`, `pyproject.toml [tool.pytest]` |

## Example output (terse)

```
# Project: dotfiles (NoxFlow workstation)

## Identity
Personal workstation dotfiles. Rust workspace (`noxd` daemon + `noxctl` CLI)
plus a Quickshell/QML desktop shell called NoxFlow. Arch + Hyprland.

## Layout
core/         — Rust workspace: noxd daemon, noxflow-ipc, config, state
cli/noxctl/   — `noxctl`, the daemon control CLI
shell/noxflow/— the Quickshell/QML shell (bar/, island/, surfaces/, theme/)
hypr/         — Hyprland config, keybindings, helper scripts
setup/        — bootstrap, health checks, the release gate
configs/      — canonical app configs (opencode/, agents, MCP)
docs/         — documentation; docs/archive/ is history, not instructions
systemd/      — user units (noxflow-shell, noxflow-fallback, noxd)
tests/smoke/  — live surface smoke test

## Key entry points
- AGENTS.md                     — repo invariants; read before editing
- docs/NOXFLOW_REPAIR_PLAN.md   — THE plan; section 0.5 is the progress log
- shell/noxflow/shell.qml       — shell entry point, wires every surface
- core/noxd/src/main.rs         — the daemon
- setup/release-gate.sh         — the gate every change must pass

## Common questions
- Plans? — docs/NOXFLOW_REPAIR_PLAN.md only. Everything in docs/archive/ is
  historical and some of it was checked and found false.
- Shell tests? — node shell/noxflow/tests/run-all.js
- Did my change break the shell? — ./setup/check-noxflow-load.sh
- Full check? — ./setup/release-gate.sh
```

## Tone

- **Terse**. New devs skim, they don't read.
- **Accurate**. If you don't know, say "I don't know — check `docs/`" or "look at `package.json` scripts".
- **Concrete**. Cite file paths, not vague descriptions.
- **Skip what's not there.** No docker compose? Don't mention it. No tests dir? Say "no test suite yet".
