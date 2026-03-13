#!/usr/bin/env sh
set -eu

# Minimal safe startup for debugging session crashes.
command -v dbus-update-activation-environment >/dev/null 2>&1 && \
  dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP >/dev/null 2>&1 || true

for app in waybar nm-applet blueman-applet; do
  if command -v "$app" >/dev/null 2>&1 && ! pgrep -x "$app" >/dev/null 2>&1; then
    "$app" >/dev/null 2>&1 &
  fi
done

# Prefer hyprpolkitagent if installed.
if [ -x /usr/lib/hyprpolkitagent/hyprpolkitagent ] && ! pgrep -x hyprpolkitagent >/dev/null 2>&1; then
  /usr/lib/hyprpolkitagent/hyprpolkitagent >/dev/null 2>&1 &
fi
