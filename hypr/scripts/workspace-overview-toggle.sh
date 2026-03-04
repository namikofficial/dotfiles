#!/usr/bin/env sh
set -eu

if hyprctl plugin list 2>/dev/null | grep -q 'Plugin hyprexpo'; then
  hyprctl dispatch hyprexpo:expo toggle >/dev/null 2>&1 || true
  exit 0
fi

if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi
