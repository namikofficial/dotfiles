# 00 — Baseline

**Date:** 2026-07-31
**Branch:** `codex/unified-shell-redesign-20260728`
**Commit:** `0dd17a0845a5009b048937f6366a467a3886823a` — `feat: add configuration for native Wayland rendering in Cursor and VS Code`
**Working tree:** clean

---

## Scope

This document captures the state of the workstation and repository before the
unified-shell redesign begins. Everything recorded here is the known-good
baseline that `09-rollback.md` restores to.

---

## 1. Git state

| Item | Value |
|---|---|
| Branch | `codex/unified-shell-redesign-20260728` |
| HEAD | `0dd17a0845a5009b048937f6366a467a3886823a` |
| Working tree | clean |
| Submodules | `private/scripts` (SSH-only, may be absent) |
| `Cargo.lock` | tracked (desktop binary reproducibility) |

Rollback anchor: `git checkout 0dd17a0845a5009b048937f6366a467a3886823a` (or the
`pre-redesign-baseline` tag once created).

---

## 2. Shell ownership (single-process audit)

The repository defines **one** Quickshell shell: `noxflow` (NoxFlow), with
Wayle as an explicit safe-mode fallback. Ownership is enforced by
`hypr/scripts/panel-switch.sh` (`start_wayle` stops `noxflow-shell.service` and
vice-versa).

### systemd user services (in repo)

| Service | Role | Enabled by |
|---|---|---|
| `noxd.service` | Desktop state daemon (event bus + 7 providers) | `graphical-session.target` |
| `noxflow-shell.service` | Quickshell shell (NoxFlow) | `graphical-session.target` |
| `noxflow-session-optional.service` | Oneshot → `startup.sh` (applets, warmers) | `graphical-session.target` |
| `noxflow-fallback.service` | Emergency Wayle fallback (OnFailure only; no `[Install]` section) | not enabled |
| `ai-workbench-*.service` | AI workbench observers | separate |

### Startup chain

```
graphical-session.target
 ├─ noxd.service
 ├─ noxflow-shell.service            ExecStart=%h/.local/bin/noxflow-shell
 ├─ noxflow-session-optional.service ── startup.sh
 │    └─ panel-switch.sh show ── systemctl --user start noxflow-shell.service
 └─ noxflow-fallback.service (OnFailure of shell → Wayle)
```

**Known risk:** `startup.sh` → `panel-switch.sh show` issues
`systemctl --user start noxflow-shell.service` while the same service is already
`WantedBy=graphical-session.target`. `systemctl start` on an active service is a
no-op, so duplicates are unlikely, but the ordering is fragile and must be
hardened in M3.

**Current state verification (to be run on the live system):**

```sh
systemctl --user is-active noxflow-shell.service wayle.service noxd.service
pgrep -ax quickshell        # expect exactly 1
pgrep -ax wayle             # expect 0 (fallback disabled)
systemctl --user is-enabled noxflow-shell.service
```

---

## 3. Installed versions

To be recorded on the live system during M0 verification:

```sh
hyprctl version
quickshell --version
qmlformat --version
qt6 --version | head -1
pacman -Qs 'quickshell|qt6-base|hyprland'
yay -Q local 2>/dev/null | rg -i 'scroll-overview|hyprexpo|localsend|kdeconnect'
```

Known from repo comments: Hyprland `0.54.1` is referenced in
`hypr/scripts/startup.sh` (`hyprpm` header-refresh issue note, lines 243–245).
`hyprpm` is the plugin manager; hyprland-scroll-overview must be built against
the exact installed version.

---

## 4. Provider / backend map (real data sources)

