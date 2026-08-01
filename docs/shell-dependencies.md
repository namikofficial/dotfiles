# Shell dependencies

Required:

- `quickshell`, Qt6 image formats/multimedia/5compat
- `noxd` and `noxctl` built from this repository
- Hyprland and its IPC socket
- PipeWire/WirePlumber (`wpctl` or `pactl`)
- iwd (`iwctl`)
- systemd-networkd (`networkctl`)
- BlueZ (`bluetoothctl`, optional provider degradation is supported)

Optional:

- `gcalcli` for the calendar adapter
- `matugen` for wallpaper-derived palette generation
- `grim` and `notify-send` for capture/status feedback
- Wayle only for explicit safe mode

The package baseline is tracked in `setup/pacman-packages.txt`; no unrelated
dotfiles or packages are added by this shell change.
