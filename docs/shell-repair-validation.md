# Shell repair validation

Run on 2026-07-29 in the live Hyprland session:

- Hyprland 0.56.0, Quickshell 0.3.0.
- Monitor: `eDP-1`, 1920x1080, scale 1.0.
- Reference video inspected from `~/Downloads/shareExample.mp4` (1920x1080, 40.93 seconds).
- No Waybar process or Wayle layer was active; `noxflow-shell.service` owned the shell.

## Completed checks

- `tests/smoke/test-noxflow-surfaces.sh`: 22 passes, 0 failures.
- Launcher rapid-toggle test: passed; no duplicate launcher surface remained.
- Calendar, quick settings, notifications, and media all created real panel layers.
- Escape removed the active modal/panel layer and no fullscreen input layer remained.
- Morph sample: early geometry differed from settled geometry, confirming host-window expansion rather than a final-size fade.
- Shell restart and diagnostics: service active, IPC reachable, no new QML errors/warnings after the smoke run.
- Workspace dispatch repair: bar workspace activation now uses direct Hyprland compositor IPC and no longer depends on a timed-out noxd action.
- Control Centre repair: live layer settled at `1528 88 380 720` instead of the previous full-height `380x1016`; tab labels no longer overlap, and the current saved Wi-Fi profile (`Airtel_shub_6992`) is addressed by its NetworkManager connection name rather than an empty scanned-AP UUID.
- Control Centre animation repair: removed the inner dim/0.85-scale animation, changed lifecycle opening to `Easing.OutCubic`, and kept the shared MorphSurface responsible for geometry.
- Control Centre state repair: Wi-Fi now reads confirmed `wifi_enabled`, hardware, connectivity, and SSID fields; Bluetooth reads adapter/power/discovery/connected-device state; audio exposes confirmed default device names and volume/mute state.
- Power profile repair: provider profile objects are normalized to profile names before comparison or action dispatch, so the active profile highlight and cycle action use the confirmed profile string.

## Manual interaction matrix

| Interaction | Implementation | Result |
|---|---|---|
| Workspace number | Lua-aware `hyprctl dispatch 'hl.dsp.focus({ workspace = "<name>" })'` via `Bar.qml` | Fixed and compositor-tested |
| Clock | Calendar trigger registry + shared morph surface | Verified by layer geometry |
| Network/Bluetooth/volume/battery | Quick-settings trigger registry | Routed to quick settings |
| Notifications | Notification trigger registry | Verified by layer creation |
| Media | Media trigger registry | Verified by layer creation |
| `Super+Space` | `noxctl panel toggle launcher` | Smoke-tested |
| `Super+D` | `noxctl panel toggle dashboard` | Smoke-tested |
| Escape/outside dismissal | Shared surface lifecycle/coordinator | Smoke-tested |

## Reload and rollback

Reload:

```bash
systemctl --user restart noxflow-shell.service
```

Rollback the shell service only:

```bash
systemctl --user stop noxflow-shell.service
```

Restore the previous working tree state only after reviewing local changes:

```bash
git diff -- shell/noxflow hypr/conf/40-binds-launch.lua hypr/scripts/shellctl
```

The repository contains unrelated pre-existing changes, so no destructive reset was performed.

## Remaining limitations

- Only the current laptop monitor was available for live multi-monitor/disconnect validation.
- Bluetooth provider tooling is unavailable in this session (`bluetoothctl` missing), so the Bluetooth panel route was validated structurally rather than against a live device toggle.
- The calendar, notifications, and media surfaces are now hosted by the shared major-panel surface, but their internal content remains the existing implementation.
