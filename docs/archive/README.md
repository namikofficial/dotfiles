# Archived plans

These files are historical. They are kept for provenance, not for instruction.

**The current plan is [`docs/NOXFLOW_REPAIR_PLAN.md`](../NOXFLOW_REPAIR_PLAN.md).**

It supersedes everything in this directory.

| File | Superseded by the repair plan on | Note |
| --- | --- | --- |
| `PLAN.md` | 2026-10-09 | 1746-line architecture plan for the earlier NoxFlow rewrite. |
| `PLAN_v2.md` | 2026-10-09 | Revision of `PLAN.md`, itself superseded by `theplan.md`. Its branch assumptions (`inspired-rewrite`) and live-service assertions no longer hold. |
| `theplan.md` | 2026-10-09 | The largest of the four. Describes an architecture the shell no longer has. |
| `OPENCODE_TASK.md` | 2026-10-09 | A task brief that referenced the other three. |
| `session-ses_05bd.md` | 2026-10-09 | 338 KB raw session transcript. Kept only as a record; git history holds the same content in a form that diffs. |
| `legacy/` | 2026-10-09 | Held only a README saying "do not move Wayle and friends yet". That decision is made: `wayle/` stays put as the documented fallback, so the directory had nothing left to guard. |

## Why they were archived rather than deleted

They contain claims that were checked and found false — most notably that most
power, media and lock buttons were rejected by `noxd`. Live probes against the
daemon showed `noxd` accepts every action the shell sends except `ai_query`, and
the real breakage was in the QML glue. The repair plan records which audit
claims were rejected and why (section 3).

Reading these documents as current guidance is how that false claim survived
long enough to shape a repair plan built on top of it.

## Do not edit these

Add work to `docs/NOXFLOW_REPAIR_PLAN.md`. Its section 0.5 is the progress log.