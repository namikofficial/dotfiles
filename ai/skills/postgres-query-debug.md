# Skill: postgres-query-debug

## When to use
Slow queries, wrong results, lock contention, or bad plans.

## Inputs required
SQL text, schema context, expected result, and EXPLAIN output if available.

## Process
1. Validate logic before tuning.
2. Inspect indexes, joins, filters, and sort paths.
3. Recommend the smallest safe query or index change.

## Output format
Diagnosis, suspected bottleneck, and concrete SQL fix.

## Safety / guardrails
Do not recommend destructive maintenance commands casually.
