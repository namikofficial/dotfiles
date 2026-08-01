#!/usr/bin/env sh
set -eu

if ! command -v iwctl >/dev/null 2>&1; then
  echo false
  exit 0
fi

wifi_if="$(iwctl station list 2>/dev/null | sed $'s/\033\\[[0-9;]*m//g' | awk '$1 ~ /^(wlan|wlp)/ { print $1; exit }')"
[ -n "$wifi_if" ] || {
  echo false
  exit
}
iwctl device "$wifi_if" show 2>/dev/null | awk -F: '/Powered/ { gsub(/[[:space:]]/, "", $2); print tolower($2) == "on" ? "true" : "false"; found=1; exit } END { if (!found) print "false" }'
