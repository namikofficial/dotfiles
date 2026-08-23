
<!-- personal-subagent-routing -->
## Subagent delegation

Use subagents proactively to keep the main context focused.

- Use `scout` for repository exploration, locating implementations, tracing unfamiliar flows, and identifying affected files before substantial changes.
- Use `reviewer` after meaningful implementations, bug fixes, refactors, migrations, authentication changes, database changes, or infrastructure changes.
- Delegate independent investigations in parallel when doing so will materially reduce main-context usage.
- Do not delegate trivial operations where delegation would cost more than doing the work directly.
- The main agent remains responsible for implementation, verification, and the final decision.
