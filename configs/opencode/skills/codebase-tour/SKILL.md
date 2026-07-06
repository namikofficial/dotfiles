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
# Project: ai (workbench)

## Identity
Local-first AI engineering workbench. TypeScript monorepo (Fastify + Vite +
SQLite/Qdrant + MCP). Slice 26 in progress (dev-agent).

## Layout
apps/         — web (Vite), api (Fastify), worker
packages/     — 19: agent-protocol, ask-engine, dev-agent, retrieval-engine, ...
mcp/          — safe MCP server
cli/          — `ai` command
tests/        — 49 test files
runtime/      — ai.db (7MB), exports, logs

## Key entry points
- PLAN.md                 — 1746-line architecture plan
- apps/api/src/server.ts  — Fastify API (3507 lines)
- packages/dev-agent/     — slice 26 work
- runtime/ai.db           — SQLite, source of truth

## Common questions
- Auth? — Not yet (slice 26 ships with approval, not auth)
- Schema? — runtime/ai.db, migrations in packages/db/src/migrations/
- Tests? — `pnpm test` (node --test)
- Add a route? — apps/api/src/server.ts (single file, ~3500 lines)
```

## Tone

- **Terse**. New devs skim, they don't read.
- **Accurate**. If you don't know, say "I don't know — check `docs/`" or "look at `package.json` scripts".
- **Concrete**. Cite file paths, not vague descriptions.
- **Skip what's not there.** No docker compose? Don't mention it. No tests dir? Say "no test suite yet".
