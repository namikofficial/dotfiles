#!/usr/bin/env sh
set -eu

HYPRCTL="${HYPRCTL_BIN:-$(command -v hyprctl || true)}"
PLUGIN_SO="${XDG_DATA_HOME:-$HOME/.local/share}/hypr/plugins/hyprexpo/hyprexpo.so"

loaded_expo_path() {
  pid="$(pgrep -x Hyprland 2>/dev/null | head -n1 || true)"
  [ -n "$pid" ] || return 1
  awk '/\/.*hyprexpo\.so$/ { print $NF; exit }' "/proc/$pid/maps" 2>/dev/null
}

toggle_expo() {
  [ -n "$HYPRCTL" ] || return 1
  "$HYPRCTL" dispatch hyprexpo:expo toggle >/dev/null 2>&1
}

load_expo_if_available() {
  [ -n "$HYPRCTL" ] || return 1
  [ -f "$PLUGIN_SO" ] || return 1

  current_path="$(loaded_expo_path || true)"
  if [ -n "$current_path" ] && [ "$current_path" != "$PLUGIN_SO" ]; then
    "$HYPRCTL" plugin unload "$current_path" >/dev/null 2>&1 || true
    sleep 0.15
  fi

  if [ "$current_path" = "$PLUGIN_SO" ] && "$HYPRCTL" plugin list 2>/dev/null | grep -q 'Plugin hyprexpo'; then
    return 0
  fi

  "$HYPRCTL" plugin load "$PLUGIN_SO" >/dev/null 2>&1 || return 1
  sleep 0.15
}

# Prefer Mission Control view. If the plugin is installed but not yet loaded in
# this session, or a stale temp build is mapped, normalize to the stable plugin
# path before falling back to the Rofi workspace hub.
current_path="$(loaded_expo_path || true)"
if [ "$current_path" = "$PLUGIN_SO" ] && toggle_expo; then
  exit 0
fi

if load_expo_if_available && toggle_expo; then
  exit 0
fi

if [ -x "$HOME/.config/hypr/scripts/workspace-overview.sh" ]; then
  "$HOME/.config/hypr/scripts/workspace-overview.sh"
fi
