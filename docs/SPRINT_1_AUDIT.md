# NoxFlow Sprint 1 foundation audit

Date: 2026-07-27

Audited commit: `06b217c` (`feat: introduce NoxFlow shell and daemon with initial CLI and IPC support`)

Reference plan: `theplan.md`, “First implementation sprint / Sprint 1 — Foundation”.

## Executive result

The additive Rust/configuration foundation builds, and `noxd` can answer a status
request over an XDG runtime Unix socket. Sprint 1 is not complete as a desktop
foundation, however. Quickshell is not installed or wired, the visible QML file
is not a Quickshell process, the new daemon unit is not installed in the live
user manager, and Wayle remains the only startup-managed panel. The NoxFlow
switch path is therefore not usable yet.

The audit found no tiny build-breaking defect that should be changed during this
audit. Runtime behavior was left unchanged.

## Requirement status

Status meanings: **complete** is implemented and verified; **partial** has a
usable slice but misses part of the requirement; **missing** has no repository
implementation; **broken** is present but its advertised path fails.

| Sprint 1 requirement | Status | Evidence |
| --- | --- | --- |
| Stable pre-rebuild tag | Missing | `git tag --list` returned no tags. |
| Dedicated `noxflow-shell` branch | Partial | Current branch is `inspired-rewrite`; no `noxflow-shell` branch exists. |
| Move Wayle under `legacy/wayle` | Missing | `legacy/` contains only `README.md`; active config remains in `wayle/`. |
| Preserve working-location symlinks | Partial | Bootstrap still links `wayle/config.toml` from its original location; no `legacy/wayle` migration or symlink scheme exists. |
| Consistent XDG config/state/cache paths | Partial | New CLI/daemon use `XDG_RUNTIME_DIR` with `/tmp` fallback; `config/default.toml` is not consumed, startup still uses `dotfiles` state, and legacy configs contain fixed paths. |
| Remove hard-coded `/home/namik` paths | Missing | 16 tracked files still contain `/home/namik`, including `wayle/config.toml`, `zshrc`, `git/gitconfig`, AI configs, and setup/docs. |
| Move startup daemons to systemd user units | Missing | `noxflow-session-optional.service` still runs the large `hypr/scripts/startup.sh`; that script starts applets, watchers, OSD, idle, wallpaper, and other processes. |
| Define `noxd` IPC types/schema | Partial | Version field and status shape exist, but IPC is raw string matching and hand-built JSON; no typed request/response model or event protocol exists. |
| Define shared theme tokens | Partial | `theme/tokens.toml` exists, but `Shell.qml` hard-codes colors and does not load the tokens. |
| Minimal Quickshell process/test surface | Broken | `shell/noxflow/Shell.qml` is a QtQuick `ApplicationWindow`; it has no `Quickshell` import, layer-shell integration, IPC adapter, project entrypoint, or startup service. `quickshell --version` returned command not found. |
| Automatic fallback to Wayle | Broken | Manual Wayle fallback exists through `panel-switch.sh`, but the switcher accepts only `wayle`; `panel-switch.sh noxflow` exits 1, and no NoxFlow startup/failure fallback is wired. |
| Record idle RAM/process count/startup timing | Missing | No Sprint 1 baseline record or NoxFlow-specific measurement check was found. |
| First visible deliverable | Partial | QML shows static workspace labels, a title, a clock, and placeholder glyphs; it has no live workspace/network/audio/battery data, Nox Island, or wallpaper-derived palette. |

## Implementation inventory

### `shell/noxflow/`

There is one file, `Shell.qml`. It is a static 900x48 QtQuick Controls window
with placeholder workspace, clock, and status text. It does not establish a
Quickshell shell surface, read `noxd`, consume `theme/tokens.toml`, or expose
a fallback path.

### `core/noxd/`

