#!/usr/bin/env sh
set -eu

if ! command -v nmcli >/dev/null 2>&1; then
  exit 0
fi

state="$(nmcli -t -f WIFI g 2>/dev/null || echo disabled)"
if [ "$state" = "enabled" ]; then
  nmcli radio wifi off >/dev/null 2>&1 || true
else
  nmcli radio wifi on >/dev/null 2>&1 || true
fi
