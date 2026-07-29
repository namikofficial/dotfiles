# AGENTS.md — dotfiles (Arch + Hyprland + NoxFlow)

This repo has **two independent codebases** in one workspace. Know which one you're working on before acting.

## Repo map

```
shell/noxflow/      QML desktop shell (Quickshell) — Bar, Launcher, Overview,
│                   Capture, Calendar, Dashboard, Settings, ControlCentre,
│                   NotificationCentre, NoxIsland, RadialWheel
├── shell.qml       Entry point — wires all surfaces
├── surfaces/       One subdir per major panel
├── components/     Shared UI primitives (Elevation, Card, Toggle, etc.)
├── theme/          Tokens.qml + ThemeProfiles — M3 design tokens
├── core/           PanelController, MorphSurface
└── MorphRegistry   Chip-geometry singleton for morph animations

core/               Rust workspace members:
├── noxd/           Desktop state + IPC daemon (zbus, ureq)
├── noxflow-ipc/    Versioned IPC contract (serde)
├── noxflow-config/ Validated config loading (toml, serde)
├── noxflow-state/  Persistent user state (toml, serde)
└── noxflow-diagnostics/ Structured diagnostics

cli/noxctl/         Rust CLI for shell/daemon control (clap)

setup/              80+ shell scripts — bootstrap, check, install, health
ai/                 System prompts, skill files, templates for AI assistants
configs/opencode/   OpenCode config, MCP scripts, plugins, skills
docs/               40+ docs — runbook, keybinds, IPC protocol, architecture
```

## Key commands

### Rust workspace
```sh
cargo build --workspace --release   # Build noxd + noxctl
cargo test --workspace               # All Rust tests
cargo check --workspace              # Fast compilation check
```
Test files: `core/noxd/tests/server.rs`, `cli/noxctl/tests/cli.rs`

### Shell scripts
```sh
./setup/check-shell.sh --all   # shellcheck (severity=error) + shfmt -d -i 2 -ci
```

### QML shell
```sh
systemctl --user restart noxflow-shell.service   # Restart after QML changes
journalctl --user -u noxflow-shell --no-pager    # Check for warnings/errors
```
No formal QML test runner. Smoke tests: `tests/smoke/test-noxflow-surfaces.sh`
Protocol unit tests: `shell/noxflow/tests/test_protocol.js`

### Dotfiles health
```sh
./setup/check-dotfiles.sh --all   # Shell script checks
dev-health                        # Fast workstation readiness
dev-health --full                 # Deep weekly health
dev-health --json                 # Machine-readable
upgrade-verify                    # Post-upgrade verification
workstationctl verify all         # Workstation verification
```

### Apply changes
```sh
exec zsh                                                           # Reload shell
./setup/bootstrap.sh                                               # Full setup
~/.config/hypr/scripts/hypr-reload-safe.sh                        # Reload Hyprland
systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
~/.config/hypr/scripts/theme-pass.sh                              # GTK theme pass
~/.config/hypr/scripts/panel-switch.sh show                       # Refresh shell
~/.config/hypr/scripts/launcher.sh --warm-cache                   # Warm launcher cache
```

## Architecture must-knows

- **IPC wiring:** Shell → `NoxdClient.qml` → Unix socket → `noxd` daemon.
  Toggle surfaces via `noxctl <surface>` or `quickshell ipc -p ~/.config/noxflow/shell call noxctl toggleLauncher`.

- **Shell entry:** `shell/noxflow/shell.qml` — wires all surfaces.
  `PanelController` owns major-panel selection. `MorphSurface` is the only major-panel layer-shell window.

- **Wayle is the fallback shell.** NoxFlow is primary. Never start both.
  Current state: `wayle.service` should be stopped+disabled, `noxflow-shell.service` active.

- **OpenCode config** lives in `configs/opencode/opencode.local-llamacpp.json` (not root `opencode.json`).
  Global instructions: `ai/system/GLOBAL_SYSTEM.md`. Skills: `configs/opencode/skills/`.

- **NVIDIA hybrid laptop (RTX 4050 + Intel).** DRM KMS is blacklisted on NVIDIA — compositor uses Intel iGPU. CUDA/compute uses NVIDIA base module. Do not hardcode DRM card numbers.

- **Settings system:** `settingsctl` for validated state updates. Schema-driven.
  Local overrides: `settings/state.local.json` (gitignored).

- **Private submodule:** `private/scripts` (requires SSH access). Skip `git submodule update` if unavailable.

## Session workflow

1. Branch is `inspired-rewrite` — active dev branch.
2. After QML edits: restart shell service, check journal for warnings.
3. After Rust edits: `cargo check --workspace` then `cargo test --workspace`.
4. After shell script edits: `./setup/check-shell.sh --all`.
5. Docs generation: `./setup/generate-keybind-docs.py` + `./setup/check-keybind-docs.sh`.

## Repo quirks

- **No CI/CD** — no `.github/` or CI config.
- **`Cargo.lock` is tracked** (for desktop binary reproducibility).
- **`.gitignore` excludes:** `logs/`, `settings/state.local.json`, `.noxflow/`, `noxflow.local.toml`, `target/`, OAuth tokens in `external/waylandar-backend/`.
- **Keybind docs** `docs/KEYBINDS.md` are generated from Lua. Change Lua bindings first, then regenerate.
- **Active refactor phases** tracked in `TASKS.md`. `PLAN_v2.md` supersedes `PLAN.md`.
- **Shell compilation criteria:** zero errors, zero warnings. Benign exception: `FileView: file does not exist` on first run.
- **Reference repos** in `REFERENCES.md` — pinned commits, don't install as deps.
