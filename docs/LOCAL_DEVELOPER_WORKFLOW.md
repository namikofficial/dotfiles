# Local Developer Workflow

This is the source-of-truth workflow for day-to-day development on this workstation.

## Daily Readiness

Run this before focused work:

```sh
dev-health
```

Use the deeper path when something feels off or after a system update:

```sh
dev-health --full
```

The fast check covers:

- dotfiles git state
- core CLI/editor availability
- settings links and generated config health
- stale retired-stack references
- shell script lint/format checks when `shellcheck` and `shfmt` are installed
- Hyprland/Wayle/portal status
- clipboard watcher state
- local AI/RAG status
- known project profile state
- disk pressure

## Guardrails

Run this after desktop-stack or docs cleanup:

```sh
dotfiles-stale-check
```

It blocks retired panel/power-stack guidance and retired local-AI endpoints from creeping back into active docs/scripts.

Run shell checks directly when editing scripts:

```sh
setup/check-shell.sh
```

## Project Profiles

Known profiles:

```sh
project-profile list
project-profile status
```

Useful actions:

```sh
project-profile path noxcrm
project-profile edit noxcrm
project-profile tmux noxcrm
project-profile launch noxcrm
project-profile check dotfiles
```

Short alias:

```sh
ppr status
ppr launch dotfiles
```

The profile command is intentionally conservative. `launch` opens the editor and a project-rooted tmux shell; it does not start backend/mobile stacks automatically.

## Local AI Routing Policy

Use one local router path unless explicitly testing something else:

- router: `llama-swap-manager`
- endpoint: `http://127.0.0.1:8080/v1`
- model alias: `local`
- default model: `qwen3-8b`

Routing rules:

- Primary daily model: `qwen3-8b` via the `local` alias.
- Fast fallback: `gemma-3-4b`.
- Coding-focused sessions: `qwen-coder-7b`.
- Use local helper scripts for shell explanations, commit messages, short reviews, and clipboard summaries.
- Use `rag quick` / `rag deep` when repo-grounded context matters.
- Use OpenCode from the AI scratchpad when you want an interactive local-agent loop.
- Use cloud tools only when explicitly chosen for a task that exceeds local model quality or context.

Status commands:

```sh
local-ai-runtime status
llama-swap-manager status
rag doctor
```

## Scratchpad Roles

Keep scratchpads role-specific instead of treating them as interchangeable terminals:

- `Super+\`: Scratch Hub for all roles, Sidecar actions, and the full scene
- `Super+Shift+\`: full work scene with main window, AI, and runner/logs
- `Super+Alt+\`: AI role, project-rooted shell for OpenCode/local models
- `Super+Ctrl+\`: runner/logs role, project-rooted command terminal
- `Super+Ctrl+Alt+\`: database role
- Obsidian and Browser DevTools roles: use the hub cards
- ``Super+` ``: smart Sidecar send/hide/restore-latest, ``Super+Ctrl+` ``: stash, ``Super+Shift+` ``: restore latest, ``Super+Alt+` ``: show/hide

## Desktop Recovery

Use the recovery menu when the desktop is functional but one layer is stale:

```sh
~/.config/hypr/scripts/desktop-recovery.sh
```

It offers:

- run `dev-health`
- restore Wayle panel
- restart portals
- safe Hyprland reload
- reapply theme
- open desktop logs
- run settings doctor
- show project profile status

The same recovery action is available from Quick Actions and the desktop command palette.
