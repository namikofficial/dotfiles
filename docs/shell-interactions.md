# Shell interactions

## Primary paths

- Clock: toggle Calendar.
- Notification chip / `Super+N`: toggle Notification Centre.
- Status cluster / `Super+Shift+B`: toggle Quick Settings.
- Quick Settings owns Network, Bluetooth, audio, brightness, DND, idle
  inhibition, battery, and power-profile controls.
- Media pill: opens the dedicated media surface; playback controls remain
  provider-backed and the bar remains compact.
- `Escape`, outside-click handling owned by a surface, or `shellctl close`
  closes the active major panel.

## Existing bindings preserved

The repository already uses `Super+N` for notifications, `Super+Shift+C` for
calendar, `Super+Shift+B` for control centre, and `Super+Escape` for the
session menu. They remain unchanged to avoid disrupting window/layout habits.
The new stable command surface is:

```sh
shellctl toggle calendar
shellctl toggle quick-settings
shellctl toggle notifications
shellctl close
shellctl reload
shellctl diagnostics
```

For users who prefer the main CLI, the same actions are available directly:

```sh
noxctl calendar
noxctl quick-settings
noxctl notifications
noxctl media panel
noxctl close
```

Focus rings and accessible names are provided by existing shared components;
keyboard Escape paths are installed on every major panel.
