#!/usr/bin/env bash
set -euo pipefail

# Enforce the workstation Wi-Fi standard: iwd + systemd-networkd.
# Run from a local terminal. The active NetworkManager connection is stopped
# only after iwd and networkd are ready to take over.

DRY_RUN=0
AUTO_YES=0
SSID=""
BSSID=""
CHANNEL=""

usage() {
  cat <<'EOF'
usage: enforce-network-stack.sh --ssid SSID [--bssid BSSID] [--channel CHANNEL] [--dry-run] [--yes]

  --ssid SSID       Wi-Fi network to connect after migration (required)
  --bssid BSSID     Prefer this access point, normally the 5 GHz BSSID
  --channel CHANNEL Record the expected channel for verification
  --dry-run         Print actions without changing the system
  --yes             Skip the confirmation prompt
EOF
}

while (($#)); do
  case "$1" in
    --ssid)
      SSID="${2:-}"
      shift
      ;;
    --bssid)
      BSSID="${2:-}"
      shift
      ;;
    --channel)
      CHANNEL="${2:-}"
      shift
      ;;
    --dry-run) DRY_RUN=1 ;;
    --yes) AUTO_YES=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$SSID" ]; then
  usage >&2
  exit 2
fi

as_root() {
  if ((EUID == 0)); then "$@"; else sudo "$@"; fi
}

run_root() {
  if ((DRY_RUN)); then
    printf '[dry-run] sudo'
    printf ' %q' "$@"
    printf '\n'
  else
    as_root "$@"
  fi
}

confirm() {
  if ((DRY_RUN || AUTO_YES)); then return; fi
  printf 'This disables NetworkManager/wpa_supplicant and enables iwd/networkd. Continue? [y/N] '
  read -r answer
  case "${answer:-N}" in y | Y | yes | YES) ;; *)
    echo 'Aborted.'
    exit 1
    ;;
  esac
}

wifi_if() {
  iwctl station list 2>/dev/null |
    sed 's/\x1b\[[0-9;]*m//g' |
    awk '$1 ~ /^(wlan|wlp)/ { print $1; exit }'
}

echo '==> Migrating Wi-Fi to iwd + systemd-networkd'
confirm

run_root pacman -S --needed iwd
run_root systemctl unmask iwd.service
run_root systemctl enable iwd.service systemd-networkd.service systemd-resolved.service
run_root mkdir -p /etc/systemd/network
run_root mkdir -p /etc/iwd
run_root mkdir -p /etc/systemd/system/systemd-networkd-wait-online.service.d

if ((DRY_RUN)); then
  echo '[dry-run] write /etc/iwd/main.conf'
else
  printf '%s\n' \
    '[General]' \
    'EnableNetworkConfiguration=false' \
    'RoamThreshold5G=-76' \
    '' \
    '[Rank]' \
    'BandModifier2_4GHz=0.0' \
    'BandModifier5GHz=1.5' \
    '' \
    '[DriverQuirks]' \
    'PowerSaveDisable=iwlwifi' |
    as_root tee /etc/iwd/main.conf >/dev/null
fi

if ((DRY_RUN)); then
  echo '[dry-run] write /etc/systemd/system/systemd-networkd-wait-online.service.d/10-wlan-only.conf'
else
  printf '%s\n' \
    '[Service]' \
    'ExecStart=' \
    'ExecStart=/usr/lib/systemd/systemd-networkd-wait-online --interface=wlan0 --ipv4' |
    as_root tee /etc/systemd/system/systemd-networkd-wait-online.service.d/10-wlan-only.conf >/dev/null
fi

network_file=""
for candidate in /etc/systemd/network/*.network; do
  [ -f "$candidate" ] || continue
  network_file="$candidate"
  break
done

if [ -n "$network_file" ]; then
  echo "==> Reusing existing networkd profile: $network_file"
elif ((DRY_RUN)); then
  echo '[dry-run] write /etc/systemd/network/25-wireless.network'
else
  printf '%s\n' \
    '[Match]' \
    'Name=wl*' \
    '' \
    '[Network]' \
    'DHCP=yes' \
    'IPv6AcceptRA=yes' \
    'Domains=~.' |
    as_root tee /etc/systemd/network/25-wireless.network >/dev/null
fi

run_root systemctl restart systemd-networkd.service
run_root systemctl restart systemd-resolved.service
run_root systemctl daemon-reload
run_root ln -sfn /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

run_root systemctl stop NetworkManager.service
run_root systemctl stop wpa_supplicant.service
run_root systemctl disable NetworkManager.service wpa_supplicant.service
run_root systemctl start iwd.service

if ((DRY_RUN)); then
  echo "[dry-run] iwctl station <wifi-interface> connect $(printf %q "$SSID")"
else
  wifi="$(wifi_if)"
  if [ -z "$wifi" ]; then
    echo 'No iwd Wi-Fi station found.' >&2
    exit 1
  fi
  echo "==> Connecting $SSID with iwctl on $wifi"
  iwctl station "$wifi" connect "$SSID"
fi

echo
echo '==> Verification'
systemctl --no-pager --full --type=service --state=active |
  grep -E '^(iwd|systemd-networkd|systemd-resolved)\.service' || true
if ! ((DRY_RUN)); then
  wifi="$(wifi_if)"
  iwctl station "$wifi" show || true
  networkctl status "$wifi" --no-pager || true
  [ -z "$BSSID" ] || echo "Expected BSSID: $BSSID"
  [ -z "$CHANNEL" ] || echo "Expected channel: $CHANNEL"
fi
