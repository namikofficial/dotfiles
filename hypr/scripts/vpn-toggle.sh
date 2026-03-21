#!/usr/bin/env sh
set -eu

if ! command -v nmcli >/dev/null 2>&1; then
  exit 0
fi

active="$(nmcli -t -f TYPE,NAME connection show --active 2>/dev/null | awk -F: '$1=="vpn" {print $2; exit}')"
if [ -n "$active" ]; then
  nmcli connection down "$active" >/dev/null 2>&1 || true
else
  if command -v nm-connection-editor >/dev/null 2>&1; then
    nm-connection-editor >/dev/null 2>&1 &
  fi
fi
