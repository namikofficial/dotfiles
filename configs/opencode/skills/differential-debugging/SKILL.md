---
name: differential-debugging
description: For difficult bugs, generate ≥ 3 competing hypotheses with supporting evidence, contradicting evidence, and the cheapest discriminating test per hypothesis. Then run the cheapest test that discriminates. Scientific debugging pattern.
compatibility: opencode
---

## What I do

Stop asking "what's wrong?" and start asking "what are the possible failures, and which one does the evidence favor?" This is essentially scientific debugging applied to software.

## When to use me

Use this skill when:

- A bug has been investigated twice without resolution.
- Multiple plausible explanations exist for the symptom.
- The bug crosses system boundaries (UI / API / DB / cache / external service).
- A previous fix attempt regressed or didn't actually fix the issue.

Do NOT use this skill for trivial bugs (typos, single-line fixes) — it adds overhead without value.

## The discipline

For any non-trivial bug, before reading code, write down **at least 3 competing hypotheses** for what's wrong. For each:

- **Supporting evidence:** what we already know that makes this hypothesis more likely
- **Contradicting evidence:** what we already know that makes this hypothesis less likely
- **Cheapest discriminating test:** the single fastest test that, if it goes one way, confirms the hypothesis; if it goes the other, refutes it

Then run the cheapest discriminating test across all hypotheses. Pick the hypothesis the test favors. If none of the tests discriminate, gather more evidence and return to the hypothesis list.

This is faster than reading code because it forces you to commit to falsifiable claims.

## A worked example

### The user report

> "I edit a part, click save, the UI says saved, but a refresh shows the old value."

### Hypothesis H1: optimistic update without rollback

- **Supporting evidence:** the UI updates immediately, suggesting client-side state is set before server confirms.
- **Contradicting evidence:** the user says the UI says "saved" — that comes from the success callback, which only fires after the server confirms. If optimistic-only, the UI would say "saved" only after a successful response.
- **Cheapest discriminating test:** open DevTools, watch the network panel on save. If a POST is sent and returns 200, H1 is partially refuted (the request did succeed). If there's no POST or it returns an error, H1 gains weight.

### Hypothesis H2: wrong update payload

- **Supporting evidence:** the server's response might be 200 but the data didn't actually update because the body was wrong.
- **Contradicting evidence:** none specific.
- **Cheapest discriminating test:** copy the network request from DevTools and replay it with curl using the same body. If curl updates the value, the client is fine and the bug is elsewhere. If curl also fails to update, the server is rejecting the payload.

### Hypothesis H3: cache invalidation missing

- **Supporting evidence:** the refresh shows the old value, which is consistent with a stale cache. The server might have updated, but the client query is returning cached data.
- **Contradicting evidence:** the user said "the UI says saved", which suggests the update did trigger some success path that should have invalidated the cache.
- **Cheapest discriminating test:** open React Query devtools (or equivalent). Look at the query cache for the relevant key. If the cached data shows the new value, the cache isn't the issue. If it shows the old value, invalidation is missing.

### H4: server returns updated entity but client displays stale one

- **Supporting evidence:** the API might return the updated entity, but the client is using a different field to render the displayed value (e.g. `lastUpdated` instead of `name`).
- **Contradicting evidence:** none specific.
- **Cheapest discriminating test:** add a `console.log(response)` in the mutation success callback. Compare the response body to what the UI renders.

## Hypothesis ranking after one round

After running one discriminating test:

- H2 confirmed (curl shows the request payload is wrong) → fix the payload construction
- H1 refuted
- H3 refuted (cache is fine)
- H4 not yet tested, but lower priority because H2 is the root cause

## The template

Use this for every non-trivial bug:

```markdown
## Bug: <one-line user report>

### H1: <hypothesis>
- Supporting evidence:
- Contradicting evidence:
- Cheapest discriminating test:
- Current confidence: <0.0–1.0>

### H2: <hypothesis>
...

### H3: <hypothesis>
...

### Round 1 test result
<what you did, what you learned, which hypotheses gained/lost confidence>

### Current best hypothesis
H2 — <one-line summary>
Confidence: <0.0–1.0>

### Next round
<what you need to do to confirm or refute the current best hypothesis>
```

## Why this works

- **Avoids confirmation bias.** Listing multiple hypotheses before checking any prevents "I think it's the cache" → looking only at the cache.
- **Each round produces a falsifiable claim.** You can be wrong, and the next test catches it.
- **Cheapest test first.** You converge on the answer in fewer total actions.
- **Documented reasoning.** If the bug recurs, the previous investigation is reusable.

## Anti-patterns

- **One hypothesis at a time.** You'll lock onto the first one and miss the actual cause.
- **Tests that don't discriminate.** "Restart the server" tells you nothing about whether the bug is in the cache.
- **Skipping the contradicting-evidence step.** Without it, you rationalize away the evidence that doesn't fit.
- **Tests that take hours.** If the test takes longer than 5 minutes, find a cheaper one or simplify the hypothesis.
- **Bailing out before testing.** "I'm pretty sure it's H2" is not a hypothesis test; it's a guess.

## Related skills

- `bug-repro` — produces the initial reproducer. Differential-debugging takes the reproducer and structures the investigation.
- `runtime-evidence` — collects the evidence that informs the hypothesis list.
- `runtime-diagnosis` — produces a ranked hypothesis list from an evidence packet; differential-debugging extends that with explicit discriminating tests.

## Output

When invoked, return:

- The hypothesis list (≥ 3) with full supporting / contradicting / discriminating-test breakdown
- Round 1 test results
- Updated confidence per hypothesis
- The current best hypothesis and the next-round test
- A summary at the top: "best hypothesis is H2 with 0.8 confidence; next step is X"
