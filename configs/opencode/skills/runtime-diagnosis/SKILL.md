---
name: runtime-diagnosis
description: Consume a runtime-evidence packet and identify the most likely failure boundary. Output is a ranked list of hypotheses with supporting and contradicting evidence, plus the cheapest discriminating test for each. Reads evidence, does not collect it.
compatibility: opencode
---

## What I do

Take an evidence packet produced by `runtime-evidence` and diagnose where the system went wrong. I do not collect new evidence — I read what was collected and reason about it.

The output is a ranked list of failure boundaries (browser / network / server / DB / cache / client-state) with the evidence supporting each, the evidence contradicting each, and the cheapest discriminating test that would prove or disprove each hypothesis.

## When to use me

Use this skill when:

- You have an evidence packet from `runtime-evidence` and need to interpret it.
- The diagnosis is unclear: multiple systems could be at fault and you need to narrow it.
- You need to communicate "where I think the bug is" in a structured, falsifiable way.

Do NOT use this skill without an evidence packet. If you don't have one, run `runtime-evidence` first.

## Inputs

A path to an evidence packet JSON file. The packet shape is documented in `runtime-evidence/references/packet-schema.md`.

## Output

A diagnosis document with this structure:

```markdown
# Diagnosis: <user_action.description>

## Most likely boundary: <boundary>

Confidence: <0.0–1.0>

## Hypothesis H1: <hypothesis>
- Boundary: <browser | network | server | db | cache | client-state>
- Supporting evidence:
  - <evidence packet field>: <quote>
- Contradicting evidence:
  - <evidence packet field>: <quote>
- Cheapest discriminating test: <single test that would confirm/refute>
- Confidence: <0.0–1.0>

## Hypothesis H2: ...

## Recommended next action
<one specific thing to do, with the agent / skill that should do it>

## Open questions
<what we don't know that would change the diagnosis>
```

Rank hypotheses by confidence. Lead with the most likely.

## How to reason

For each candidate boundary (browser, network, server, DB, cache, client-state), ask:

1. **What does the evidence at THIS boundary show?**
2. **Is this boundary consistent with the user-observed symptom?**
3. **What would have to be true at OTHER boundaries for THIS boundary to be the cause?**

Most bugs have one boundary that explains most of the evidence, and the cause propagates from there. Your job is to find the originating boundary, not to explain away the symptoms.

## The discriminating-test discipline

For each hypothesis, name the single cheapest test that would confirm or refute it. The discipline matters: without it, you can list 10 plausible hypotheses and never commit to one.

Examples:

- "Send the same network request directly with curl. If it succeeds, the bug is in the browser client."
- "Add a single console.log in the suspected function. If it doesn't fire, the code path is wrong."
- "Run the suspected DB query in psql with the exact params from the packet. If it returns the expected data, the query logic is fine."

The cheapest discriminating test is usually the one that takes under a minute.

## Anti-patterns

- **Reaching for the most familiar boundary.** "It's probably the database" is not a diagnosis; it's a habit.
- **Ignoring the user's exact symptom.** If the user says "the screen flashes and resets", no amount of network analysis explains it.
- **Listing every plausible hypothesis equally.** Pick the most likely one and commit.
- **Skipping the discriminating test.** Without it, your hypothesis is unfalsifiable.
- **Refusing to commit.** If the evidence strongly supports one hypothesis, say so. Hedging without justification is not rigor.

## Related skills

- `runtime-evidence` — produces the packet this skill consumes
- `differential-debugging` — explicitly structures the competing-hypotheses analysis this skill does informally
- `regression-hunter` — answers a different question: "what used to work that doesn't now?"

## Output

When invoked, return:

- The diagnosis document above
- A short summary at the top: most likely boundary, confidence, recommended next action
- Any patterns you noticed that should become new rules in the invariant registry
