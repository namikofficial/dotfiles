# AI Workbench desktop integration

The TypeScript AI Workbench is the canonical owner of project selection, active context, active work, checks, services and runtime state. Dotfiles observes Hyprland and presents cached state; it does not create a second durable registry.

## Current flow

```mermaid
flowchart LR
  Hypr[Hyprland events] --> Observer[Desktop observer]
  Observer -->|DesktopObservation| API[Workbench API]
  API --> DB[(Workbench SQLite)]
  API --> Status[ProjectStatus aggregator]
  Status --> Cache[XDG project-status-v1 cache]
  Cache --> Work[Wayle Work cluster]
  Cache --> Kage[Kage compatibility adapter]
  Cache --> Rofi[Rofi cockpit]
  Cache --> Resume[Project resume]
  Cache --> Scratch[AI / logs scratchpads]
  API -->|normalized SSE| Notify[Notification bridge]
  Notify --> DesktopNotify[Wayle DND + notify-send]
```

The observer refreshes status after the resolved project changes or the cache expires. Wayle only reads the compact cache every five seconds; it does not run Git, Docker, model, or network probes.

## Wayle Work cluster

The right side of the bar contains one grouped cluster:

```text
[Project] [Git/Checks] [Work] [AI]
```

- Project shows selection, pin, confidence and stale state. Left click opens the project cockpit; right click switches the canonical Workbench selection.
- Git shows branch, changed/staged counts and conflicts.
- Work shows the active task, state and progress.
- AI shows the model role and normalized runtime state. Unknown is shown honestly until model supervision is connected.

Workbench launch actions use project-aware deep links: project overview, Work, Ask, Planner, and Checks inherit the cached canonical project ID.

All four chips are rendered by `hypr/scripts/workbench-wayle-status`. Tooltips are human text, not raw JSON. Offline fallback is read-only and visibly stale/unavailable.

## Desktop commands

```bash
kage project current --wayle
kage project current --json
kage project status
kage project refresh
workbench-wayle-status project
workbench-wayle-status git
workbench-wayle-status work
workbench-wayle-status ai
workbench-project-switcher
```

`kage project refresh` prefers the Workbench status API and falls back to the legacy detector only when Workbench is unavailable. The old Kage cache remains for rollback during migration.

The project switcher fails closed if Workbench is offline. It never writes a local selection; it sends the chosen registered project ID to `/context/selection` and then refreshes the compact cache.

## Runtime configuration and startup

Workbench-aware desktop scripts read `~/.config/ai-workbench/runtime.env`, the same central configuration consumed by the Workbench systemd user units. `workbench-runtime-env.sh` supplies local-first defaults when the file is absent. Kage, the observer, Rofi switcher, Workbench launcher, and AI context helpers no longer need separate Workbench/model port ownership.

`open-ai-workbench.sh` probes the core `/ready` endpoint and starts `ai-workbench.target` when the user units are installed. If systemd startup is unavailable or fails, it preserves the existing `ai-workbench` tmux fallback. Optional model and vector services do not prevent the project control plane from opening.

The desktop observer unit also reads the central environment file. Install and rollback procedures live in the AI repository's `docs/RUNTIME_SUPERVISION.md`; installing services is explicit and is not performed by the dotfiles scripts.

The `ai-workbench-notification-bridge` graphical-session service consumes the canonical SSE stream and keeps only a private XDG reconnect cursor. It notifies for approvals, run/check failures, run completion, manually requested indexing, blocked work and runtime loss. Routine focus, retrieval and model-call events are ignored. Wayle DND and `AI_WORKBENCH_NOTIFICATIONS_ENABLED=false` suppress display without losing the event cursor. Notification actions open canonical Workbench deep links when supported.

## Interactive workflow secrets

Terminal and tmux workflows use `workbench-workflow-launch.py`. The API-authorized capability contains the structured
command, canonical context identifiers, and approved secret names, but never their values. Configure the same private
provider path used by Workbench in `~/.config/ai-workbench/runtime.env`:

```bash
AI_WORKBENCH_SECRET_FILE=/home/namik/.config/ai-workbench/workflow-secrets.env
```

The provider uses `NAME=value` entries and must be an absolute, canonical regular file owned by the current user with
mode 0600 or stricter. The launcher rejects symlinks, resolves only names approved by both the project manifest and
command, deletes its one-use capability before starting the child, and never adds values to API calls, logs, caches,
SQLite, command arguments, or the capability file. The child receives a reduced ambient environment plus canonical
Workbench identifiers and the explicitly requested values.

## Scratchpads and resume

Project resume, AI helper context, and AI/log scratchpad launch now prefer the canonical cached project path. New scratchpad processes receive `AI_WORKBENCH_PROJECT_ID`, `AI_WORKBENCH_PROJECT_NAME`, `AI_WORKBENCH_TASK_ID`, `AI_WORKBENCH_RUN_ID`, and `AI_WORKBENCH_SESSION_ID` alongside the path. Their terminal title shows the visible project identity. Explicit `NOXFLOW_AI_CONTEXT` and `NOXFLOW_SCRATCH_PIN_PROJECT_PATH` remain supported.

The standalone AI helper exports the same project, session, task and run identifiers before launching Codex.
OpenCode inherits them through the AI scratchpad shell. Missing or stale cache data remains read-only fallback; these
clients never create a second session store.

An existing interactive scratchpad is preserved when project focus changes. The manager notifies that it remains pinned instead of destroying unsaved terminal work. Close and reopen a pad to follow the current project, or set `NOXFLOW_SCRATCH_PIN_PROJECT_PATH` for an intentional persistent pin.

## Offline behavior

When Workbench is unavailable:

- Wayle returns valid JSON payloads with an unavailable/stale tooltip.
- Project and Git chips may use the existing legacy Kage cache.
- Canonical project selection and other mutations fail clearly.
- Kage’s old detector remains a rollback fallback.
- Terminals, scratchpads and project resume continue to launch.

## Validation

```bash
bash -n hypr/scripts/ai-workbench-observer hypr/scripts/kage \
  hypr/scripts/workbench-runtime-env.sh hypr/scripts/open-ai-workbench.sh \
  hypr/scripts/workbench-wayle-status hypr/scripts/workbench-project-switcher \
  hypr/scripts/kage-project-rofi.sh hypr/scripts/project-resume.sh \
  hypr/scripts/scratchpad-manager.sh hypr/scripts/ai-helper-context.sh

shellcheck hypr/scripts/ai-workbench-observer hypr/scripts/kage \
  hypr/scripts/workbench-runtime-env.sh hypr/scripts/open-ai-workbench.sh \
  hypr/scripts/workbench-wayle-status hypr/scripts/workbench-project-switcher \
  hypr/scripts/kage-project-rofi.sh hypr/scripts/project-resume.sh

python3 -c 'import tomllib; tomllib.load(open("wayle/config.toml", "rb"))'
wayle config schema >/dev/null
./setup/test-workbench-desktop.sh
python3 setup/test-workbench-notification-bridge.py
python3 -m unittest setup/test-workbench-workflow-launch.py
```

`setup/check-local.sh` currently also reports pre-existing shfmt differences across many unrelated scripts. The Workbench scripts are validated directly so that legacy formatting is not rewritten as part of this migration.

## Remaining Phase 5 compatibility work

- Replace project-specific tmux scene conventions with approved manifest scene templates.
- Add an event/file watcher bridge for faster Git-to-cache refresh without frequent polling.
- Retire the old Kage watcher only after manual desktop parity and rollback validation.
