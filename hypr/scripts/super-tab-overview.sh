#!/usr/bin/env bash
set -euo pipefail

# Canonical workspace overview shortcut (Super+Tab).
# Delegates to the NoxFlow QML overview when the shell is running,
# falls back to hyprexpo plugin, then the legacy workspace-overview script.

ntfy() {
  command -v notify-send >/dev/null 2>&1 || return 0
  notify-send -a "Overview" "$1" "${2:-}" >/dev/null 2>&1 || true
}

# 1. Try the NoxFlow QML overview via IPC
if systemctl --user is-active --quiet noxflow-shell 2>/dev/null; then
  if quickshell ipc -p "$HOME/.config/noxflow/shell/shell.qml" call noxctl toggleOverview 2>/dev/null; then
    exit 0
  fi
fi

# 2. Fall back to hyprexpo plugin
if hyprctl plugin list 2>/dev/null | grep -qi 'hyprexpo'; then
  if hyprctl dispatch hyprexpo:expo toggle >/dev/null 2>&1; then
    exit 0
  fi
fi

# 3. Fall back to legacy workspace script
if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  exec "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi

ntfy "Overview unavailable" "No NoxFlow shell, hyprexpo, or fallback available."
exit 1
