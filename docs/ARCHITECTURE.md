# Workstation architecture

This is the short, current map of the dotfiles. Historical audits and design
experiments under `docs/audits/` and `docs/shell-redesign/` are background, not
authoritative operating instructions.

## Runtime ownership

| Concern | Normal owner | Boundary |
| --- | --- | --- |
| Compositor | Hyprland | `hypr/hyprland.lua` and `hypr/conf/` |
| Desktop shell | NoxFlow | `shell/noxflow/shell.qml` |
| Shell IPC/providers | `noxd` | Rust workspace and Unix socket |
| Major surfaces | `PanelController` + `MorphSurface` | `shell/noxflow/core/` |
| Wi-Fi/DHCP/DNS | iwd + systemd-networkd + systemd-resolved | `docs/NETWORK_STACK_POLICY.md` |
| Wallpaper daemon | hyprpaper | `hypr/scripts/set-wallpaper.sh` |
| Wallpaper/theme compiler | `nox-theme.py` | `hypr/scripts/nox-theme.py` |
| Theme adapters | `theme-sync.sh` and hook directory | generated files under `$XDG_CACHE_HOME`/`$HOME/.cache` |
| Fallback shell | Wayle | explicit safe-mode only; never co-runs with NoxFlow |

## Shell composition

NoxFlow keeps one daemon client and typed provider models at the composition
root. `PanelController` owns major-panel exclusivity and `MorphSurface` is the
single major-panel layer-surface per monitor. Dedicated surfaces (launcher,
calendar, notifications, control centre, media, clipboard, wallpaper and
share) remain separate components.

The current island is a migration boundary. New work must not add launcher,
calendar, dashboard or settings responsibilities to `NoxIsland.qml`. The
target is a narrow Activity Capsule fed by one shell-level activity stream;
the remaining migration is tracked in `ROADMAP.md`.

## Theme data flow

```text
wallpaper bytes
  -> nox-theme.py (SHA-256, deterministic policy, contrast validation)
  -> ~/.cache/hypr/theme-palette.json (nox-theme-schema-v1)
  -> theme-sync.sh (Rofi/Kitty/Hyprlock/GTK/legacy hook adapters)
```

`nox-theme.py` is the only palette calculator. Adapters must consume the
canonical JSON or its compatibility environment; they must not quantize the
wallpaper again or rewrite user-owned settings. Theme generation is skipped
when the caller has no valid wallpaper and returns a non-zero status when the
semantic contrast report fails.

## Change rules

- Prefer typed IPC/events over QML subprocesses.
- Keep generated/runtime state out of Git; durable decisions belong in docs.
- Keep package profiles declarative and do not uninstall automatically.
- Make one normal owner explicit for every service or integration.
- Verify the narrowest affected surface before claiming success.
