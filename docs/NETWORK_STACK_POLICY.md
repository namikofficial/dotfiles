# Network Stack Policy

This workstation standard is:

- `iwd`/`iwctl` as the Wi-Fi orchestrator
- `systemd-networkd` for DHCP and IP configuration
- `systemd-resolved` for DNS
- NetworkManager and `wpa_supplicant` disabled to avoid backend contention

This keeps one Wi-Fi control path and avoids the unstable dual-band roaming
observed when the router advertises 2.4 GHz and 5 GHz under one SSID.

## Enforce

Run this from a local terminal because it changes system services:

```sh
./setup/enforce-network-stack.sh --ssid "Your Wi-Fi SSID"
```

The script installs iwd, enables iwd/networkd/resolved, disables conflicting
services, configures iwd to prefer 5 GHz and disable iwlwifi power saving,
saves the requested iwd profile, and prints verification output.

For the known-good 5 GHz access point:

```sh
./setup/enforce-network-stack.sh --ssid "Airtel_shub_6992" --bssid "78:BB:C1:13:A6:4A" --channel 153
```

The BSSID and channel are verification targets. iwd’s rank settings prefer
5 GHz and disable 2.4 GHz selection; confirm the actual BSSID/channel with
`iwctl station <interface> show` after connecting.

## Recovery

If the Wi-Fi interface disappears after a driver or service failure:

```sh
./setup/recover-wifi-netdev.sh
```

To recreate and connect the known 5 GHz profile:

```sh
./setup/recover-wifi-netdev.sh --connect "Airtel_shub_6992" "78:BB:C1:13:A6:4A" 153
```

## Expected service state

```text
iwd.service              active (running)
systemd-networkd.service active (running)
systemd-resolved.service active (running)
NetworkManager.service   inactive / disabled
wpa_supplicant.service   inactive / disabled
```
