# NoxFlow Shell Milestone 1 Release Report

Status: implementation complete; live release gate blocked by missing
Quickshell on the validation machine.

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
configuration, fallback availability, IPC documentation, hard-coded paths,
and live shell integration.

## Integration matrix

| Scenario | Result | Notes |
| --- | --- | --- |
| noxd systemd startup | Pass | Active under `noxd.service`; socket and provider snapshots available. |
| Quickshell connection and reconnect | Blocked | `quickshell` is not installed. |
| Bar provider state updates | Blocked | Requires Quickshell session. |
| Audio and brightness controls | Pass | Provider/action/unit tests pass. |
| Network, Bluetooth, battery and power state | Pass | Provider/action/unit tests pass; live Bluetooth hardware is unavailable to the test harness. |
| Media state and controls | Pass | MPRIS provider/action tests pass; no active player is required. |
| Nox Island activity | Pass | Synthetic Island IPC tests pass. |
| Multi-monitor placement | Blocked | Requires Quickshell session and external display exercise. |
| Hyprland reload | Blocked | Requires active Quickshell session. |
| Quickshell and noxd restart | Partial | noxd restart is supervised; Quickshell restart is blocked by missing binary. |
| Suspend/resume | Blocked | Requires live desktop power-cycle exercise. |
| External monitor disconnect/reconnect | Blocked | Requires live external monitor. |
| Daemon unavailable mode | Pass | QML client reconnect/degraded-path code and protocol fixtures pass. |
| Protocol mismatch | Pass | CLI and IPC tests pass. |
| Invalid configuration | Pass | Configuration integration tests pass. |
| Wayle fallback and safe mode | Pass | `noxctl shell safe-mode` selects the active Wayle recovery path. |

## Measurements

Capture live values with:

```sh
./setup/measure-noxflow.sh
```

The NoxFlow-specific measurement command is currently blocked because the
NoxFlow shell cannot be active without Quickshell. The live daemon snapshot on
2026-07-27 reported `noxd` RSS of approximately 16.3 MiB. Login-to-bar time,
NoxFlow idle CPU, and NoxFlow process count remain pending until Quickshell is
installed and the gate is rerun.

## Recovery behavior

NoxFlow failure stops the failed shell and activates Wayle through the
fallback service. `noxctl shell safe-mode` explicitly selects the same
no-daemon recovery path. The last fallback reason is retained in NoxFlow
state for diagnostics.

## Remaining Wayle dependencies

Wayle remains the configured fallback shell and is still required for safe
mode. Its configuration and service remain installed. The remaining direct
dependency is the Wayle fallback service/configuration; NoxFlow provider state
and controls are owned by `noxd`.

## Release decision

The static gate passes. The overall release decision remains pending until
Quickshell is installed, the live integration matrix is completed, and
`setup/release-gate.sh` exits successfully.
