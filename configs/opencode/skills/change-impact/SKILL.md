---
name: change-impact
description: Pre/post call-graph impact analysis for a planned change. Maps which symbols, callers, contracts, APIs, DB queries, jobs, UI components, and tests are affected. Owns the change-budget rule: flag when actual changed files far exceed planned.
compatibility: opencode
---

## What I do

For any non-trivial change, produce two views:

1. **Planned impact graph** — what the change is supposed to touch, derived from the plan.
2. **Actual diff** — what the implementation actually changed.

Compare the two. If they disagree, investigate. The disagreement is usually one of:

- The implementation expanded scope without justification.
- The plan missed a caller.
- The plan missed a contract dependency.
- A consumer wasn't updated to match the change.

I also own the **change-budget rule**: if `actual_changed_files - planned_files > threshold`, STOP and replan.

## When to use me

Use this skill when:

- Implementing a refactor that touches shared types or APIs.
- Reviewing a non-trivial change before merging.
- Debugging "I changed X but Y broke" — when callers should have updated and didn't.
- Analyzing whether a feature can be removed cleanly.

Do NOT use this skill for trivial changes (single-file cosmetic, typo fixes).

## Output

For each change, produce an impact map:

```
SYMBOL: <changed symbol or file>

DIRECT CALLERS (same module)
  - <caller 1> (src/foo.ts:42)
  - <caller 2> (src/bar.ts:88)

TRANSITIVE CALLERS (1 hop)
  - <caller 3> (src/baz.ts:15) — calls <caller 1>
  - <caller 4> (src/qux.ts:22) — calls <caller 2>

CONTRACT CONSUMERS
  - API: GET /api/v1/<endpoint> called by <client code>
  - API: POST /api/v1/<endpoint> — body shape changed, see <client code>
  - Event: <event name> — handled by <subscriber>

DB
  - Table: <table> — column changed, see migration
  - Query: SELECT ... FROM <table> — requires company scope

BACKGROUND JOBS
  - <job name> reads from <table>

UI
  - <component> renders <symbol>
  - <hook> returns <symbol>

TESTS
  - <test name> covers <symbol>
  - <test name> mocks <symbol>
```

Plus a delta report:

```
PLANNED FILES: <N>
ACTUAL FILES: <M>
DELTA: M - N

OVER-BUDGET: yes/no
  - Unexpected files: <list>
  - Missing callers: <list>
```

## How to compute

1. Identify the changed symbol(s) by reading the diff.
2. Use LSP `findReferences` for each changed symbol to enumerate callers.
3. Use LSP `callHierarchy incomingCalls` for the same.
4. Use CodeGraph for cross-package impact.
5. Use `rg` for contract consumers:
   - API: `rg -l 'GET .*<endpoint>' --type ts`
   - Event: `rg -l 'on\(.<event>' --type ts`
   - DB: `rg -l 'from .<table>' --type ts`
6. Categorize each caller as direct, transitive, or contract consumer.
7. Cross-check with the test files — is each contract consumer covered by a test?

## The change-budget rule

```
EXPECTED SURFACE: ≤ N files (set in the plan, per-task)

if actual_changed_files - planned_files > threshold:
  STOP
  list unexpected files with file:line
  ask: is the expansion justified?
  if yes: update plan, continue
  if no: replan, narrow scope
```

Threshold guidance:
- Pure refactor: 0 extra (or pre-declared in plan)
- New feature: ≤ 1.5× planned
- Library upgrade: 0 (or every change is justified)

The threshold is set in the plan, not enforced as a hard universal.

## Workflow

### Before implementation

1. Use this skill to compute the **planned impact graph** from the symbol you're about to change.
2. Update the plan with the list of files you'll touch.
3. Set the change budget in the plan.

### After implementation

1. Compute the **actual diff** (`git diff --name-only`).
2. Re-run this skill on the changed symbols to get the post-change impact graph.
3. Compare planned vs actual file lists.
4. Run the change-budget check.
5. Verify each direct caller has been updated (for refactors where the API/contract changed).
6. Verify each contract consumer has a corresponding test update.

## Common blind spots

- **Tests don't catch signature changes.** A type-only refactor can pass all tests but break consumers at runtime if the consumers cast or assume shape.
- **Generated code isn't in the diff.** A schema change might require regenerating clients or types. The diff looks clean but downstream consumers are now broken.
- **Background jobs run on a different schedule.** A job that ran on the old schema is still in flight when you deploy the new one.
- **Documentation doesn't update.** The README still references the old API.

These are flagged separately in the impact report.

## Output

When invoked, return:

- The impact map for the changed symbols
- The delta report (planned vs actual)
- The change-budget verdict (within / over)
- Specific file:line locations for each unexpected change or missing consumer
- A recommendation: merge, narrow scope, or split into multiple commits

If the answer is "narrow scope", the next step is replanning, not implementing more.
