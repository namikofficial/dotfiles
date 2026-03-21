#!/usr/bin/env sh
set -eu

if ! command -v nmcli >/dev/null 2>&1; then
  echo false
  exit 0
fi

state="$(nmcli -t -f WIFI g 2>/dev/null || echo disabled)"
[ "$state" = "enabled" ] && echo true || echo false
