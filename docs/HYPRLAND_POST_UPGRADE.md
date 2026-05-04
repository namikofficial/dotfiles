# Hyprland Post-Upgrade Checklist

Run this after Hyprland, NVIDIA, kernel, PipeWire, or portal upgrades.

## First Rule

Reboot after ABI-sensitive upgrades. Arch package release changes can rebuild Hyprland against newer ecosystem libraries even when the upstream Hyprland version is unchanged.

Example:

```text
hyprland 0.54.3-3 -> 0.54.3-4
```

Here `0.54.3` is the upstream Hyprland version. The `-3 -> -4` suffix is the Arch package release.

## Verify

```sh
~/Documents/code/dotfiles/setup/post-reboot-verify.sh
~/.config/hypr/scripts/compositor-facts.sh
```

The verify script is read-only. It should not restart the panel, portals, PipeWire, or Hyprland.

## Repair Commands

Use the narrow repair first:

```sh
~/.config/hypr/scripts/restart-portals.sh
```

Use the stronger media restart only when screen sharing still fails:

```sh
~/.config/hypr/scripts/restart-media-stack.sh
```

## Panel Policy

Wayle is the primary panel shell and notification UI.

```sh
~/.config/hypr/scripts/panel-switch.sh wayle
~/.config/hypr/scripts/panel-switch.sh show
```
