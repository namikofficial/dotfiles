#!/usr/bin/env sh
set -eu

if ! command -v iwctl >/dev/null 2>&1; then
  exit 0
fi

wifi_if="$(iwctl station list 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '$1 ~ /^(wlan|wlp)/ { print $1; exit }')"
[ -n "$wifi_if" ] || exit 0
state="$(iwctl device "$wifi_if" show 2>/dev/null | awk -F: '/Powered/ { gsub(/[[:space:]]/, "", $2); print tolower($2); exit }')"
if [ "$state" = "on" ]; then
  iwctl device "$wifi_if" set-property Powered off >/dev/null 2>&1 || true
else
  iwctl device "$wifi_if" set-property Powered on >/dev/null 2>&1 || true
fi
