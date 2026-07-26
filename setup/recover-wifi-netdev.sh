#!/usr/bin/env bash
set -euo pipefail

SSID="${1:-Airtel_shub_6992}"
BSSID="${2:-78:BB:C1:13:A6:4A}"
CHANNEL="${3:-161}"
CONNECT=0

if [ "${1:-}" = "--connect" ]; then
  CONNECT=1
  SSID="${2:-Airtel_shub_6992}"
  BSSID="${3:-78:BB:C1:13:A6:4A}"
  CHANNEL="${4:-161}"
fi

as_root() {
  if ((EUID == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

if nmcli -t -f NAME connection show | grep -Fx -- "$SSID" >/dev/null 2>&1; then
  echo "==> Pinning NetworkManager profile to 5 GHz"
  nmcli connection modify "$SSID" \
    connection.interface-name "" \
    802-11-wireless.band a \
    802-11-wireless.channel "$CHANNEL" \
    802-11-wireless.bssid "$BSSID" \
    802-11-wireless.powersave 2 \
    connection.autoconnect yes \
    connection.autoconnect-priority 50
fi

echo "==> Reloading Intel Wi-Fi driver to recreate the Wi-Fi interface"
as_root systemctl stop NetworkManager.service
as_root modprobe -r iwlmvm iwlwifi
as_root modprobe iwlwifi
as_root systemctl start NetworkManager.service

echo "==> Reloading NetworkManager profiles"
as_root nmcli connection reload
nmcli radio wifi on

wifi_if="$(
  nmcli -t -f DEVICE,TYPE device status |
    awk -F: '$2 == "wifi" { print $1; exit }'
)"

if [ -z "$wifi_if" ]; then
  echo "No NetworkManager Wi-Fi device found after driver reload." >&2
  nmcli device status >&2 || true
  exit 1
fi

if ((CONNECT)) && ! nmcli -t -f NAME connection show | grep -Fx -- "$SSID" >/dev/null 2>&1; then
  echo "==> Creating NetworkManager profile for $SSID on $wifi_if"
  nmcli device wifi connect "$BSSID" ifname "$wifi_if" name "$SSID" --ask
fi

if nmcli -t -f NAME connection show | grep -Fx -- "$SSID" >/dev/null 2>&1; then
  nmcli connection modify "$SSID" \
    connection.interface-name "" \
    802-11-wireless.band a \
    802-11-wireless.channel "$CHANNEL" \
    802-11-wireless.bssid "$BSSID" \
    802-11-wireless.powersave 2 \
    connection.autoconnect yes \
    connection.autoconnect-priority 50
fi

if ((CONNECT)); then
  echo "==> Connecting to $SSID on 5 GHz BSSID $BSSID"
  nmcli connection up "$SSID" ifname "$wifi_if"
fi

echo
echo "==> Verification"
nmcli -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS device show "$wifi_if" 2>/dev/null || true
nmcli -f ACTIVE,SSID,BSSID,CHAN,FREQ,RATE,SIGNAL,DEVICE device wifi list --rescan no | sed -n '1,12p'
