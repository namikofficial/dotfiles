# 05 — Dependency Matrix

**Date:** 2026-07-31

What each shell surface/backend requires, and whether it's optional.

## Runtime (required)

| Component | Package | Used by | Notes |
|---|---|---|---|
| Quickshell | `quickshell` (pacman) | whole shell | shell.qml entry |
| noxd daemon | repo (cargo) | providers | build via `make install-bin` |
| noxctl CLI | repo (cargo) | keybinds, IPC | build via `make install-bin` |
| Hyprland | `hyprland` | compositor | 0.56.0 at baseline |
| Qt6 Quick | `qt6-base` + QML modules | QML shell | see release-gate check_optional_runtime |

## Backends (providers, via noxd)

| Provider | Backend | Package |
|---|---|---|
| audio | PipeWire + pactl | `pipewire` `pulseaudio-utils` |
| bluetooth | BlueZ D-Bus | `bluez` `bluez-utils` |
| brightness | D-Bus (ddcci/wlroots) | kernel + `brightnessctl` |
| hyprland | Hyprland sockets | `hyprland` |
| media | MPRIS D-Bus | any MPRIS player |
| network | iwd/iwctl + systemd-networkd | `iwd`, `systemd` |
| power | UPower D-Bus | `upower` |

## New in this redesign

| Component | Package | Required? | Notes |
|---|---|---|---|
| hyprland-scroll-overview | hyprpm / source build | **yes** (overview) | ABI-breaking; rebuild after Hyprland upgrades (`setup/scrolloverview-rebuild.sh`) |
| LocalSend | `localsend-bin` (AUR) | **yes** (Quick Share) | 1.17.0; systemd user service autostarts |
| wl-clipboard | `wl-clipboard` | yes (clipboard panel) | `wl-copy` for copy action |

## Existing integrations reused (no new deps)

| Concern | Existing tool |
|---|---|
| Wallpaper | `hypr/scripts/set-wallpaper.sh` (hyprpaper + matugen) |
| Theme pass | `hypr/scripts/theme-pass.sh` (GTK, kitty, shell tokens) |
| Clipboard capture | `cliphist-daemon.sh` + `ClipboardModel` |
| Notifications | `NotificationModel` + daemon |
| Syncthing | companion integration (unchanged) |

## Optional

| Package | Purpose | If missing |
|---|---|---|
| `pavucontrol` / `blueman` / `nm-connection-editor` | utility apps | panels still show state; apps just won't launch |
| `rofi` | fallback pickers (SUPER+O) | wallpaper panel covers it |
| `hyprexpo` | legacy overview fallback | super-tab-overview.sh falls through to workspace-overview.sh |

## Firewall

LocalSend needs port 53317 (TCP+UDP) open on the local network for discovery
and transfer. Documented in LocalSend README; check `ufw`/`firewalld` if
devices don't appear.
