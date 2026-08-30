#!/usr/bin/env bash
set -euo pipefail

# Workspace overview shortcut (Super+Tab) — fallback only.
# Used by hypr/conf/95-plugins.lua when the scroll-overview plugin is NOT
# loaded (e.g. before a rebuild after a Hyprland upgrade). The primary path is
# the plugin itself: SUPER+TAB → hl.plugin.scrolloverview.overview("toggle").
# The NoxFlow QML overview was removed 2026-07-31 (shell-redesign M10).

ntfy() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Overview" "$1" "${2:-}" >/dev/null 2>&1 || true
}

# Keep this script intentionally narrow: Super+Tab is a workspace/window
# overview, never an AI goal-mode or model switch. The primary scrolloverview
# binding lives in 95-plugins.lua; this path is used only when that plugin is
# unavailable or fails to load.

# 1. Try the hyprexpo plugin if present
if hyprctl plugin list 2>/dev/null | grep -qi 'hyprexpo'; then
  if hyprctl dispatch hyprexpo:expo toggle >/dev/null 2>&1; then
    exit 0
  fi
fi

# 2. Fall back to the legacy workspace script
if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  exec "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi

ntfy "Overview unavailable" "Install/rebuild hyprland-scroll-overview (see setup/scrolloverview-rebuild.sh)."
exit 1
