#!/usr/bin/env bash
set -euo pipefail

# Enforce the workstation Wi-Fi standard:
# NetworkManager + wpa_supplicant backend, with iwd disabled.

DRY_RUN=0
AUTO_YES=0
SSID=""
BSSID=""
CHANNEL=""

usage() {
  cat <<'EOF'
usage: enforce-network-stack.sh [--dry-run] [--yes]

  --dry-run  Show the actions without changing the system.
  --yes      Apply the destructive changes without prompting.
  --ssid SSID
             Ensure NetworkManager has a Wi-Fi connection for SSID before
             removing iwd. If no saved profile exists, nmcli will ask for
             credentials in an interactive terminal.
  --bssid BSSID
             Pin the NetworkManager Wi-Fi profile to a specific access point.
  --channel CHANNEL
             Pin the NetworkManager Wi-Fi profile to a specific channel.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --yes) AUTO_YES=1 ;;
    --ssid)
      SSID="${2:-}"
      [ -n "$SSID" ] || {
        echo "--ssid requires a value" >&2
        exit 1
      }
      shift
      ;;
    --bssid)
      BSSID="${2:-}"
      [ -n "$BSSID" ] || {
        echo "--bssid requires a value" >&2
        exit 1
      }
      shift
      ;;
    --channel)
      CHANNEL="${2:-}"
      [ -n "$CHANNEL" ] || {
        echo "--channel requires a value" >&2
        exit 1
      }
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

