#!/usr/bin/env sh
set -eu

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  command -v notify-send >/dev/null 2>&1 && notify-send -a Power "Power profile" "powerprofilesctl unavailable" || true
  exit 0
fi

current="$(powerprofilesctl get 2>/dev/null || true)"
if [ -z "$current" ]; then
  command -v notify-send >/dev/null 2>&1 && notify-send -a Power "Power profile" "Service disabled by system config" || true
  exit 0
fi
case "$current" in
  power-saver) next="balanced" ;;
  balanced) next="performance" ;;
  performance) next="power-saver" ;;
  *) next="balanced" ;;
esac

powerprofilesctl set "$next" >/dev/null 2>&1 || true
command -v notify-send >/dev/null 2>&1 && notify-send -a Power "Profile" "$next" || true
