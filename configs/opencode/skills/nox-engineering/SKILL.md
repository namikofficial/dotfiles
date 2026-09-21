---
name: nox-engineering
description: NoxOrigin engineering workflow for tenant-safe architecture, contracts, verification, and focused delivery.
compatibility: opencode
---

# Nox engineering

Use this skill for NoxOrigin backend, API, database, worker, shared-contract,
release, or cross-platform work. It is the engineering counterpart to
`nox-ui-engineering`.

## Route before editing

1. Confirm repository root, branch, HEAD, dirty state, and nearest `AGENTS.md`.
2. Read the smallest relevant contract, owner module, callers, schema/migration,
   and tests. Treat `.ai/state.md` and historical handoffs as evidence, not truth.
3. Identify the owning boundary: transport/UI, application/use-case, domain,
   port, adapter, database/RLS, worker, or generated contract.
4. State objective, acceptance criteria, non-goals, affected files, and the
   cheapest check that could disprove the plan.

## Non-negotiable invariants

- Workspace scope and authorization are server-owned; never trust client scope,
  actor, role, permission, or resource IDs.
- PostgreSQL is business truth; one atomic operation uses one transaction-scoped
  connection. State, audit, and mandatory outbox effects commit together.
- Jobs and consumers are retry-safe and idempotent. External HTTP calls do not
  hold database locks when the contract permits a post-commit phase.
- Domain code does not import Fastify, React Native, Expo Router, Drizzle,
  PostgreSQL, environment, HTTP, UI state, or generated clients.
- Historical migrations are immutable. Generated API/OpenAPI clients are
  refreshed through the owning generator, never hand-edited.
- Preserve useful URLs, semantic labels, accessibility, loading/empty/error/
  permission/offline states, and deliberate Web versus Android interaction.

## Verification routing

Use the smallest authoritative gate first and expand only when the changed
seam requires it:

| Surface | First gate | Escalate when needed |
| --- | --- | --- |
| Pure domain/adapter | focused unit/typecheck | package tests |
| DB/RLS/transaction | isolated integration | concurrency/tenant matrix |
| API/contracts | route/contract test | generated client/OpenAPI gate |
| Web UI | focused Playwright | seeded Web-to-API runtime |
| Android/native | JVM/lint/host check | emulator/device/Maestro |
| release/deploy | repository release gate | staging/production evidence |

Report `PASS`, `PARTIAL`, `BLOCKED`, or `UNVERIFIED` per layer. A green build,
mocked browser test, or health endpoint is not end-to-end proof.

## Delegation and handoff

Delegate only an independent bounded slice. The handoff must contain objective,
acceptance criteria, known evidence, relevant paths, do-not-investigate limits,
and required return fields. The coordinator owns integration, diff review,
verification, and the final verdict.

## Completion packet

Return changed files, callers/contracts reviewed, commands and observed results,
proof by layer, unresolved risks, and the next safe action. Do not hide skipped
device/database/staging gates behind a generic “verified” label.
