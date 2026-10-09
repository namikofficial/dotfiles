# Tasks

**There is no task board in this repository any more.**

The active plan is [`docs/NOXFLOW_REPAIR_PLAN.md`](docs/NOXFLOW_REPAIR_PLAN.md).

It is the only NoxFlow plan. It supersedes `PLAN.md`, `PLAN_v2.md`,
`theplan.md`, `OPENCODE_TASK.md` and this file, all of which now live in
[`docs/archive/`](docs/archive/README.md) as history only.

## How to work from it

1. Read `docs/NOXFLOW_REPAIR_PLAN.md`. Section 2 lists the seven phases; section
   0.5 is the progress log of what has actually landed and what was verified.
2. Pick the next unfinished item. Each has an owner file and an acceptance
   check — the acceptance check is the definition of done, not your judgement of
   it.
3. Finish the phase gate before starting the next phase:
   ```sh
   node shell/noxflow/tests/run-all.js
   ./setup/check-noxflow-load.sh
   tests/smoke/test-noxflow-surfaces.sh
   ```
4. Append what you did, and how you verified it, to section 0.5.

## Do not

- Do not read a plan from `docs/archive/` as if it were current. Several of its
  claims were checked and found false; the repair plan's section 3 records which.
- Do not add items here. If something needs tracking and it is not in the repair
  plan, add it to the repair plan.