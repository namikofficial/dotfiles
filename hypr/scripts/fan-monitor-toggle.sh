#!/usr/bin/env bash
set -euo pipefail

if command -v rofi >/dev/null 2>&1; then
  choice="$(printf '%s\n' on off status | rofi -dmenu -i -p 'Fan Monitor' -theme "$HOME/.config/rofi/actions.rasi")"
  case "$choice" in
    on) notify-send -a Fan 'Fan monitor' 'Enable the monitor widget or script here' 2>/dev/null || true ;;
    off) notify-send -a Fan 'Fan monitor' 'Disable the monitor widget or script here' 2>/dev/null || true ;;
    status) notify-send -a Fan 'Fan monitor' 'No dedicated fan monitor backend is wired yet' 2>/dev/null || true ;;
  esac
  exit 0
fi

notify-send -a Fan 'Fan monitor' 'No rofi backend available' 2>/dev/null || true
