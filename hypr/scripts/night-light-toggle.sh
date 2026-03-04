#!/usr/bin/env sh
set -eu

temp="${HYPRSUNSET_TEMP:-4200}"

if pgrep -x hyprsunset >/dev/null 2>&1; then
  pkill -x hyprsunset || true
  if command -v swayosd-client >/dev/null 2>&1; then
    swayosd-client --custom-icon weather-clear-night-symbolic --custom-message "Night Light: Off" || true
  fi
  exit 0
fi

hyprsunset -t "$temp" >/dev/null 2>&1 &
sleep 0.1
if command -v swayosd-client >/dev/null 2>&1; then
  swayosd-client --custom-icon weather-clear-night-symbolic --custom-message "Night Light: ${temp}K" || true
fi
