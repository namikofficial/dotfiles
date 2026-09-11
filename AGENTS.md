@/home/namik/.codex/RTK.md

# Dotfiles repository guidance

This repository contains independent workstation configuration surfaces. Read
the nearest nested `AGENTS.md` before editing a scoped area:

- `shell/noxflow/AGENTS.md` — Quickshell/QML desktop shell.
- `core/AGENTS.md` — Rust workspace and `cli/noxctl`.
- `setup/AGENTS.md` — bootstrap, health, and shell scripts.
- `configs/opencode/AGENTS.md` — OpenCode models, agents, MCP, skills, and links.

## Repository map

- `shell/noxflow/`: NoxFlow shell; `shell.qml` is the entry point.
- `core/` and `cli/noxctl/`: desktop daemon, IPC, config/state, diagnostics, and CLI.
- `setup/`: workstation bootstrap, health, installers, and verification control planes.
- `configs/opencode/`: canonical OpenCode configuration and local plugins.
- `ai/`: shared system prompts, templates, and assistant skills.

## Invariants

- NoxFlow is the primary shell. Wayle is the fallback; do not run both.
- Shell IPC flows through `NoxdClient.qml` to the `noxd` Unix socket.
- OpenCode's canonical config is `configs/opencode/opencode.local-llamacpp.json`,
  linked to `~/.config/opencode/opencode.json` by `setup/normalize-links.sh`.
- Use `settingsctl` for validated settings updates; do not edit generated local state.
- The NVIDIA hybrid laptop uses Intel for compositor DRM and NVIDIA for compute;
  never hardcode DRM card numbers.
- `private/scripts` is an optional SSH-backed submodule; do not require it for checks.

## Working rules

1. Inspect the current branch, status, nearest instructions, callers, and tests before editing.
2. Preserve unrelated dirty work and stage exact paths only when staging is requested.
3. Run the cheapest relevant verification after each scoped change; never claim an unobserved result.
4. Use `git diff --check` on changed text. Do not publish, push, commit, or alter credentials unless the user explicitly requests it.

Common checks are `./setup/check-shell.sh --all`, `./setup/check-dotfiles.sh --all`,
`cargo check --workspace`, and `cargo test --workspace`; use only those relevant
to the changed surface.