| Surface concern | Backend | Provider (Rust) | QML model |
|---|---|---|---|
| Audio (PipeWire) | `pactl` subscribe + mutations | `core/noxd/src/providers/audio.rs` | `AudioModel.qml` |
| Bluetooth (BlueZ) | D-Bus `org.bluez` | `providers/bluetooth.rs` | `BluetoothModel.qml` |
| Brightness | D-Bus (ddcci/wlroots backends) | `providers/brightness.rs` | `BrightnessModel.qml` |
| Hyprland state | socket pair (`.socket.sock`/`.socket2.sock`) | `providers/hyprland.rs` | `HyprlandModel.qml` |
| MPRIS media | D-Bus `org.mpris.MediaPlayer2` | `providers/media.rs` | `MediaModel.qml` |
| Network (iwd) | iwd station state + systemd-networkd | `providers/network.rs` | `NetworkModel.qml` |
| Power (UPower) | D-Bus `org.freedesktop.UPower` | `providers/power.rs` | `PowerModel.qml` + `BatteryModel.qml` |
| Notifications | daemon snapshot + events | (QML-side) | `NotificationModel.qml` |
| Calendar | `Component.onCompleted: start()` | (QML-side) | `CalendarModel.qml` |
| Clipboard | cliphist / author-clipboard-daemon | (QML-side) | `ClipboardModel.qml` |
| Weather | QML-side fetch | — | `WeatherModel.qml` |
| System stats | QML-side sampling | — | `SystemModel.qml` |

Transfer backend (planned): **LocalSend** — already declared in
`setup/aur-packages.txt` (`localsend-bin|localsend-appimage`) and referenced in
`hypr/scripts/lib/quick-actions.sh` (`flatpak run org.localsend.localsend_app`).
No `TransferService.qml` exists yet. Syncthing is installed and working
(`hypr/scripts/syncthing-control.sh`, systemd user service) and stays as a
companion integration.

---

## 5. Known bugs fixed in this redesign (baseline repro)

### 5.1 Volume/brightness OSD flashes on login

**Root cause:** race in `shell/noxflow/NoxIsland.qml`:

1. `NoxIsland.qml:49` — `Component.onCompleted` sets `guardVolume = audio.outputVolume`.
   At that moment `audio.outputVolume` is `0` (default in `AudioModel.qml:6`; snapshot not yet received).
2. `shell.qml:21` — `NoxdClient { Component.onCompleted: start() }` connects asynchronously.
3. First snapshot arrives → `audioModel.applySnapshot` sets the real value (e.g. 43).
4. `NoxIsland.qml:81` — `onOutputVolumeChanged` fires: `|43 − 0| > 1` → enqueues "Volume" OSD.

Same race for brightness (`guardBrightness` default `-1`, `NoxIsland.qml:82`).

**Fix (M1):** gate on `audio.available` + a `firstSnapshotApplied` flag; set
guards only after the first synced snapshot, never display on the initial
application of a snapshot.

### 5.2 Minimize/restore/group workflow broken

Reference: `hypr/scripts/minimize-window.sh` (211 lines), binds at
`hypr/conf/40-binds-launch.lua:30,66` and groups at `50-binds-layout.lua:66-69`.

- **Bug A:** `set_window_fullscreen` (`minimize-window.sh:42-56`) passes a
  double-quoted Lua string into `hl.dispatch(...)` and swallows errors with
  `|| true` — restored windows silently lose fullscreen.
- **Bug B:** `hypr_eval` (`minimize-window.sh:18-20`) does not reflect actual
  dispatch success under `set -eu`.
- **Bug C:** minimizing a grouped window to `special:minimized` can leave the
  group inconsistent; restore places the window back without group context.
- **Bug D:** workspace restore prefers `workspace_name` over `workspace_id`,
  which can target the wrong named workspace.

**Fix (M2):** verified dispatcher syntax, no error swallowing, group-aware
minimize/restore, workspace-id-normalized restore.

---

## 6. Current shell surface inventory

