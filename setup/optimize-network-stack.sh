#!/usr/bin/env bash
set -euo pipefail

DROPIN_DIR=/etc/systemd/system/systemd-networkd-wait-online.service.d
DROPIN_PATH="$DROPIN_DIR/10-wlan-only.conf"

if ((EUID != 0)); then
  printf 'Run with sudo: sudo %q\n' "$0" >&2
  exit 2
fi

install -d -m 755 "$DROPIN_DIR"
cat >"$DROPIN_PATH" <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-networkd-wait-online --interface=wlan0 --ipv4
EOF

systemctl daemon-reload
systemctl restart systemd-networkd-wait-online.service

printf 'Network-online wait is now limited to wlan0 with IPv4.\n'
systemctl status systemd-networkd-wait-online.service --no-pager -l
