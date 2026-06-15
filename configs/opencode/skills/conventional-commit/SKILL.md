---
name: conventional-commit
description: Generate a detailed conventional commit message from staged changes. Use when the user runs `git commit` with the AI helper, or asks for a commit message from a diff.
---

# Conventional Commit

## When to use

- User runs `kage ai commit-msg` or `gcm`
- User asks "write a commit message for these changes"
- User pastes a diff and asks for a commit message

## Rules

### Subject line (required)

```
type(scope): imperative lowercase subject
```

- **type** (required): `feat`, `fix`, `refactor`, `perf`, `docs`, `test`, `build`, `ci`, `chore`, `style`, `revert`
- **scope** (optional): the area of the codebase (e.g. `api`, `web`, `cli`, `rag`, `auth`)
- **subject** (required):
  - Imperative mood ("add", not "added" or "adds")
  - Lowercase
  - No period at the end
  - ≤ 50 chars
  - No emoji
  - Describe the **what**, not the **how**

### Body (encouraged, especially for non-trivial changes)

- Wrap at **72 chars per line**
- Explain the **WHY**, not the what (the diff already shows the what)
- Use bullet points (`- `) for multiple reasons
- Reference the user-visible behavior change, not the implementation
- If the change is non-obvious, link to the issue, doc, or design rationale

### Footer (when relevant)

- `BREAKING CHANGE: <description>` (if the change breaks public API)
- `Refs: #123` (if it closes an issue)
- `Co-authored-by: Name <email>` (when pair/mob programming)

## Examples

### Minimal (small change)

```
chore(deps): bump biome to 2.4.16
```

### Standard feature

```
feat(api): add SSE stream for /dev/run events

- The /dev/run endpoint now streams lifecycle events so the web UI
  can show progress without polling
- Each event is `{ type, runId, ts, data }` JSON-encoded
- Reconnect-safe: client sends Last-Event-ID header
```

### Bug fix

```
fix(auth): prevent token refresh on stale requests

The refresh endpoint was racing with logout. A request that
arrived during logout would re-issue a token, undoing the
session clear.

- Add a 1s debounce on the refresh path
- Reject refresh if the session was marked dead in the last 2s
- Closes #482
```

### Breaking change

```
feat(api)!: drop support for Fastify 4 routes

The plugin API changed in 5.x and we're moving forward.
v4 routes will return 404 with a `Migrate` link in the body.

BREAKING CHANGE: Fastify 4 plugin authors must upgrade to v5.
Migration guide: docs/migrations/fastify-4-to-5.md
```

## Anti-patterns (DO NOT)

- ❌ `fix stuff` — vague, no type, no scope, no body
- ❌ `feat(api): Added new feature.` — past tense, period at end
- ❌ `WIP` — never a final commit message
- ❌ `feat(api): WIP adding SSE` — type and scope OK but WIP is not
- ❌ `chore: format` — useless; the diff shows the format
- ❌ `feat(api): huge commit merging dev into main` — squash before commit
- ❌ `feat: implemented a sophisticated algorithm` — describe the algorithm, not the existence of it
- ❌ Multiple `type:` lines — squash

## When to skip the body

- Pure formatting changes (`chore: biome reformat`)
- Single-line typo fixes (`docs: fix typo in README`)
- Version bumps (`chore(release): 1.2.3`)
- Automated dependency updates (`chore(deps): lockfile refresh`)

In all other cases, **a body is expected** — the user wants to know *why* you changed the code, not just *what* you changed.
