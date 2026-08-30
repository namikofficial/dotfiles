# NoxFlow Top Chrome Completion Checklist

Status: implemented and live-validated on 2026-08-23

This document records the repair of the NoxFlow bar/dynamic-island interaction, the surrounding telemetry and power-authority work, and the checks future changes must preserve.

## Outcome

The dynamic island no longer closes on a fixed timer while its source remains hovered. Source hover, island hover, pins, routine OSD activity, and critical interruptions are separate state channels. The user can move into the island, interact with it, pin it, use a distinct Open action, or dismiss it with re-click, Escape, a detectable click-away, context replacement, or panel closure.

The top chrome uses one Quickshell layer window. Its click mask is the union of the bar and the visible island card, so transparent pixels below the bar pass through to applications. The behavior follows Quickshell's documented `QsWindow.mask` and `Region` model.

## Interaction contract

- [x] Every supported source reports hover state explicitly: workspace, health, connectivity, audio/power, notifications, updates, sync, and degraded-provider health.
- [x] The source remains open while either the source or island body is hovered.
- [x] Leaving both starts a 900 ms transit grace.
- [x] Generation tokens make stale timer callbacks harmless.
- [x] Clicking the island body pins or unpins the current context.
- [x] The dashboard has a separate keyboard-accessible Open action.
- [x] Pin state is visible and exposed to accessibility.
- [x] Routine OSD activity preserves and restores pins.
- [x] Critical activity may interrupt a pin and restores the original pin, including nested critical events.
- [x] Critical content itself cannot be pinned.
- [x] Escape, re-click, context replacement, top-chrome click-away, and panel close dismiss the appropriate state.
- [x] Transparent top-chrome pixels outside the bar/card are click-through.

## Data truth contract

- [x] CPU, memory, disk, load, frequency, swap, thermal, and GPU metrics have explicit availability semantics.
- [x] Successful samples expose timestamp, age, live/stale status, and source identity.
- [x] A failed refresh with prior data is shown only as stale; a failure without usable data is unavailable.
- [x] Missing optional metrics reset to unavailable instead of retaining a positive value indefinitely.
- [x] NVIDIA telemetry is labeled as compute telemetry; it is not described as the compositor GPU.
- [x] Integrated DRM sources are discovered from sysfs and never hard-coded to a card number.
- [x] Power profiles come only from real noxd/power-profiles-daemon snapshots; profile names are never invented.

## Power authority

- [x] `power.auto_profile=true` is the only condition that starts or keeps the AC/battery watcher running.
- [x] `power.auto_profile=false` stops the watcher and makes `power.default_profile` authoritative.
- [x] The local machine profile is `performance`, its default power profile is `performance`, automation is disabled, and the live profile was verified as `performance` during this work.
- [x] Profile changes remain local in `settings/state.local.json`; secrets and machine-local state remain untracked.

## Automated evidence

- [x] `node shell/noxflow/tests/test_hover_engagement.js`
- [x] `node shell/noxflow/tests/test_system_snapshot.js`
- [x] `node shell/noxflow/tests/test_protocol.js`
- [x] `node shell/noxflow/tests/test_workspace_presentation.js`
- [x] `qmllint` on all changed QML files
- [x] `bash -n` and targeted `shfmt -d -i 2 -ci` on changed power scripts
- [x] `git diff --check` and `git diff --cached --check` before each commit
- [x] NoxFlow service restart and journal inspection after each QML slice
- [x] Surface smoke test; the sync command now uses the real `noxctl panel toggle sync` interface

The full `./setup/check-shell.sh --all` currently reports pre-existing repository-wide shfmt drift in unrelated scripts. Changed power scripts pass targeted syntax and formatting checks. Do not treat those unrelated baseline diffs as failures introduced by this work.

## Manual acceptance checklist

These checks require a real pointer/keyboard session and should be repeated after interaction or geometry changes:

- [ ] Hover each visible capsule for at least two seconds; its island context remains open.
- [ ] Move from a source capsule into the island slowly; the island remains interactive.
- [ ] Pin a context, trigger volume/brightness OSD, and confirm the pinned context returns.
- [ ] Activate Open with pointer, Return, and Space.
- [ ] Confirm Escape and re-click unpin.
- [ ] Confirm clicks through transparent space below the bar reach the underlying application.
- [ ] Repeat on every connected monitor and at every configured scale.

Automated startup, lint, reducer, IPC, and screenshot evidence does not replace these physical interaction checks.

## Future change and commit checklist

For every future bar/island change:

1. Record `git status --short`, `git diff --stat`, and `git diff --name-only` before editing.
2. Preserve user work and give any delegated writer an exact file boundary.
3. Add or update a deterministic reducer/parser fixture for state changes.
4. Run focused Node tests and `qmllint`.
5. Restart `noxflow-shell.service` and inspect the new journal interval.
6. Run the surface smoke test and the relevant physical interaction checks.
7. Stage exact paths, inspect the cached names/diff, run `git diff --cached --check`, and commit one coherent validated slice.
8. Do not push unless the user explicitly requests it.
