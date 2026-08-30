# Shell audit — 2026-07-28

## Result

The repository already had a substantial NoxFlow Quickshell implementation:
per-monitor bar, Nox Island OSD, `noxd` provider models, Quick Settings,
calendar, notification centre, and systemd startup. A second full bar was not
introduced.

## Existing ownership

| Responsibility | Owner | Finding |
|---|---|---|
| Persistent bar and OSD | `shell/noxflow/Bar.qml`, `NoxIsland.qml` | Reused; bar was visually thin but reserved 56 logical px. |
| Network/Bluetooth/audio/brightness/power | `ControlCentre.qml` tabs | Reused as Quick Settings sections, not separate major panels. |
| Calendar | `CalendarWidget.qml` + `CalendarModel.qml` | Reused; data remains separate and uses cached Waylandar/gcalcli adapter. |
| Notifications | `NotificationCentre.qml` + `NotificationModel.qml` | Reused; history and DND are model-owned. |
| Startup | `noxflow-shell.service`, `panel-switch.sh` | NoxFlow was available but switcher defaulted to Wayle. |
| Keybindings | `hypr/conf/40-binds-launch.lua` | Existing bindings preserved; new IPC aliases avoid collisions. |
| Theme | `theme/tokens.toml`, `Tokens.qml`, theme sync cache | Reused; semantic token set already existed. |

## Problems addressed

- Major surfaces had independent lifecycle ownership and could overlap.
- Morph geometry was registered but not centrally coordinated; this is now
  owned by `MorphSurface`.
- The switcher defaulted to Wayle, making duplicate-shell ownership likely.
- Monitor config named `eDP-1` and duplicated responsibility with the hotplug
  monitor controller.
- Shell settings, geometry, and motion values were spread across components.
- No stable `shellctl` command existed for the requested panel vocabulary.

## Deliberate non-changes

The existing daemon/provider protocol, notification history model, calendar
adapter, media model, launcher, overview, capture, and existing Hyprland
bindings were not replaced. Wayle files and unrelated dotfiles were not
removed.
