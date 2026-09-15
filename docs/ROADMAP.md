# Roadmap

Only unfinished work belongs here. Completed investigations and historical
plans are intentionally not repeated.

## P1 — shell ownership

- Add a shell-level `ActivityController` that subscribes to `noxd` once.
- Replace the multipurpose `NoxIsland` with a narrow, reduced-motion-aware
  Activity Capsule; remove launcher/calendar/hover-dashboard ownership from it.
- Consolidate `PanelController` and `SurfaceCoordinator` mutual-exclusion
  rules and add an Escape-priority contract test.
- Replace Bar's periodic workspace polling with model/event-driven refreshes.

## P1 — live theme runtime

- Hydrate `Theme.Tokens` from `nox-theme-schema-v1` through a watched file or a
  typed daemon event, with perceptual interpolation and last-known-good state.
- Stage adapter files in a temporary directory and atomically publish the
  complete adapter set; add rollback and rapid-switch tests.
- Add tmux and safe VS Code adapters that consume canonical JSON without
  rewriting user settings.

## P2 — source-of-truth cleanup

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
