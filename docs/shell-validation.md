# Shell validation

## Static checks

The following are safe to run from the repository root:

```sh
git diff --check
python3 -m unittest tests/theme/test_tokens.py
shellcheck hypr/scripts/shellctl hypr/scripts/shell-diagnostics hypr/scripts/panel-switch.sh
```

## Live E2E checklist

Run inside the Hyprland user session after installing/symlinking the shell:

```sh
systemctl --user restart noxd.service noxflow-shell.service
shellctl diagnostics
tests/smoke/test-noxflow-surfaces.sh
```

Then verify both displays, scale 1.5, monitor hotplug, fullscreen, rapid
calendar↔Quick Settings switching, Escape/outside close, audio/brightness
sliders, network/Bluetooth state, notifications, calendar refresh, media, and
session-action confirmation. Capture `setup/measure-noxflow.sh` output for
idle and active resource use.

## Current run limitation

This review ran in a restricted non-Wayland sandbox: `hyprctl`, the user D-Bus
session, and layer-shell surfaces were unavailable. Static repository checks
can run here, but live compositor/E2E results must be collected from the actual
Hyprland session with the commands above; they are not reported as passing by
assumption.

## Live run recorded 2026-07-28

- Hyprland 0.56.0, Quickshell 0.3.0.
- NoxFlow and noxd active; Wayle inactive; dunst owns notifications.
- Active monitor: `eDP-1`, 1920×1080, scale 1.0, 40 px top reservation.
- The live IPC sequence and corrected surface smoke test passed: 22 passes,
  0 failures, with no new QML errors/warnings during the test.
- Direct `noxctl` aliases passed for launcher, calendar, Quick Settings,
  notifications, media, and close.
- `bluetoothctl` was unavailable in the session, so Bluetooth controls remain
  dependency-degraded until it is installed/available.
- An external monitor and scale 1.5 could not be verified because only the
  laptop display was connected at scale 1.0.
