
<!-- personal-subagent-routing -->
## Quality contract

- Start from the requested outcome and observable acceptance criteria; inspect repository instructions, branch/status, affected callers, contracts, and tests before editing.
- Make the smallest complete change. Preserve unrelated work, do not invent compatibility layers, hide errors, weaken types, or claim a build/startup proves runtime behavior.
- Verify the changed behavior at the cheapest authoritative tier, then escalate only when the surface requires it. Treat delegated output as evidence, not authority.
- Final reports must separate `OBSERVED`, `NOT_CONFIGURED`, `UNVERIFIED`, `BLOCKED`, and `RECOMMENDED`, and include exact paths, commands, results, risks, and next action.

## Subagent delegation

Use subagents proactively to keep the main context focused.

- Use `scout` for repository exploration, locating implementations, tracing unfamiliar flows, and identifying affected files before substantial changes.
- Use `reviewer` after meaningful implementations, bug fixes, refactors, migrations, authentication changes, database changes, or infrastructure changes.
- Delegate independent investigations in parallel when doing so will materially reduce main-context usage.
- Do not delegate trivial operations where delegation would cost more than doing the work directly.
- The main agent remains responsible for implementation, verification, and the final decision.
