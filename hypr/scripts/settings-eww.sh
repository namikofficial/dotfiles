#!/usr/bin/env bash
set -euo pipefail

CFG="$HOME/.config/eww-settings"
if ! command -v eww >/dev/null 2>&1; then
  notify-send -a Settings "Eww not installed" "Install eww for the detailed settings panel."
  exit 1
fi

state="$(eww -c "$CFG" windows 2>/dev/null | rg -n 'settings_panel' || true)"
if [[ -n "$state" ]]; then
  eww -c "$CFG" close settings_panel
  exit 0
fi

eww -c "$CFG" daemon >/dev/null 2>&1 || true
eww -c "$CFG" open settings_panel
