---
name: task-execute
description: Implement the next item from the repository's active plan against its acceptance criteria, and verify before reporting done.
compatibility: opencode
---
## What I do
- Read the item in full (goal, in/out scope, criteria, verification, notes) before editing
- Make the smallest change that satisfies the acceptance criteria; do not expand scope
- Run the item's acceptance check and report the observed result, not the expected one

## The active plan
This repository has exactly one: `docs/NOXFLOW_REPAIR_PLAN.md`.

Items are numbered by phase (section 2) and the progress log is section 0.5.
`PLAN.md`, `PLAN_v2.md`, `theplan.md`, `OPENCODE_TASK.md` and the old `TASKS.md`
are in `docs/archive/` as history only — several of their claims were checked
and found false, so they must not be used as current guidance. See
`docs/archive/README.md`.

## The phase gate
Every phase ends with the same three checks. Run them before starting the next
phase:

```sh
node shell/noxflow/tests/run-all.js
./setup/check-noxflow-load.sh
tests/smoke/test-noxflow-surfaces.sh
```

`check-noxflow-load.sh` never starts a second shell while the live one is up; it
restarts `noxflow-shell.service` instead. Do not verify the shell by running
`quickshell -p` by hand — that draws a second top bar over the running one.

## When to use me
Use this when an item in the active plan is the next thing to work on, or when
the user hands you a repair-plan item and expects implementation.