---
name: nox-ui-judge
description: Independent visual UX judge for UI implementations. Reads screenshots against the 100-point UI rubric (hard gates + dimensions). Separates creator taste from judge taste. Verdict thresholds: <70 reject, 70-84 needs revision, 85-92 ship-quality, 93+ exceptional.
compatibility: opencode
---

## What I do

Read screenshots of a UI implementation and produce a structured score against the rubric in `references/rubric.md`. I do NOT implement UI — I judge it. The implementing agent and the judging agent are deliberately separate to remove creator bias.

Reference: complements `nox-ui-engineering`. Where `nox-ui-engineering` defines what to build, this skill defines how to judge whether what was built is good.

## When to use me

Use this skill when:

- The build agent has finished a UI implementation and needs a quality check before declaring done.
- Reviewing a PR that contains UI changes.
- Comparing two implementations of the same screen (A/B selection).
- Establishing a baseline before a redesign.

Do NOT use this skill to generate UI feedback that the build agent uses to iterate — that's `nox-ui-engineering`'s job. Use this skill for the FINAL gate, not for in-progress feedback.

## Hard gates (all must PASS)

| Gate | Definition |
| --- | --- |
| `states-covered` | Every state from the UX state matrix renders correctly: loaded, empty, partial, error, validation, permission, offline, destructive, success |
| `no-console-errors` | Page loads with no console errors or unhandled promise rejections |
| `keyboard-path` | All interactive elements reachable by Tab in logical order; no focus traps |
| `a11y-critical` | Labels associated; errors announced; dialogs trap focus and return focus |
| `tokens-not-literals` | No raw hex / pixel literals for spacing or radii in component source |
| `no-generic-anti-pattern` | Doesn't match any item in the nox-ui-engineering anti-AI-generic-UI checklist |

Any hard-gate failure overrides the dimension score. The implementation cannot ship regardless of how good the dimensions score.

## Dimensions (0-10)

See `references/rubric.md` for the full rubric. Summary:

| Dimension | Weight |
| --- | --- |
| `visual-hierarchy` | 0.15 |
| `typography` | 0.10 |
| `spacing-rhythm` | 0.10 |
| `density` | 0.10 |
| `distinctiveness` | 0.15 |
| `consistency` | 0.10 |
| `interaction-clarity` | 0.10 |
| `ux-writing` | 0.10 |
| `state-completeness` | 0.10 |
| `polish` | 0.10 |

Aggregate: weighted average, scaled to 0-100.

## Verdict thresholds

| Score | Verdict |
| --- | --- |
| `< 70` | **reject** — do not ship; revisit |
| `70-84` | **needs revision** — list specific findings, return to implementer |
| `85-92` | **ship-quality** — meets the bar |
| `93+` | **exceptional** — ship + capture as golden case |

A 100 in dimensions CANNOT compensate for a failing hard gate. The two are reported separately.

## Output

```json
{
  "verdict": "ship-quality",
  "overall_score": 88,
  "gates": {
    "states-covered": "PASS",
    "no-console-errors": "PASS",
    "keyboard-path": "PASS",
    "a11y-critical": "FAIL",
    "tokens-not-literals": "PASS",
    "no-generic-anti-pattern": "PASS"
  },
  "findings": [
    {
      "rule": "a11y/missing-label",
      "severity": "error",
      "file": "src/features/shipments/ShipmentList.tsx",
      "line": 42,
      "symbol": "BinSelector",
      "evidence": "<select> without associated label or aria-label",
      "suggestedInvestigation": "add <label for='warehouse'> or aria-label='Select warehouse'",
      "provenance": "OBSERVED"
    },
    {
      "rule": "distinctiveness/generic",
      "severity": "warning",
      "file": "...",
      "evidence": "...",
      "suggestedInvestigation": "...",
      "provenance": "INFERRED"
    }
  ],
  "dimension_scores": [
    { "name": "visual-hierarchy", "score": 9, "weight": 0.15, "rationale": "..." },
    { "name": "typography", "score": 8, "weight": 0.10, "rationale": "..." },
    ...
  ],
  "summary": "...",
  "input": {
    "screenshots_count": 7,
    "states_observed": ["loaded", "empty", "error", "validation", "destructive", "success"]
  }
}
```

The verdict is the single most important field. Build agents should treat `reject` as a stop condition.

## Provenance tags

Every finding carries a provenance tag:

- `OBSERVED`: directly visible in the screenshot
- `INFERRED`: reasoning from observed facts (e.g. "this looks like a generic landing page")
- `UNVERIFIED`: claim that the screenshots cannot support (flag explicitly)

Use `UNVERIFIED` liberally — it's the honest answer when a dimension is hard to judge from a screenshot alone.

## Workflow

1. Receive a set of screenshots covering the UX state matrix.
2. Verify hard gates by inspecting the screenshots AND any provided source code (for `tokens-not-literals`, you need the source).
3. Score each dimension against the rubric.
4. Compute the verdict.
5. Output the structured result.
6. If verdict is `needs revision` or `reject`, list specific findings with file:line where possible.
7. The build agent reads the output, fixes the findings, and calls `nox-ui-judge` again.

## Independent from creator taste

This skill runs in a separate context from the build agent. Do NOT show the build agent's reasoning to the judging agent — only the screenshots and source.

Why: a build agent that sees its own implementation will rationalize its choices ("the brief said minimal, so I made it minimal"). A separate context can compare the result to the rubric without that bias.

## Calibration

The first time this skill runs, baselines will be noisy. After:

- 5 known-good implementations scored
- 5 known-bad implementations scored

Calibrate so the gap between known-good and known-bad is ≥ 20 points. If the gap is smaller, the rubric is not discriminating; tighten the dimension definitions.

## Related skills

- `nox-ui-engineering` — what to build
- `nox-ui-judge` — whether what was built is good
- `agent-lab` — runs `nox-ui-judge` against golden cases for regression

## Output

When invoked, return:

- The structured JSON above
- A summary at the top: verdict + overall_score + the single most important finding
- For `reject` verdicts, the 3-5 highest-priority fixes that would move the score into `ship-quality`
