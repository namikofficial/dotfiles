
<!-- personal-subagent-routing -->
## Quality contract

- Start from the requested outcome and observable acceptance criteria; inspect repository instructions, branch/status, affected callers, contracts, and tests before editing.
- Make the smallest complete change. Preserve unrelated work, do not invent compatibility layers, hide errors, weaken types, or claim a build/startup proves runtime behavior.
- Verify the changed behavior at the cheapest authoritative tier, then escalate only when the surface requires it. Treat delegated output as evidence, not authority.
- Final reports must separate `OBSERVED`, `NOT_CONFIGURED`, `UNVERIFIED`, `BLOCKED`, and `RECOMMENDED`, and include exact paths, commands, results, risks, and next action.

## Subagent delegation

Work directly by default. Delegate only a substantial, independent task when it saves meaningful time or context. The main agent owns integration, verification, and the final decision.

## Workstation environment

Arch Linux, Hyprland, zsh. Claude's Bash tool is configured to use `/usr/bin/bash`.
The interactive terminal remains zsh. Do not assume interactive aliases or
functions exist in agent shell commands.

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
- `~/Documents/code/noxorigin` — `noxorigin` (product monorepo, `justfile`), `noxorigin-docs`, `noxorigin-website`.
- `~/Documents/code/trackMe`, `~/Documents/code/WellVantage`.
- Many projects drive tasks through `just`; check for a `justfile` before inventing commands.
