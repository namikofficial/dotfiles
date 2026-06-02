# Skill: code-review

## When to use
After a diff, PR, or risky refactor.

## Inputs required
Diff, scope, risk areas, and test status.

## Process
1. Scan changed files and nearby context.
2. Check correctness, regressions, and missing tests.
3. Return only actionable findings.

## Output format
Bulleted findings with severity, file path, and fix direction.

## Safety / guardrails
Ignore style-only issues and untouched files.
