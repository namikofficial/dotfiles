# Agent quality contract

Apply this contract to every implementation, plan, review, and verification task.

## Before action

- Restate the user-visible outcome in one sentence.
- Extract observable acceptance criteria, non-goals, constraints, and the affected surface.
- Inspect repository instructions, branch/status, entry points, callers, contracts, and authoritative tests before editing.
- Label assumptions and choose the cheapest check capable of disproving each important assumption.

## During action

- Make the smallest complete change; preserve unrelated dirty work.
- Trace every changed interface to its callers and failure paths.
- Prefer existing patterns and deterministic CLIs. Do not add speculative fallbacks, hidden casts, broad rewrites, silent error suppression, or unrelated cleanup.
- Treat delegated output as evidence requiring independent validation.

## Completion proof

- Inspect the complete diff and changed call sites.
- Run focused checks first, then the authoritative broader checks required by the repository.
- Report only observed results and label each item `OBSERVED`, `NOT_CONFIGURED`, `UNVERIFIED`, `BLOCKED`, or `RECOMMENDED`.
- State residual risks, skipped gates, and the next safe action. A build, startup, registration, or DOM assertion alone is not proof of user-visible correctness.
