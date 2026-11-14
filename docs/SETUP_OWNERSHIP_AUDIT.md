# Setup ownership audit

Duplicate scripts, competing owners and dead references in `setup/`, found by
reading the code rather than by listing filenames. Each finding names the lines
that prove it and states whether it is open or already resolved.

## 1. Three scripts link the same systemd units — open

- `setup/bootstrap.sh` links `noxflow-shell.service`,
  `noxflow-fallback.service` and `noxflow-session-optional.service` into
  `~/.config/systemd/user`.
- `setup/bootstrap-noxflow.sh` links a list of units with `ln -sf`
  (`setup/bootstrap-noxflow.sh:40`), installs the binaries from
  `target/release` (`:27`), writes `panel.engine` (`:67`) and enables and
  restarts the services (`:72`).
- `setup/install-noxflow-foundation.sh` links `noxd.service`,
  `noxflow-shell.service`, `noxflow-fallback.service` and
  `localsend.service` with `ln -sfn` (`:12`) and installs the binaries
  with `cargo install --path` (`:10`).

`noxflow-shell.service` and `noxflow-fallback.service` therefore have three
owners, and `noxd.service` has two. The two installers also disagree about
where the binaries come from (workspace build output versus `cargo install`),
so a user who runs both ends up with whichever ran last, silently.

## 2. Eleven paths have two link owners — open

`setup/bootstrap.sh` and `setup/normalize-links.sh` both write:

    ~/.cache/hypr/theme-colors-rofi.rasi
    ~/.config/hypr/hyprland.lua
    ~/.config/hypr/lib
    ~/.config/hypr/monitor-layout.json
    ~/.config/mimeapps.list
    ~/.config/rofi/theme-colors-rofi.rasi
    ~/.config/uwsm/env
    ~/.config/uwsm/env-hyprland
    ~/.config/wayle/config.toml
    ~/.config/xdg-desktop-portal/hyprland-portals.conf

They use different mechanisms — the bootstrap plans first, records a manifest
and refuses to delete a path it does not own, while `normalize-links.sh`
moves the old path aside to `<path>.bak.<stamp>` — so a run of one script
reverts a decision the other made.

## 3. A retired Hyprland drop-in had two owners — resolved

- `setup/normalize-links.sh` linked
  `systemd/user/wayland-wm@hyprland.desktop.service.d/10-aq-drm-devices.conf`,
  which was deleted in commit `b71e9d0`. The link source no longer existed,
  so every run created a dangling symlink to a file that was not there.
- `setup/bootstrap.sh` removed the same override as obsolete, because DRM
  selection is owned by `uwsm/env-hyprland`, which exports
  `AQ_DRM_DEVICES`.

Both scripts claimed the path, and the drop-in contradicted the environment
that now owns it. `normalize-links.sh` no longer links it and removes a link
left by an earlier run; the bootstrap records the removal so that
`setup/rollback.sh` can put it back.

## 4. The bootstrap called a script that no longer exists — resolved

`setup/bootstrap.sh` invoked `setup/install-local-ai-stack.sh`
(`--install-runtime` and `--install-models`). That script was deleted in
commit `8022f56`, so the default bootstrap died with exit 127 before it
finished. The bootstrap now calls `setup/install-llama-router.sh` and
`setup/download-local-models.sh core`, and a failing optional step reports
a warning instead of aborting the workstation setup.

## 5. `check-dotfiles.sh` is an alias, not a second check — kept deliberately

`setup/check-dotfiles.sh` is a four-line `exec` wrapper around
`setup/check-shell.sh`. It is referenced from `README.md`, `AGENTS.md`,
`configs/claude/CLAUDE.md`, `configs/claude/agents/verifier.md` and
`docs/VSCODE_THEME_PLAN.md`. Removing it would break five references for no
gain, so it stays and is documented as an alias.

## 6. The browser MCP entry is installed where Claude Code never reads it — open

`setup/bootstrap.sh` links `configs/claude/mcp.json` to
`~/.claude/.mcp.json`. Claude Code's MCP scopes are local and project
(`.mcp.json` in the project root) and user (`~/.claude.json`);
`~/.claude/.mcp.json` is not one of them. `claude mcp list` reports the
user-scope servers (`playwright`, `obsidian`, `codegraph`, `mcode`) and
never the `browser` entry this file defines, so the browser MCP server is
not configured at all.

