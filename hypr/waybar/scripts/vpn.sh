#!/usr/bin/env sh
set -eu

if ! command -v nmcli >/dev/null 2>&1; then
  echo "󰦞"
  exit 0
fi

vpn_name="$(nmcli -t -f TYPE,NAME connection show --active 2>/dev/null | awk -F: '$1=="vpn" {print $2; exit}')"
if [ -n "$vpn_name" ]; then
  printf '󰖂 %s\n' "$vpn_name"
else
  echo "󰦞"
fi
