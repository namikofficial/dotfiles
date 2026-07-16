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
project-profile dev nox-billings
project-profile launch noxcrm
project-profile check dotfiles
project-resume
```

Short alias:

```sh
ppr status
ppr launch dotfiles
```

`project-profile dev <profile>` creates or attaches to the project's named tmux layout: API, web, mobile, and logs. `tmux` and `launch` use that same layout for NoxCRM, Nox Billings, and TrackMe.

Nox Billings helpers:

```sh
nox-billings
nox-billings-edit
nox-billings-emulator
```

## Client Backups

Client source repositories and remote staging/production database dumps are encrypted with Restic before being synchronized from `~/syncthing/client-backups`. Configure the backup-only SSH hosts and Restic password outside Git, then enable the timer:

```sh
sudo pacman -S restic
client-backup init-config
$EDITOR ~/.config/nox-backup/client-backup.conf
setup/configure-client-backup.sh
client-backup verify
```

The timer runs nightly, retains 30 daily snapshots, and does not dump local development databases. `client-backup status` shows the latest snapshot. Restore only into a new non-production database.

`project-resume` is the opposite path: it uses the focused repo to restore the current project session, reopen the editor, and bring back Sidecar or related scratchpads.

## Local AI Routing Policy

The TypeScript AI Workbench at `~/Documents/code/ai` is the canonical application for project indexing, retrieval, sessions, plans, dev runs, memory, and MCP. Dotfiles owns the desktop launchers and local model runtime. The legacy Python RAG remains a migration fallback only.

Use one local router path unless explicitly testing something else:

- router: `llama-swap-manager`
- endpoint: `http://127.0.0.1:8080/v1`
- model alias: `local`
- default model: `qwen3-4b-local`

Routing rules:

- Primary daily model: `qwen3-4b-local` via the `local` alias.
- Agent/tool sessions: `granite-agent`.
- Embeddings: separate nomic llama.cpp server on port 8081.
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

Workbench status:

```sh
cd ~/Documents/code/ai
pnpm cli -- health --deep
```

## Scratchpad Roles

Keep scratchpads role-specific instead of treating them as interchangeable terminals:

- `Super+\`: Scratch Hub for all roles, Sidecar actions, and the full scene
- `Super+Shift+\`: full work scene with main window, AI, and runner/logs
- `Super+Alt+\`: AI role, project-rooted shell for OpenCode/local models
- `Super+Ctrl+\`: runner/logs role, project-rooted command terminal
- `Super+Ctrl+Alt+\`: database role
- Obsidian and Browser DevTools roles: use the hub cards
- ``Super+` ``: show/hide Sidecar, ``Super+Shift+` ``: move focused window to Sidecar, ``Super+Ctrl+` ``: stash, ``Super+Shift+1..0``: move focused Sidecar window back to a workspace
- Multiple Sidecar windows tile inside the shelf instead of stacking on top of each other.

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
