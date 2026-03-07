# Settings System

This directory is the canonical source of truth for user-configurable desktop settings.

- `schema.json`: structure and validation contract.
- `defaults.json`: baseline values tracked in git.
- `state.json`: user-selected overrides tracked in git (can be replaced with local-only workflow later).
- `state.local.json`: optional local-only overrides (gitignored).
- `profiles/*.json`: machine profile overlays selectable with `settingsctl profile apply <name>`.

Use `hypr/scripts/settingsctl` to read, write, validate, and apply settings.
