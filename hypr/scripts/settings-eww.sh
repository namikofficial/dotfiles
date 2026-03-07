#!/usr/bin/env bash
set -euo pipefail

CFG="$HOME/.config/eww-settings"
WIN="settings_panel"

if ! command -v eww >/dev/null 2>&1; then
  notify-send -a Settings "Eww not installed" "Install eww for the detailed settings panel."
  exit 1
fi

is_open() {
  eww -c "$CFG" active-windows 2>/dev/null | rg -q ": $WIN$"
}

if is_open; then
  eww -c "$CFG" close "$WIN" >/dev/null 2>&1 || true
  exit 0
fi

eww -c "$CFG" daemon >/dev/null 2>&1 || true
eww -c "$CFG" reload >/dev/null 2>&1 || true
sleep 0.08
eww -c "$CFG" open "$WIN"
