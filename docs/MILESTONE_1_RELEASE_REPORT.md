# NoxFlow Shell Milestone 1 Release Report

Status: Release candidate

## Scope

This milestone makes the NoxFlow bar and Nox Island usable as the primary
Quickshell shell, with `noxd` as the event-driven state service and Wayle as
the preserved fallback. Wayle is intentionally not removed.

## Release gate

Run from the repository root in an active Hyprland graphical session:

```sh
./setup/release-gate.sh
```

The gate checks Rust formatting, Clippy, tests, QML syntax, systemd units,
configuration, package ownership, fallback availability, IPC documentation,
hard-coded paths, Quickshell launch, Quickshell-to-noxd IPC, and live shell
integration. The gate passed on 2026-07-27.

## Integration matrix

| Scenario | Static test | Synthetic integration test | Live desktop test | Manual hardware test |
| --- | --- | --- | --- | --- |
| noxd systemd startup | Pass | — | Pass; active unit and socket | — |
| Quickshell production entrypoint | Pass; `qmllint` | — | Pass; one instance | — |
| Protocol negotiation/subscription | Pass | Pass | Pass; journal records subscription | — |
| Bar/provider state updates | Pass | Pass | Pass; live provider snapshots | Media content pending real player |
| Audio/brightness controls | Pass | Pass | Pass; signed and mute round-trips | — |
| Network/Bluetooth/battery/power | Pass | Pass | Pass; live providers available | Paired Bluetooth device pending |
| MPRIS media | Pass | Pass | Provider unavailable without player | Start a real MPRIS player |
| Nox Island content/timeout | Pass | Pass | Pass; synthetic volume/brightness events | Visual timeout confirmation |
| Multi-monitor placement | Pass | Pass | Single-monitor pass | External display reconnect |
| Hyprland reload/workspace | Pass | Pass | Reload passed | Confirm workspace switching |
| noxd restart/socket recovery | Pass | Pass | Pass; disconnect/resubscribe | — |
| Quickshell restart/crash | Pass | Pass | Pass; forced SIGKILL recovered | — |
| Daemon-unavailable mode | Pass | Pass | Pass; socket disappearance exercised | — |
| Protocol mismatch | Pass | Pass | — | — |
| Invalid configuration | Pass | Pass | — | — |
| Wayle fallback/return to NoxFlow | Pass | Pass | Pass; both directions | — |
| Suspend/resume | Pass | Pass | — | Required manual test |
| External-monitor disconnect/reconnect | Pass | Pass | — | Required manual test |

## Measurements

Capture live values with:

```sh
./setup/measure-noxflow.sh
```

Measured on 2026-07-27 after a 10-second settle:

```text
noxd RSS: 12,232 KiB
Quickshell RSS: 233,216 KiB
Combined NoxFlow RSS: 245,448 KiB
Idle CPU: 0.31%
NoxFlow-related processes: 2
Journal errors since shell start: 0
Wayle fallback startup: 790 ms
NoxFlow shell startup after Wayle: 549 ms
```

The reported `login_to_visible_bar_seconds=16,698` is a session-start to
current-shell-activation proxy, not a clean boot measurement. A true
login-to-visible-bar measurement remains a manual next-login check.

## Recovery behavior

NoxFlow failure activates Wayle through the fallback service. `noxctl shell
safe-mode` explicitly selects the same no-daemon recovery path. A forced
Quickshell SIGKILL produced an inactive failed NoxFlow unit and active Wayle;
`noxctl shell use noxflow` restored one active Quickshell instance and no Wayle
process.

## Remaining Wayle dependencies

Wayle remains the configured fallback shell and is still required for safe
mode. Its configuration and service remain installed. The remaining direct
dependency is the Wayle fallback service/configuration; NoxFlow provider state
and controls are owned by `noxd`.

## Release decision

The milestone is a Release candidate. The release gate passed. Remaining work
is limited to manual suspend/resume, external-monitor reconnect, true
login-to-visible-bar timing, and a real MPRIS playback session before marking
the milestone Passed.
