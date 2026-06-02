# Skill: hyprland-debug

## When to use
Hyprland, portal, Wayland, or compositor regressions.

## Inputs required
Symptoms, logs, and recent package or config changes.

## Process
1. Identify whether the issue is compositor, portal, input, or app-specific.
2. Check config, service state, and session env in that order.
3. Prefer reversible fixes and reloads first.

## Output format
Probable cause, config or service target, and recovery command.

## Safety / guardrails
Avoid destructive resets unless the current config is backed up.
