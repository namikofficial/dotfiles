# Architecture audit — 2026-09-16

## Evidence-backed findings

- The Rust `noxd`/IPC/provider split, typed QML models, `MorphSurface`,
  `PanelController`, and existing pure-JS lifecycle tests are valuable and are
  retained.
- `NoxIsland.qml` is a 1,100+ line component with fifteen injected models. It
  owns OSD/activity state, launcher, inline calendar, hover dashboards,
  pinning, click-away handling and per-monitor daemon event processing.
- `TopChrome.qml` forwards the same broad model set to both `Bar` and the
  island, while `SurfaceCoordinator` and `PanelController` overlap on surface
  policy.
- The former runtime palette path replaced wallpaper-derived colors with fixed
  values and optionally ran `wal`, `matugen`, and `pywalfox`; it also rewrote
  VS Code settings in place. The palette compiler is now isolated in
  `hypr/scripts/nox-theme.py`, and the optional competing engines/unsafe editor
  mutation have been removed from `theme-sync.sh`.
- README network/keybind prose contradicted executable policy. README now
  describes iwd/networkd/resolved and `SUPER+W` wallpaper consistently with
  the Lua bindings and generated keybind document.
- `.agent/context.md`, `handoff.md`, task graph, task files, subtasks and RAG
  traces are runtime state and were tracked despite `.gitignore` rules. The
  durable `memory.md`, `decisions.md` and `checks.md` files remain available;
  runtime entries are removed from the working tree so the next commit can
  purge them from Git.

## Implementation boundary

This pass delivers the first safe slice: one deterministic, content-hashed,
contrast-validated theme compiler, a thin compatibility integration, corrected
source-of-truth documentation, and runtime-state cleanup. The QML capsule
split, live token watcher, transactional adapter directory, package profiles,
and full runtime/device validation remain explicitly listed in `ROADMAP.md`.
