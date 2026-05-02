# Network Stack Policy

This workstation standard is:

- `NetworkManager` as the network orchestrator
- `wpa_supplicant` as the Wi-Fi backend
- `iwd` not installed and its service masked

## Why

- Avoids backend contention (`iwd` vs `wpa_supplicant`) and flaky Wi-Fi behavior.
- Matches the rest of this dotfiles setup (`nmcli`, tray tooling, panel/network scripts).
- Keeps Wi-Fi behavior predictable across reboots and package updates.

## Enforce (idempotent)

Run:

```sh
./setup/enforce-network-stack.sh
```

The script will:

- Install `networkmanager` and `wpa_supplicant` if missing
- Remove `iwd` if installed
- Mask `iwd.service`
- Pin NetworkManager backend via `/etc/NetworkManager/conf.d/20-wifi-backend.conf`
- Restart NetworkManager and print verification output

## Expected service state

```text
NetworkManager.service   active (running)
wpa_supplicant.service   active (running)
iwd.service              masked / inactive
```
