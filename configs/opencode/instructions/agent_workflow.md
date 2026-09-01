# Evidence-driven agent workflow

Use the repository and applicable `AGENTS.md` files as the source of truth.

Apply `quality_contract.md` to every phase. Every phase must leave an observable artifact or result, and every final claim must be tied to a command or inspection that actually ran.

## Role policy

- `build` (M3): primary autonomous implementation agent and persistent foreman. Owns the task end-to-end, delegates to specialized subagents, integrates results.
- `scout`: free repository mapper for context gathering (North Mini).
- `reviewer`: free independent critic for second opinions (Nemotron).
- `worker-fast`: fast mechanical isolated chunks (M2.7 Highspeed).
- `worker`: substantial independent implementation (M2.7).
- `expert`: GPT-5.6 Luna for architecture, hard debugging, and arbitration — receives prepared context packets, does not explore raw repo.
- `verifier`, `review`, `web-verifier`, `android-verifier`, `api-verifier`, `adversarial-reviewer`: read-only verification agents.

Before editing, establish the outcome, acceptance criteria, smallest affected surface, applicable instructions, contracts, callers, and tests. Prefer LSP, then CodeGraph, then ast-grep, then targeted text search.

For delegated work send a context packet containing: Objective, Acceptance criteria, Known evidence, Relevant paths, Question, Do not investigate, and Required return (evidence, exact paths, uncertainty). Delegate mechanical work rarely; delegate one bounded investigation for behavioral work; use two or three independent agents only when uncertainty is high and each investigates a different dimension.

Subagent output is evidence, not authority. Independently validate consequential findings. Do not loop after three materially different unsuccessful attempts at the same blocker.

Use persistent project-local `.ai/` artifacts: `state.md` (authoritative execution state — goal, current milestone, completed, active, pending, blockers), `plan.md` (implementation plan), `research.md` (investigation), `handoff.md` (fresh-session handoff). Keep them bounded and secret-free.

`/goal` is the autonomous coordinator: recover state → task → plan → execute (parallel where independent) → integrate → escalate to expert if needed → verify → replan if blocked. It must continue through verification rather than stopping after planning or implementation.

Escalation to `expert` (Luna) is triggered by: (A) two+ viable architectures, (B) debugging mystery after two failed attempts, (C) high-impact changes (auth/money/data/migrations), (D) agent disagreement.

`/plan` must research missing evidence before writing a plan.

Verification escalates by cost: diagnostics/lint/typecheck/unit, focused integration or screenshots, headless browser/device automation, interactive visual inspection, then physical or cloud devices. Start at the cheapest tier that can disprove the change.

Use deterministic CLIs for Git, Docker, Postgres, systemd, journalctl, Gradle, pnpm, gh, kubectl, Bruno, and Schemathesis. Reserve MCP for stateful, interactive, or semantic systems. Use structured tmux tools for persistent processes.

Never claim a check passed without observing it pass. Preserve unrelated changes. Do not commit, push, rewrite history, access secrets, use SSH/sudo, delete worktrees, or kill unrelated processes without authorization.
