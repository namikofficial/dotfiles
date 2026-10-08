
<!-- personal-subagent-routing -->
## Quality contract

- Start from the requested outcome and observable acceptance criteria; inspect repository instructions, branch/status, affected callers, contracts, and tests before editing.
- Make the smallest complete change. Preserve unrelated work, do not invent compatibility layers, hide errors, weaken types, or claim a build/startup proves runtime behavior.
- Verify the changed behavior at the cheapest authoritative tier, then escalate only when the surface requires it. Treat delegated output as evidence, not authority.
- Final reports must separate `OBSERVED`, `NOT_CONFIGURED`, `UNVERIFIED`, `BLOCKED`, and `RECOMMENDED`, and include exact paths, commands, results, risks, and next action.

## Subagent delegation

Use subagents proactively to keep the main context focused.

- Use `Explore` for broad fan-out sweeps across many files, directories, or naming conventions when only the conclusion matters.
- Use `scout` for locating implementations, tracing unfamiliar flows, and mapping affected files before substantial changes.
- Use `planner` before substantial or cross-cutting changes that need a sequenced strategy and named acceptance criteria.
- Use `verifier` to run the cheapest authoritative checks for a changed surface and report observed results.
- Use `reviewer` after meaningful implementations, bug fixes, refactors, migrations, authentication changes, database changes, or infrastructure changes.
- Delegate independent investigations in parallel when doing so will materially reduce main-context usage.
- Do not delegate trivial operations where delegation would cost more than doing the work directly.
- The main agent remains responsible for implementation, verification, and the final decision.

## Workstation environment

Arch Linux, Hyprland, zsh. The Bash tool runs an interactive zsh that sources
`~/.zshrc` (symlink into `~/Documents/code/dotfiles`), so shell aliases and
functions are live inside tool calls.

### Alias traps

- `cat` is `bat --paging=never --style=plain`, `ls` is `eza --icons=auto
  --group-directories-first`, `ssh` is `kitten ssh`. `ls -t`/`-s` are eza flags,
  not coreutils ones; use `command ls` when you need coreutils semantics.
- `grep` is `rg -n --smart-case` in a real login shell, but the agent shell
  snapshot runs `unalias grep` (also `find`, `pkill`). Never depend on either
  mapping: call `rg` and `fd` by name.
- `cp`/`mv`/`rm` are plain coreutils with no `-i`/`-I` guard. Nothing prompts, so
  nothing hangs — but nothing protects against a bad glob either. Pass explicit
  paths, never a bare wildcard, and prefer the Write/Edit tools over shell writes.
- Prefer the Read/Edit/Glob/Grep tools over shell equivalents generally.

### Token-efficient command output

`rtk` (`~/.local/bin/rtk`) filters and summarizes command output before it
reaches context. Prefer it for noisy commands:

- Wrappers: `rtk git`, `rtk gh`, `rtk docker`, `rtk cargo`, `rtk npm`,
  `rtk pnpm`, `rtk go`, `rtk tsc`, `rtk vitest`, `rtk jest`, `rtk pytest`,
  `rtk prisma`, `rtk psql`, `rtk kubectl`, `rtk dotnet`.
- Inspection: `rtk ls`, `rtk tree`, `rtk find`, `rtk read`, `rtk diff`,
  `rtk json`, `rtk deps`, `rtk wc`, `rtk grep`, `rtk rg`.
- Reduction: `rtk err <cmd>` (errors/warnings only), `rtk test <cmd>` (failures
  only), `rtk summary <cmd>`, `rtk log <cmd>` (deduplicated logs).
- Escape hatch: `rtk proxy <cmd>` for raw output. `rtk gain` shows savings.

Use the raw command when exact bytes matter: diff hunks you will patch,
checksums, `git diff --check`, or anything whose output you must quote verbatim.

### Installed tooling

- Search/read: `rg`, `fd`, `bat`, `eza`, `ast-grep`/`sg`, `tokei`, `delta`, `fzf`.
- Data/HTTP: `jq`, `sd`, `xh`. No `yq`, `gum`, or `glow` installed.
- Runtime/build: `just`, `uv`, `ruff`, `pnpm`, `bun`, `node` (nvm), `cargo`, `docker`.
  No `kubectl`, `podman`, `watchexec`, or `cargo-nextest` despite `k*` aliases existing.
- System: `procs`, `dust`, `duf`, `btm`, `hyperfine`, `lazygit`, `atuin`, `zoxide`, `tldr`.
- Secrets: `sops` + `age`. Age key: `dotfiles/private/scripts/noxorigin/sops/age/keys.txt`.
  Never decrypt, print, or commit secret material unless explicitly asked.

### Project roots

- `~/Documents/code/dotfiles` — workstation config; read its `AGENTS.md` and the
  nearest nested `AGENTS.md` before editing. Checks: `./setup/check-shell.sh --all`,
  `./setup/check-dotfiles.sh --all`, `cargo check --workspace`.
- `~/Documents/code/noxorigin` — `workspace` (NoxCRM), `nox-billings`, `nox-tickets`.
- `~/Documents/code/trackMe`, `~/Documents/code/WellVantage`.
- Many projects drive tasks through `just`; check for a `justfile` before inventing commands.
