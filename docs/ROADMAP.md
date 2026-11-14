# Roadmap

Only unfinished work belongs here. Completed investigations and historical
plans are intentionally not repeated.

Each item names the code that still has to change, so an agent can check the
claim against the tree instead of taking it on trust.

## P1 — shell ownership

- Replace the multipurpose `NoxIsland` with a narrow, reduced-motion-aware
  Activity Capsule; remove launcher/calendar/hover-dashboard ownership from
  it. The island still owns the launcher
  (`shell/noxflow/island/IslandHost.qml`: `openLauncher`, `closeLauncher`,
  `toggleLauncher`) and the calendar/dashboard layers.

## P1 — live theme runtime

- Publish the complete adapter set atomically. `hypr/scripts/theme-sync.sh`
  still writes each adapter in place (`cat >"$rofi_colors"`,
  `cat >"$kitty_colors"`, `cat >"$tmux_colors"`), so a failure halfway
  through leaves a mixed theme on screen. Stage the files and move them into
  place as a set; add rollback and rapid-switch tests.
- Keep a last-known-good theme state. `shell/noxflow/theme/Tokens.qml`
  watches the palette file and falls back to the static profile on first
  boot, but a failed later hydration has no valid previous palette to fall
  back to.

## P2 — source-of-truth cleanup

- Give each installed unit a single installer. `setup/bootstrap.sh`,
  `setup/bootstrap-noxflow.sh` and `setup/install-noxflow-foundation.sh`
  all link `noxflow-shell.service` and `noxflow-fallback.service`, and the
  last two both link `noxd.service`. See
  `docs/SETUP_OWNERSHIP_AUDIT.md`.
- Split the link ownership between `setup/bootstrap.sh` and
  `setup/normalize-links.sh`, which both write the same eleven paths.
- Give the shell runtime bridges one owner: `setup/install-shell-runtime-bridges.sh`
  links the same four `~/.local/bin` targets as the bootstrap.
- Register the browser MCP server in Claude Code's user scope, or drop the
  entry that `setup/bootstrap.sh` links to `~/.claude/.mcp.json`.
- Untrack `aliases.local.zsh` and ignore it: it is a personal overlay that
  `zshrc` sources only when present.
- Give `setup/test-local-models.sh` a headless mode, or keep it as the one
  manual suite: it needs a running `llama-server` and the downloaded models.
- Keep the daemon configuration and its schema in step. The Rust schema in
  `core/noxflow-config` is authoritative; `config/default.toml` documents
  it and `configs/noxflow/config.toml` is the installed instance, and both
  are checked by `core/noxflow-config/tests/repository_config.rs`. A new
  setting belongs in the schema first.
- Introduce a machine-readable service-ownership matrix and package profiles.
- Extend keybind generation to cover the remaining non-Lua helper bindings and
  conflict checks.
- Archive obsolete shell plans after the migration milestones above land.

## Verification still required

- Quickshell runtime smoke test on the active session.
- Wallpaper corpus coverage for dark, bright, monochrome, saturated and noisy
  images, including adapter syntax and rollback failure paths.
- Device/session checks for live theme reload, focus, click-through masks and
  safe-mode exclusivity.
