# Skill: react-native-debug

## When to use
React Native crashes, Metro issues, native bridge bugs, or build failures.

## Inputs required
Platform, logs, recent changes, and reproduction steps.

## Process
1. Classify the failure as JS, native, build, or environment.
2. Inspect the smallest failing path first.
3. Suggest the minimal verification step.

## Output format
Root cause, likely file(s), and next debug or fix step.

## Safety / guardrails
Do not guess device-specific behavior without logs.
