#!/usr/bin/env sh
set -eu

if [ -x "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" ]; then
  "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" || true
fi

if command -v hyprlock >/dev/null 2>&1; then
  exec hyprlock
fi

if command -v swaylock >/dev/null 2>&1; then
  exec swaylock -f
fi

exec loginctl lock-session
