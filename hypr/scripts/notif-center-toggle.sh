#!/usr/bin/env bash
set -euo pipefail

cfg="$HOME/.config/eww"
win="notif_center"
backdrop="notif_backdrop"

command -v eww >/dev/null 2>&1 || exit 0
[ -f "$cfg/eww.yuck" ] || exit 0

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
