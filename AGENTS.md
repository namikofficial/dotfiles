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
- `ssh/`: the managed `~/.ssh/config` source; installed by `setup/install-ssh-config.sh`.
- `configs/opencode/`: canonical OpenCode configuration and local plugins.
- `configs/pi/`: canonical pi model catalogue for the local llama.cpp router.
- `system/llama-router/`: llama.cpp router preset template, renderer and control script.
- `ai/`: shared system prompts, templates, and assistant skills.

## Invariants

- NoxFlow is the primary shell. Wayle is the fallback; do not run both.
- Shell IPC flows through `NoxdClient.qml` to the `noxd` Unix socket.
- OpenCode's canonical config is `configs/opencode/opencode.local-llamacpp.json`,
  linked to `~/.config/opencode/opencode.json` by `setup/normalize-links.sh`.
- pi's canonical model catalogue is `configs/pi/models.json`, linked to
  `~/.pi/agent/models.json` by `setup/normalize-links.sh`.
- The local llama.cpp router runs with `--models-max 1` and keeps one model
  resident. The llama.cpp default of four is an immediate VRAM OOM on the
  6 GB card. Lane context sizes are measured ceilings; do not widen them.
- Use `settingsctl` for validated settings updates; do not edit generated local state.
- The NVIDIA hybrid laptop uses Intel for compositor DRM and NVIDIA for compute;
  never hardcode DRM card numbers.
- `private/scripts` is an optional SSH-backed submodule; do not require it for checks.

## Working rules

1. Inspect the current branch, status, nearest instructions, callers, and tests before editing.
2. Preserve unrelated dirty work and stage exact paths only when staging is requested.
3. Run the cheapest relevant verification after each scoped change; never claim an unobserved result.
4. Use `git diff --check` on changed text. Do not publish, push, commit, or alter credentials unless the user explicitly requests it.
5. For home/system discovery, name exact roots and use shallow depth/excludes.
   Never recursively search `.codex/sessions`, browser profiles, caches,
   dependencies, build output, `.git`, or credential stores. Byte-cap unknown
   output and summarize structured data mechanically.

Common checks are `./setup/check-shell.sh --all`, `./setup/check-dotfiles.sh --all`,
`cargo check --workspace`, and `cargo test --workspace`; use only those relevant
to the changed surface.
