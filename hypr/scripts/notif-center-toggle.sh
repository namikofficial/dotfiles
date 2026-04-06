#!/usr/bin/env bash
set -euo pipefail

if command -v swaync-client >/dev/null 2>&1; then
  swaync-client -sw -t >/dev/null 2>&1 || true
  exit 0
fi

cfg="$HOME/.config/eww"
win="notif_center"
backdrop="notif_backdrop"

eww --config "$cfg" daemon >/dev/null 2>&1 || true
eww --config "$cfg" reload >/dev/null 2>&1 || true

if eww --config "$cfg" active-windows 2>/dev/null | grep -Eq "^${win}:"; then
  eww --config "$cfg" close "$win" >/dev/null 2>&1 || true
  eww --config "$cfg" close "$backdrop" >/dev/null 2>&1 || true
  command -v hyprctl >/dev/null 2>&1 && hyprctl dispatch submap reset >/dev/null 2>&1 || true
else
  eww --config "$cfg" open-many "$backdrop" "$win"
  command -v hyprctl >/dev/null 2>&1 && hyprctl dispatch submap notifpanel >/dev/null 2>&1 || true
fi