as_root() {
  if ((EUID == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

run_root() {
  if ((DRY_RUN)); then
    printf '[dry-run] sudo %s\n' "$*"
  else
    as_root "$@"
  fi
}

confirm() {
  if ((DRY_RUN || AUTO_YES)); then
    return 0
  fi
  printf 'This will remove iwd if installed and restart NetworkManager. Continue? [y/N] '
  read -r answer
  case "${answer:-N}" in
    y | Y | yes | YES) ;;
    *)
      echo "Aborted."
      exit 1
      ;;
  esac
}

echo "==> Enforcing NetworkManager + wpa_supplicant policy"
confirm

nm_wifi_state() {
  nmcli -t -f WIFI g 2>/dev/null || true
}

nm_has_wifi_connection() {
  [ -n "$SSID" ] || return 1
  nmcli -t -f NAME,TYPE connection show 2>/dev/null |
    awk -F: '$2 == "802-11-wireless" { print $1 }' |
    grep -Fx -- "$SSID" >/dev/null 2>&1
}

nm_connected_wifi_device() {
  nmcli -t -f DEVICE,TYPE,STATE d 2>/dev/null |
    awk -F: '$2 == "wifi" && $3 == "connected" { print $1; exit }'
}

nm_any_wifi_device() {
  nmcli -t -f DEVICE,TYPE d 2>/dev/null |
    awk -F: '$2 == "wifi" { print $1; exit }'
}

iwd_connected_ssid() {
  command -v iwctl >/dev/null 2>&1 || return 0
  iwctl station list 2>/dev/null |
    awk 'NR > 4 && $1 !~ /^-+$/ { print $1; exit }' |
    while read -r station; do
      [ -n "$station" ] || continue
      iwctl station "$station" show 2>/dev/null |
        awk -F'Connected network[[:space:]]+' '/Connected network/ { print $2; exit }' |
        sed 's/[[:space:]]*$//'
    done |
    sed -n '1p'
}

if ! pacman -Q networkmanager >/dev/null 2>&1 || ! pacman -Q wpa_supplicant >/dev/null 2>&1; then
  echo "==> Installing required packages: networkmanager, wpa_supplicant"
  run_root pacman -S --needed networkmanager wpa_supplicant
fi

if [ -n "$SSID" ] && ! nm_has_wifi_connection; then
  echo "==> Creating NetworkManager Wi-Fi profile for: $SSID"
  if ((DRY_RUN)); then
    printf '[dry-run] nmcli device wifi connect %q --ask\n' "$SSID"
  else
    nmcli device wifi connect "$SSID" --ask
    nmcli connection modify "$SSID" connection.interface-name ""
  fi
fi

if [ -n "$SSID" ] && { [ -n "$BSSID" ] || [ -n "$CHANNEL" ]; }; then
  echo "==> Pinning NetworkManager Wi-Fi profile to 5 GHz preferences"
  if ((DRY_RUN)); then
    printf '[dry-run] nmcli connection modify %q 802-11-wireless.band a' "$SSID"
    [ -z "$BSSID" ] || printf ' 802-11-wireless.bssid %q' "$BSSID"
    [ -z "$CHANNEL" ] || printf ' 802-11-wireless.channel %q' "$CHANNEL"
    printf ' 802-11-wireless.powersave 2 connection.autoconnect-priority 50\n'
  else
    nm_args=(
      connection modify "$SSID"
      connection.interface-name ""
      802-11-wireless.band a
      802-11-wireless.powersave 2
      connection.autoconnect-priority 50
    )
    [ -z "$BSSID" ] || nm_args+=(802-11-wireless.bssid "$BSSID")
    [ -z "$CHANNEL" ] || nm_args+=(802-11-wireless.channel "$CHANNEL")
    nmcli "${nm_args[@]}"
  fi
fi

if [ -z "$SSID" ] &&
  [ -n "$(iwd_connected_ssid)" ] &&
  { [ "$(nm_wifi_state)" != "enabled" ] || [ -z "$(nm_connected_wifi_device)" ]; }; then
  cat >&2 <<EOF
Refusing to remove iwd while it appears to own the active Wi-Fi connection.

Run this once from a terminal so NetworkManager saves the Wi-Fi credentials:

  ./setup/enforce-network-stack.sh --ssid "$(iwd_connected_ssid)"

Then rerun this script normally if needed.
EOF
  exit 1
fi

if pacman -Q iwd >/dev/null 2>&1; then
  echo "==> Removing conflicting package: iwd"
  run_root pacman -Rns --noconfirm iwd
fi

echo "==> Masking iwd service to prevent accidental enable"
run_root systemctl mask iwd.service || true

echo "==> Pinning NetworkManager backend to wpa_supplicant"
run_root mkdir -p /etc/NetworkManager/conf.d
if ((DRY_RUN)); then
  cat <<'EOF'
[dry-run] write /etc/NetworkManager/conf.d/20-wifi-backend.conf
[device]
wifi.backend=wpa_supplicant
EOF
else
  cat <<'EOF' | as_root tee /etc/NetworkManager/conf.d/20-wifi-backend.conf >/dev/null
[device]
wifi.backend=wpa_supplicant
EOF
fi
run_root rm -f /etc/NetworkManager/conf.d/10-iwd.conf

echo "==> Restarting network services"
run_root systemctl enable --now NetworkManager.service
run_root systemctl restart NetworkManager.service
if [ -z "$(nm_any_wifi_device)" ] && lsmod | grep -q '^iwlwifi'; then
  echo "==> Wi-Fi device missing after iwd removal; reloading Intel Wi-Fi driver"
  run_root systemctl stop NetworkManager.service
  run_root modprobe -r iwlmvm iwlwifi
  run_root modprobe iwlwifi
  run_root systemctl start NetworkManager.service
fi
if [ -n "$SSID" ]; then
  if ((DRY_RUN)); then
    printf '[dry-run] sudo nmcli connection reload\n'
    printf '[dry-run] nmcli connection up %q\n' "$SSID"
  else
    run_root nmcli connection reload || true
    nmcli connection up "$SSID" || true
  fi
fi

if ((DRY_RUN)); then
  echo
  echo "==> Dry run complete"
  exit 0
fi

echo
echo "==> Verification"
systemctl list-units --type=service | grep -E "NetworkManager|wpa_supplicant|iwd" || true
echo
if command -v iw >/dev/null 2>&1; then
  iw dev | sed -n '1,80p'
fi
