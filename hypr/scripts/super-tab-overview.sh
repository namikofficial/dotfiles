#!/usr/bin/env bash
set -euo pipefail

notify() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Overview" "$1" "${2:-}"
}

if hyprctl plugin list 2>/dev/null | grep -qi 'hyprexpo'; then
  if hyprctl dispatch hyprexpo:expo toggle >/dev/null 2>&1; then
    exit 0
  fi
fi

if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  exec "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi

notify "Overview unavailable" "No hyprexpo plugin or workspace overview fallback is available."
exit 1