`noxd` is a small std-only blocking Unix-socket server. It creates
`$XDG_RUNTIME_DIR/noxflow/noxd.sock`, supports `status`, `ping`, and one JSON
status request spelling, and reports `hyprland`, `audio`, `network`, `battery`,
and `media` as `pending`. It has no providers, subscriptions, event stream,
configuration loading, socket permissions policy, or tests.

### `cli/noxctl/`

Implemented commands are `status` and a text-only `doctor`. `shell use wayle`
delegates to the existing panel switcher. `shell use noxflow` is accepted by
the Rust argument parser but fails downstream because the switcher has no
`noxflow` case. `shell restart` and `shell safe-mode` intentionally exit 2
as reserved future work.

### `config/` and `theme/`

The default config, focus profile, and semantic token file exist. They are
source artifacts only: neither binary loads them and the QML surface duplicates
colors in source. There are no keybinding, provider, profile-loading, or
generated-theme contracts for NoxFlow yet.

### Wayle fallback

Wayle remains active in its original `wayle/` location and has a valid installed
user unit at `/usr/lib/systemd/user/wayle.service`. The repository's
`panel-switch.sh` owns Wayle start/stop and persists only `wayle` as a valid
engine. The live unit was inactive at audit time, while
`noxflow-session-optional.service` was active and still owned the legacy startup
process tree.

## Dependency map

```text
                     graphical-session.target
                              |
          +-------------------+-------------------+
          |                                       |
  noxflow-session-optional.service          (not installed)
          |                                       |
  hypr/scripts/startup.sh                    noxd.service
          |                                       |
  panel-switch.sh ---> wayle.service         $XDG_RUNTIME_DIR/noxflow/noxd.sock
          |                                       ^
          |                                       |
       Wayle UI                              noxctl status/doctor
          ^                                       |
          |                                       +--> panel-switch.sh
          |
      Hyprland <--- existing scripts, keybinds, compositor sockets

  Intended but currently absent:

  Quickshell/Shell.qml ---> noxd IPC ---> Hyprland and system providers
             |
             +--> startup supervision/failure detection ---> Wayle fallback
```

Current dependency conclusions:

- Hyprland starts the optional systemd unit through the graphical session; the
  unit runs the legacy startup script rather than a NoxFlow shell.
- Wayle is the only shell actually understood by the panel switcher and the
  only shell referenced by the weekly/dev health checks.
- `noxd` has no live dependency edge from Hyprland, Quickshell, or systemd on
  this workstation because its user unit is not installed.
- `noxctl` can reach `noxd` when launched manually and can invoke the Wayle
  switcher, but cannot control a NoxFlow shell.
- Quickshell is only mentioned in a comment; no executable, service, or
  launcher path exists.

## Technical debt that can block Sprint 2

- No authoritative runtime contract: configuration, IPC, provider states, and
  events are not typed or versioned beyond a hand-built status JSON string.
- No process ownership boundary: the optional oneshot unit still launches a
  broad startup tree, making lifecycle, restart, fallback, and measurement
  ambiguous.
- No installed/verified `noxd` unit path; the unit points at
  `%h/.local/bin/noxd` but that binary is absent in the audited user environment.
- No Quickshell project scaffold or layer-shell entrypoint to build on.
- Wayle migration has not begun, so active paths and legacy paths cannot yet be
  tested independently.
- XDG policy is inconsistent, including `/tmp` fallbacks, unconsumed config,
  non-NoxFlow state directories, and 16 tracked files with hard-coded home
  paths.
- The switch protocol is asymmetric: CLI accepts `noxflow`, but
  `panel-switch.sh` cannot start it.
- Live-data providers are all `pending`; the first visible bar cannot be made
  reliable until provider ownership and event delivery are defined.
- There are no NoxFlow tests, and the existing Cargo crates contain zero tests.
- Existing repository guardrails are already noisy: full shell formatting and
  keybind parity checks fail independently of the new foundation.

## Existing checks and exact results

Commands were run from `/home/namik/Documents/code/dotfiles` on 2026-07-27.

