#!/usr/bin/env sh
set -eu

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  exit 0
fi

on_ac_power() {
  for n in /sys/class/power_supply/*/online; do
    [ -r "$n" ] || continue
    if [ "$(cat "$n" 2>/dev/null || echo 0)" = "1" ]; then
      return 0
    fi
  done
  return 1
}

while :; do
  current="$(powerprofilesctl get 2>/dev/null || true)"
  if on_ac_power; then
    [ "$current" = "performance" ] || powerprofilesctl set performance >/dev/null 2>&1 || true
  else
    [ "$current" = "power-saver" ] || powerprofilesctl set power-saver >/dev/null 2>&1 || true
  fi
  sleep 30
done
