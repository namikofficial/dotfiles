#!/usr/bin/env sh
set -eu

# Try Mission Control view first, then fallback to Rofi overview.
if hyprctl dispatch hyprexpo:expo toggle >/dev/null 2>&1; then
  exit 0
fi

if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi
