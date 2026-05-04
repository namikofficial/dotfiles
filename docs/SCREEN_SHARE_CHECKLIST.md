# Screen Share Checklist

## Debug Snapshot

Before changing settings, collect a log:

```sh
~/.config/hypr/scripts/screen-share-debug.sh
```

## Portal Routing

Expected routing:

```text
Screen sharing    -> xdg-desktop-portal-hyprland
Screenshots       -> xdg-desktop-portal-hyprland
Global shortcuts  -> xdg-desktop-portal-hyprland
File picker       -> xdg-desktop-portal-gtk
Other fallback    -> gtk
```

Repo-owned preference file:

```text
~/.config/xdg-desktop-portal/hyprland-portals.conf
```

## Tests

Test these after reboot or portal restarts:

```text
Chrome/Chromium:
- full monitor share
- single window share
- selected region if offered

Discord / Electron apps:
- full monitor share
- single window share

OBS:
- PipeWire monitor capture
- PipeWire window capture

Screenshot/OCR:
- grim + slurp area capture
- OCR area capture
```

## Repair Order

```sh
~/.config/hypr/scripts/restart-portals.sh
~/.config/hypr/scripts/restart-media-stack.sh
```
