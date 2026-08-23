#!/usr/bin/env sh
set -eu

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  exit 0
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$(readlink -f "$0")")" && pwd)
settingsctl="$script_dir/settingsctl"

auto_profile_enabled() {
  [ -x "$settingsctl" ] && [ "$("$settingsctl" get power.auto_profile 2>/dev/null || printf 'false')" = "true" ]
}

auto_profile_enabled || exit 0

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
  auto_profile_enabled || exit 0
  current="$(powerprofilesctl get 2>/dev/null || true)"
  if on_ac_power; then
    [ "$current" = "performance" ] || powerprofilesctl set performance >/dev/null 2>&1 || true
  else
    [ "$current" = "power-saver" ] || powerprofilesctl set power-saver >/dev/null 2>&1 || true
  fi
  sleep 30
done