| Command | Result |
| --- | --- |
| `cargo test --manifest-path core/noxd/Cargo.toml` | PASS, exit 0; 0 tests run. |
| `cargo test --manifest-path cli/noxctl/Cargo.toml` | PASS, exit 0; 0 tests run. |
| `cargo check --manifest-path core/noxd/Cargo.toml` | PASS, exit 0. |
| `cargo check --manifest-path cli/noxctl/Cargo.toml` | PASS, exit 0. |
| `cargo build --manifest-path core/noxd/Cargo.toml` | PASS, exit 0. |
| `cargo build --manifest-path cli/noxctl/Cargo.toml` | PASS, exit 0. |
| `setup/check-shell.sh --all` | FAIL, exit 1; ShellCheck passed, `shfmt -d` reported pre-existing formatting drift in `setup/fetch-wallpaper-sources.sh` and `setup/test-opencode-mcp.sh`. It checked 212 scripts. |
| `setup/check-stale-references.sh` | PASS, exit 0. |
| `setup/check-keybinds.sh` | FAIL, exit 1; broad documented-target mismatches were reported across the launch/session keybind set. |
| `bash -n hypr/scripts/panel-switch.sh hypr/scripts/startup.sh setup/install-noxflow-foundation.sh` | PASS, exit 0. |
| `systemd-analyze verify systemd/user/noxd.service systemd/user/noxflow-session-optional.service` | FAIL, exit 1; `noxd.service` reports `/home/namik/.local/bin/noxd` is not executable because the unit has not been installed with the binary. |
| `quickshell --version` | FAIL, exit 127; `quickshell: command not found`. |
| `hypr/scripts/panel-switch.sh noxflow` | FAIL, exit 1; usage output lists only `toggle`, `wayle`, `toggle-view`, `show`, `hide`, and `status`. |
| `cli/noxctl/target/debug/noxctl doctor` | PASS, exit 0; reports the XDG runtime socket and Wayle fallback. |
| `cli/noxctl/target/debug/noxctl shell restart` | FAIL as designed, exit 2; reports this is reserved for the session integration sprint. |
| Manual `noxd` with temporary `XDG_RUNTIME_DIR` plus `cli/noxctl/target/debug/noxctl status` | PASS, exit 0; returned schema 1 JSON and all five providers as `pending`. |
| `systemctl --user list-unit-files --no-pager` | PASS, exit 0; `wayle.service` enabled, `noxflow-session-optional.service` linked/enabled, and no `noxd.service` listed. |
| `systemctl --user status noxd.service --no-pager` | FAIL, exit 4; unit not found. |
| `systemctl --user status wayle.service --no-pager` | PASS command, service inactive/dead at audit time; installed unit is enabled and previously exited successfully. |
| `systemctl --user status noxflow-session-optional.service --no-pager` | PASS command; oneshot active/exited, with legacy watchers and daemons in its cgroup. |

## Recommended implementation order

1. Establish the migration boundary: tag the audited baseline, choose/create
   the dedicated branch, and decide exactly which Wayle files move under
   `legacy/wayle` while preserving tested symlinks.
2. Define the XDG policy and typed contracts before adding providers: config,
   state, cache, runtime socket, IPC requests/responses, and event envelopes.
3. Create the actual Quickshell project and a minimal layer-shell bar that can
   start, stop, and report failure without taking down the Wayle fallback.
4. Install and supervise `noxd` through a dedicated user unit; remove only the
   daemon responsibilities from `startup.sh` after each replacement has a
   service-level health check.
5. Make `noxctl shell use noxflow`, restart, and safe-mode agree with the
   switcher and implement an explicit automatic fallback to Wayle.
6. Add one provider at a time—Hyprland/workspaces first, then audio/network/
   battery/media—and replace the static QML labels with daemon state.
7. Connect theme tokens and profile loading to the shell, then record baseline
   startup time, process count, and idle RAM for the new path.
8. Re-run the repository checks and add focused NoxFlow tests before expanding
   into Nox Island or other Sprint 2 surfaces.

