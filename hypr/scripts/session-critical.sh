#!/usr/bin/env sh
set -eu

# UWSM owns the session. Finalize its environment before optional UI starts.
if command -v uwsm >/dev/null 2>&1; then
  uwsm finalize
else
  dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE
fi

systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
systemctl --user start xdg-desktop-portal-hyprland.service 2>/dev/null || true

if command -v hyprpolkitagent >/dev/null 2>&1 && ! pgrep -x hyprpolkitagent >/dev/null 2>&1; then
  hyprpolkitagent >/dev/null 2>&1 &
elif [ -x /usr/lib/hyprpolkitagent/hyprpolkitagent ] && ! pgrep -x hyprpolkitagent >/dev/null 2>&1; then
  /usr/lib/hyprpolkitagent/hyprpolkitagent >/dev/null 2>&1 &
fi

# Cosmetic and developer conveniences can fail without affecting Hyprland.
if ! systemctl --user start noxflow-session-optional.service 2>/dev/null; then
  "$HOME/.config/hypr/scripts/startup.sh" >/dev/null 2>&1 &
fi
