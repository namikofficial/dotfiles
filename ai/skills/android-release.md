# Skill: android-release

## When to use
Preparing or debugging Android release builds.

## Inputs required
App variant, signing setup, CI or local path, and failing step.

## Process
1. Validate versioning, env vars, signing, and Gradle task selection.
2. Check release-only flags and asset bundling.
3. Confirm the expected artifact output.

## Output format
Release checklist and exact command sequence.

## Safety / guardrails
Never print or commit signing secrets.
