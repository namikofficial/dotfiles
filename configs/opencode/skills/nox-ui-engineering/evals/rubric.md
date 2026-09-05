# nox-ui-engineering rubric

This rubric defines how a UI implementation is graded against the rules in `nox-ui-engineering/SKILL.md`. Used by `agent-lab` to record baseline and post-skill runs.

## Hard gates (all must PASS)

| Gate | Definition |
| --- | --- |
| `states-covered` | Every state from the UX state matrix (initial / loading / empty / partial / error / validation / permission / offline / destructive / success) is rendered correctly for the screen. Screenshots captured per state. |
| `no-console-errors` | Page loads with no console errors or unhandled promise rejections. |
| `keyboard-path` | Every interactive element is reachable by Tab in logical order. No focus traps. |
| `a11y-critical` | All form inputs have labels; errors are associated via aria-describedby and announced; dialogs trap focus and return focus on close. |
| `tokens-not-literals` | No raw hex colors, pixel literals for spacing, or magic radii in component source. All values reference tokens. |

## Dimensions (0..10)

| Dimension | Weight | Definition |
| --- | --- | --- |
| `visual-hierarchy` | 0.15 | Clear primary action; secondary actions distinguishable; information density matches content type. |
| `typography` | 0.10 | Type scale applied consistently; weights used semantically; line heights readable. |
| `spacing-rhythm` | 0.10 | Vertical rhythm present; whitespace appropriate for content density; no inconsistent gaps. |
| `density` | 0.10 | Right level of density for the screen type (table = dense, marketing = sparse). |
| `distinctiveness` | 0.15 | Screen does not look like a generic AI-generated product. Has a deliberate aesthetic direction. |
| `consistency` | 0.10 | Reuses existing tokens, components, and patterns. No one-off designs. |
| `interaction-clarity` | 0.10 | Affordances clear; destructive actions protected; loading and success states obvious. |
| `ux-writing` | 0.10 | Labels, helper text, errors, empty states use plain language; include recovery paths; no `Oops!` / `Just` / `Simply`. |
| `state-completeness` | 0.10 | The full UX state matrix is covered, not just the happy path. |

## Aggregate score

- `aggregate = sum(score * weight) / sum(weight)` — out of 10
- `aggregate_100 = aggregate * 10` — out of 100
- A 100 in dimensions cannot compensate for a failing hard gate.

## Eval cases

The cases in `cases.json` are the reproducible scenarios that drive baseline + with-skill runs. Each case points at a scenario under `configs/opencode/agent-lab/scenarios/`.

## Recording

```
node configs/opencode/agent-lab/runners/opencode.mjs \
  configs/opencode/agent-lab/scenarios/ui/<scenario>.json \
  <workdir> \
  --baseline
```

This produces:
- `results/baseline/<scenario>.json` — the committed baseline
- `results/runs/<timestamp>-<scenario>.json` — the run trace

To run with the skill loaded: invoke the build agent with `nox-ui-engineering` active and use the same scenario.
