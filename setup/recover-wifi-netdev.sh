#!/usr/bin/env bash
set -euo pipefail

SSID="Airtel_shub_6992"
BSSID="78:BB:C1:13:A6:4A"
CHANNEL="153"
CONNECT=0

if [ "${1:-}" = '--connect' ]; then
  CONNECT=1
  SSID="${2:-$SSID}"
  BSSID="${3:-$BSSID}"
  CHANNEL="${4:-$CHANNEL}"
fi

as_root() {
  if ((EUID == 0)); then "$@"; else sudo "$@"; fi
}

wifi_if() {
  iwctl station list 2>/dev/null |
    sed 's/\x1b\[[0-9;]*m//g' |
    awk '$1 ~ /^(wlan|wlp)/ { print $1; exit }'
}

echo '==> Reloading Intel Wi-Fi driver'
as_root systemctl restart iwd.service
wifi="$(wifi_if)"
if [ -z "$wifi" ]; then
  echo 'No iwd Wi-Fi station found after restarting iwd.' >&2
  iwctl station list >&2 || true
  exit 1
fi

if ((CONNECT)); then
  echo "==> Connecting $SSID on $wifi"
  iwctl station "$wifi" connect "$SSID"
fi

echo
echo '==> Verification'
iwctl station "$wifi" show
networkctl status "$wifi" --no-pager || true
echo "Expected BSSID: $BSSID"
echo "Expected channel: $CHANNEL"
