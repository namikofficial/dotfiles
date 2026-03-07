# Settings System

This repository now includes a schema-driven settings layer.

## Files

- `settings/schema.json`: contract for supported settings.
- `settings/defaults.json`: baseline settings.
- `settings/state.json`: overrides.
- `settings/state.local.json`: optional local-only machine overrides (gitignored).
- `settings/profiles/*.json`: selectable machine profiles.
- `hypr/scripts/settingsctl`: CLI entrypoint.
- `hypr/scripts/settings-hub.sh`: Rofi Settings Hub.
- `hypr/scripts/settings-eww.sh`: optional Eww detailed panel.
- `hypr/scripts/settings/apply.sh`: apply engine.
- `hypr/scripts/settings/doctor.sh`: drift checks.
- `hypr/scripts/settings/keybind-check.sh`: duplicate keybind detector.
- `setup/apply-system-profile.sh`: root-level system profile apply.

## Commands

```sh
~/.config/hypr/scripts/settingsctl list
~/.config/hypr/scripts/settingsctl get notifications.timeout
~/.config/hypr/scripts/settingsctl set notifications.timeout 12
~/.config/hypr/scripts/settingsctl toggle notifications.sounds.enabled
~/.config/hypr/scripts/settingsctl apply all
~/.config/hypr/scripts/settingsctl doctor
~/.config/hypr/scripts/settingsctl keycheck
~/.config/hypr/scripts/settingsctl profile list
~/.config/hypr/scripts/settingsctl profile apply dock
```

## Keybinds

- `Super + ,` -> open settings hub
- `Super + Shift + ,` -> re-apply last section
- `Super + Ctrl + ,` -> quick toggle notification sounds
- `Super + Alt + ,` -> toggle Eww settings panel

## System Profile

Apply templates for `/etc/modprobe.d`, boot entries, and Timeshift timer:

```sh
sudo ./setup/apply-system-profile.sh <root-partuuid>
```

This script creates timestamped backups before replacing files.
