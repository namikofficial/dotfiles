#!/usr/bin/env sh
set -eu

if ! command -v nmcli >/dev/null 2>&1; then
  echo false
  exit 0
fi

active="$(nmcli -t -f TYPE,NAME connection show --active 2>/dev/null | awk -F: '$1=="vpn" {print $2; exit}')"
[ -n "$active" ] && echo true || echo false
