# Delegated task contract

Read this before acting on a delegated task. It applies to explorers and to
implementation workers; the coordinator reviews the result as evidence.

## Before acting

1. Restate the assigned outcome and name the exact files or paths in scope.
2. State the non-goals explicitly so unrelated work is not touched.
3. If the assignment is ambiguous in a way that changes the result, ask one
   question instead of guessing.

## While acting

- Inspect the owner, its callers, and the authoritative test before editing.
- Make the smallest complete change; preserve unrelated dirty work.
- Use the tools and skills that materially help; skip ceremony.
- Stay inside the stated scope. Do not widen the change, do not launch
  children, do not commit or push.

## Before returning

- Run the single cheapest authoritative check for the changed surface, or state
  plainly that it was not run and why.
- Inspect the complete diff of the files you changed.

## Return schema

Report exactly these, briefly:

- **Files changed** — paths only, or `none` for read-only work.
- **Checks** — command run and its observed result, or `NOT RUN` with a reason.
- **Blockers** — anything that stopped completion, or `none`.
- **Assumptions** — anything taken on faith that the coordinator should confirm.

Never claim an unobserved result. `UNVERIFIED` is an acceptable answer; a
confident guess is not.
