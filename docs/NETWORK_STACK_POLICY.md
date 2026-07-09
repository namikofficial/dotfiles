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

If the machine is currently online through `iwd`, migrate the active SSID
through NetworkManager first:

```sh
./setup/enforce-network-stack.sh --ssid "Your Wi-Fi SSID"
```

The script uses `nmcli --ask` for credentials when NetworkManager does not
already have a saved profile, then removes `iwd` after the NetworkManager
profile exists.

For dual-band routers that reuse one SSID for 2.4 GHz and 5 GHz, pin the
known-good 5 GHz BSSID:

```sh
./setup/enforce-network-stack.sh --ssid "Airtel_shub_6992" --bssid "78:BB:C1:13:A6:4A" --channel 161
```

If `iwd` exits badly and the `wlan0` interface disappears, recover it with:

```sh
./setup/recover-wifi-netdev.sh
```

That restores the NetworkManager Wi-Fi device without creating a Wi-Fi profile.
To recreate and connect the known 5 GHz profile in one step, use:

```sh
./setup/recover-wifi-netdev.sh --connect "Airtel_shub_6992" "78:BB:C1:13:A6:4A" 161
```

## Expected service state

```text
NetworkManager.service   active (running)
wpa_supplicant.service   active (running)
iwd.service              masked / inactive
```