| Surface | File | Role |
|---|---|---|
| Entry | `shell/noxflow/shell.qml` (293 ln) | wires 15+ surfaces, IPC handler |
| Bar | `shell/noxflow/Bar.qml` | workspaces, CPU/RAM/temperature pills, clock pill, media pill, status cluster |
| Island (OSD) | `shell/noxflow/NoxIsland.qml` (119 ln) | priority-queue contextual pill |
| Panel host | `shell/noxflow/core/MorphSurface.qml` (130 ln) | PanelWindow + Behavior morphs |
| Controller | `shell/noxflow/core/PanelController.qml` (100 ln) | panel state machine |
| Coordinator | `shell/noxflow/components/SurfaceCoordinator.qml` | modal stacking + Escape |
| Morph registry | `shell/noxflow/MorphRegistry.qml` | chip→panel origin geometry |
| Control centre | `surfaces/controlcenter/ControlCentre.qml` (868 ln) | Wi-Fi/BT/audio/brightness/power |
| Notification centre | `surfaces/notifications/NotificationCentre.qml` (106 ln) | grouped notifs, DND, history |
| Calendar | `surfaces/calendar/CalendarWidget.qml` | calendar |
| Media panel | `surfaces/media/MediaPanel.qml` | MPRIS controls |
| Launcher | `surfaces/launcher/Launcher.qml` | app launcher |
| Dashboard | `surfaces/dashboard/Dashboard.qml` | full-screen dashboard |
| Overview (QML) | `surfaces/overview/Overview.qml` (204 ln) | **to be deleted** (M10) |
| Settings | `surfaces/settings/SettingsPanel.qml` | settings |
| Capture | `surfaces/capture/Capture.qml` | screenshot/OCR |
| Radial wheel | `surfaces/radialmenu/RadialWheel.qml` | radial menu |
| Theme | `theme/Tokens.qml`, `theme/ThemeProfiles.js` | M3 design tokens + profiles |
| Config | `config/ShellConfig.qml`, `config/Motion.qml` | shell + motion settings |

---

## 7. Keybind baseline (before redesign)

Canonical map: `docs/KEYBINDS.md` (generated from `hypr/conf/*.lua`).

| Bind | Current action |
|---|---|
| `SUPER+TAB` | `noxctl panel toggle overview` (QML Overview) → **replaced** (M10) |
| `SUPER+SPACE` | `noxctl panel toggle launcher` |
| `SUPER+N` | `noxctl panel toggle notifications` |
| `SUPER+SHIFT+B` | `noxctl panel toggle control` |
| `SUPER+SHIFT+C` | `noxctl panel toggle calendar` |
| `SUPER+C` | `hl.dsp.window.center()` → **moved** (M11) |
| `SUPER+M` | `hl.dsp.window.fullscreen(maximized)` → **moved** (M11) |
| `SUPER+CTRL+V` | cliphist-rofi |
| `SUPER+SHIFT+V` | cliphist-toggle |
| `SUPER+O` / `SUPER+SHIFT+O` | set-wallpaper pick / next |
| `SUPER+ESC` | power-menu.sh |
| `SUPER+T` | window group toggle |
| `SUPER+ALT+.` / `SUPER+ALT+;` | group next / prev |
| `SUPER+SHIFT+M` | minimize-window.sh minimize |
| `SUPER+ALT+M` | minimize-window.sh restore |
| `SUPER+CTRL+T` | move out of group |

---

## 8. Environment constraints

- **NVIDIA hybrid laptop (RTX 4050 + Intel):** DRM KMS blacklisted on NVIDIA;
  compositor uses Intel iGPU. CUDA/compute uses NVIDIA base module. Do not
  hardcode DRM card numbers.
- **No CI/CD** in repo.
- **`Cargo.lock` tracked.**
- **Wayle is the fallback shell** — must never run alongside NoxFlow.
- **OpenCode config** lives in `configs/opencode/opencode.local-llamacpp.json`
  (not root `opencode.json`).
- **Settings system:** `settingsctl` for validated state updates;
  `settings/state.local.json` is gitignored.
- **Private submodule** `private/scripts` may be unavailable (SSH).

---

## 9. Acceptance criteria (this redesign)

The redesign is complete when:

1. One shell process; no duplicate bar/notification ownership.
2. Central island visibly morphs (phased geometry + content choreography).
3. Every displayed control uses real backend data.
4. Quick Share performs real transfers (LocalSend).
5. ScrollOverview plugin is the primary spatial workflow (keyboard + touchpad + mouse).
6. Multi-monitor stable.
7. Shell restart and rollback documented.
8. No QML warnings or repeated service errors.
9. Volume/brightness OSD does not flash on login.
10. Minimize/restore/group workflow works reliably.