The file's content is now portable (the command resolves the script through
`$HOME` instead of an account path), but registering the server is a
user-scope action:

    claude mcp add --scope user browser -- sh -c 'exec "$HOME/Documents/code/dotfiles/configs/opencode/chrome-devtools-mcp.sh"'

## 7. A pre-commit hook was installed where git never looks — resolved

`setup/install-git-hooks.sh` wrote `.git/hooks/pre-commit`. The managed
gitconfig sets `core.hooksPath = ~/.config/git/hooks`, so git reads hooks
only from there and the installed hook was silently ignored. The script now
asks git for the configured hooks path, installs there, and keeps the
repository path in the hook body because the hook may live outside the
checkout.

## 8. Two orphaned runtime stylesheets — resolved

`hypr/wlogout/.runtime-style.css` and `hypr/wlogout/.runtime-style-futuristic.css`
were tracked, referenced by nothing (the live `style.css` does not import
them) and carried the account's wallpaper path. They were removed. The
tracked wlogout styles are `style.css` and `style-futuristic.css`.

## 9. A tool appends to a tracked, symlinked rc file — open

`~/.bashrc` is a symlink to the repository's `bashrc`. The MiniMax Code
CLI appends its `PATH` entries to `~/.bashrc`, which lands in the
checkout: that is how `/home/namik/.minimax/bin` ended up in a tracked
file. The entries are now `$HOME`-based, but the hazard remains — any tool
that appends to a symlinked rc file writes into the repository. The rc files
should be copied rather than linked, or the tools should own their own
fragment.

## 10. `aliases.local.zsh` is tracked but is a personal overlay — open

The file holds the account's private project aliases and is sourced by
`zshrc` only when it exists (`zshrc:849`). The paths are now portable,
but the file should be untracked and ignored, like `AGENTS.local.md`: it is
personal state that happens to live in the checkout.

## 11. The OpenCode config is the one remaining home-path cluster — open

`configs/opencode/opencode.local-llamacpp.json` still carries 18 absolute
paths into the checkout. It was left as-is on purpose:

- it is the canonical config and is symlinked into
  `~/.config/opencode/opencode.json`, so it is a live config whose edits
  apply immediately — a rendered copy would break that workflow;
- OpenCode resolves file paths relative to the config file's directory
  (documented), but the resolution of `mcp.servers.*.command` could not be
  verified offline, and getting it wrong breaks four MCP servers.

The remedy is to render the file from a template at install time, which keeps
the absolute paths and substitutes only the checkout location.

## 12. `install-shell-runtime-bridges.sh` duplicates the bootstrap — open

`setup/install-shell-runtime-bridges.sh` links `node`, `npm`, `npx` and
`pnpm` into `~/.local/bin` — the same four targets `setup/bootstrap.sh`
links, with a different mechanism (`ln -sfn` instead of a planned link with
a backup and a manifest entry). One owner should link them.

## 13. The Android environment file looked broken but is not — verified

`android/android-env.conf` uses `${ANDROID_HOME:-$HOME/Android/Sdk}`, which
looks like shell syntax that a systemd generator would not perform.
`environment.d(5)` documents that the right-hand side *is* expanded, with
`${FOO}`, `$FOO`, `${FOO:-default}` and `${FOO:+alternate}` supported.
The only account-bound value was the literal `JAVA_HOME`, which now
defaults through `${JAVA_HOME:-$HOME/.local/opt/android-studio/jbr}`.

## 14. A unit hard-coded the checkout location — resolved

`systemd/user/llama-router.service` started with
`ExecStartPre=%h/Documents/code/dotfiles/system/llama-router/render-preset.py`.
The account name was already portable, but the checkout path was not: a
clone anywhere else left the unit pointing at a file that does not exist, and
the router never started. `setup/install-llama-router.sh` now links the
renderer into `~/.config/llama-router/render-preset.py` and the unit starts
`%h/.config/llama-router/render-preset.py`.

## 15. A unit was linked without the binary it starts — resolved

`setup/bootstrap.sh` links `noxflow-shell.service`, whose `ExecStart` is
`%h/.local/bin/noxflow-shell` — but no bootstrap step provided that
launcher, so a bootstrap-only install had a unit that could not start. The
bootstrap now links `setup/noxflow-shell-launcher.sh` into
`~/.local/bin`, and `setup/bootstrap-noxflow.sh` links it instead of
copying it: a copy of a tracked script drifts from it, which is exactly what
happened to the `noxctl` binary copy (see `normalize-links.sh`).

