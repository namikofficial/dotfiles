# 08 — Known Limitations

**Date:** 2026-07-31

Honest list of what is NOT fully implemented or has known caveats.

## Quick Share (M12)

- **Transfers are app-owned.** LocalSend's upload API runs on the *peer* device,
  requiring per-peer discovery + cert validation that only the LocalSend app
  implements. The shell panel is a launch point + honest status surface; the
  actual accept/decline/progress UI is the LocalSend window/notifications.
- **No transfer progress in the shell.** Because transfers happen inside the
  app, the panel cannot show byte-level progress without reimplementing the
  peer protocol (deliberately avoided per design contract §7).
- **`--hidden` crashes** on localsend-bin 1.17.0 (`hideToTray`
  LateInitializationError — appindicator unavailable). The systemd unit
  launches plain, so the app window appears on login. Revisit after upstream
  fixes or if an appindicator host appears.
- **Daemon must be running** for discovery; the panel surfaces "LocalSend not
  running" honestly when the service is down.

## ScrollOverview (M10)

- **ABI-breaking plugin.** Every Hyprland upgrade requires a rebuild
  (`hyprpm update && hyprpm enable scrolloverview`, or
  `setup/scrolloverview-rebuild.sh --source`). Until rebuilt, SUPER+TAB falls
  back to the legacy `super-tab-overview.sh` script.
- **hyprpm state-store bug:** the first `hyprpm update` runs sudo and leaves a
  root-owned `/var/cache/hyprpm/<user>` store; later non-root `hyprpm add`
  fails "Headers outdated". Fix documented in
  `setup/scrolloverview-rebuild.sh` and session notes.

## Morph engine (M6/M7)

- **Content components own their own lifecycle** (`SurfaceLifecycle`). The
  MorphSurface coordinates geometry + crossfade, but each panel's internal
  open/close animation runs independently. Panels with complex internal
  animations (e.g. ControlCentre) may show a slightly different rhythm than
  the frame morph. Acceptable; revisit per-panel if noticeable.
- **Reduced motion** skips geometry animation but content crossfade still runs
  briefly (contentEnter/contentExit at reduced duration).
- **No per-panel custom geometry profiles yet.** All panels use the default
  width/height table in `MorphSurface.geometryFor`; custom sizes per panel
  (e.g. a taller media panel) are future work.

## Clipboard panel

- Copy uses `wl-copy` via a detached Process. Works for text; images/rich
  content are not specially handled (history stores text).
- `ClipboardModel` captures via cliphist daemon when running; the in-shell
  model is the display layer.

## Wallpaper panel (M13)

- Thumbnails are async-loaded full-res images (no pre-generated thumbs).
  Large 4K sets may use memory until scrolled. Acceptable at this scale.
- Applying calls `set-wallpaper.sh <path>` which runs matugen + theme
  propagation; the panel doesn't wait for completion (fire-and-forget with
  error surfacing on scan, not apply).

## General

- **Wayle is masked.** The `noxflow-fallback.service` OnFailure path is a no-op
  while Wayle stays masked (intentional: single-shell guarantee).
- **Launcher.qml** has a pre-existing qmllint failure (unrelated to this
  redesign; was failing at baseline). Launcher still functions at runtime.
- **No CI/CD** in the repo; validation is the release gate +
  `setup/check-shell.sh` run manually.
- **`systemd-analyze --user verify`** prints an unrelated warning from
  `~/.config/environment.d/60-android.conf` (pre-existing).