The same gap existed for the daemon configuration: the daemon loads
`~/.config/noxflow/config.toml` (`core/noxflow-config/src/loader.rs:62`),
but only `setup/bootstrap-noxflow.sh` installed it. The bootstrap installs
it now.

## 16. Two files claim to be the NoxFlow configuration — open

`config/default.toml` says "Path: $XDG_CONFIG_HOME/noxflow/config.toml",
and `configs/noxflow/config.toml` says "Canonical source:
dotfiles/configs/noxflow/config.toml. Symlinked to ~/.config/noxflow/config.toml".
Both claim the same destination, and they have drifted: the first selects
`profile = "laptop"`, the second `profile = "material-expressive"`, and
only the first carries the `[providers]` section. Both parse against the
schema in `core/noxflow-config/src/config.rs`, so nothing rejects the
stale one — the file the daemon actually reads is
`configs/noxflow/config.toml`, and the sections it omits fall back to
code defaults.

The two files now have distinct, documented roles: `config/default.toml` is
the annotated reference of the schema, `configs/noxflow/config.toml` is the
instance the bootstrap installs.

The instance was also wrong in a way the daemon would have refused:
`profile = "material-expressive"` names a profile that does not exist (the
repository ships `base`, `focus` and `laptop`), and
`brightness.external_backend = ""` fails the daemon's own validation. It
also carried eighteen keys the schema does not know — `[bar]`, `[calendar]`,
`[island]`, `[animation]`, `[bluetooth]`, `[runtime]` and five stray
keys — which the daemon ignores, so they read as if they configured
something and did nothing.

Both files are now checked against the schema by
`core/noxflow-config/tests/repository_config.rs`, which loads them through
the production loader and fails on any key the schema does not know. The
bootstrap links `config/profiles` as well, so the named profile a config
selects resolves.

## 17. The setup test suites were wired into nothing — resolved

Twelve `setup/test-*.sh` scripts existed, and no runner ever executed
them. Two of them had been failing since the code they check moved on:

- `setup/test-pnpm-bridge.sh` expected the bridge to select `lts/*` when
  no `.nvmrc` is in scope; `system/node-runtime` selects nvm's
  `default` alias, and `setup/test-node-runtime-bridge.sh` already
  asserted that. The pnpm test was the stale side.
- `setup/test-ai-config.sh` asserted that the OpenCode config defines
  exactly the commands `fix` and `ui`. The config also defines
  `/capture-eval` and `/agent-lab`, which point at files that exist
  (`configs/opencode/agent-lab/commands/capture-eval.md` and
  `configs/opencode/agent-lab/runners/opencode.mjs`). The test was the
  stale side; it now requires the two core commands to exist and every
  command to be complete, without freezing the set.

Eight suites now run in the gate's integration mode: keybind documentation,
MCP profile, node runtime bridge, pnpm runtime bridge, project resume,
desktop launch, project profile and AI configuration.
`setup/test-local-models.sh` stays manual: it needs `llama-server` and the
downloaded models.

## 18. The scripts nothing references, classified

The remaining `setup/*.sh` files that no other script or document
mentions are not all the same kind of thing:

- **Deprecated shims that forward to the current owner** (4):
  `emergency-hypr-login-fix.sh`, `fix-nvidia-proprietary-hybrid.sh`,
  `fix-systemd-boot-nvidia.sh` and `restore-dynamic-hybrid-login.sh` each
  print "Deprecated: … is managed by workstationctl" and exec
  `workstationctl apply-system`. They exist so an old muscle-memory
  command still does the right thing.
- **Manual operator tools** (5): `client-backup-remote.sh` (installs a
  root-owned helper on remote backup hosts; its configuration is
  intentionally untracked), `configure-prism-performance.sh`,
  `install-devin-cli.sh`, `install-vscode-development.sh` and
  `install-git-hooks.sh` (run once after cloning).
- **A duplicate of the bootstrap** (1): `install-shell-runtime-bridges.sh`
  links the same four `~/.local/bin` targets as `setup/bootstrap.sh`.

## 19. The release gate mixed repository checks with desktop state — resolved

`setup/release-gate.sh` ran the repository checks and the live-desktop checks
in one pass, so a CI runner had to provide a logged-in Hyprland session, a
running `noxd` and an installed Quickshell. It also kept its output in two
shared files under `/tmp`, which concurrent runs overwrote. The gate now
has the modes `verify-static`, `verify-integration` and `verify-live`, and
keeps its output in its own `mktemp -d` directory behind a cleanup trap.
