#!/usr/bin/env sh
set -eu

wall=""
if [ -f "$HOME/.cache/current-wallpaper" ]; then
  wall="$(cat "$HOME/.cache/current-wallpaper" 2>/dev/null || true)"
fi

if [ -x "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" ]; then
  if [ -n "$wall" ] && [ -f "$wall" ]; then
    "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" "$wall" || true
  else
    "$HOME/.config/hypr/scripts/sync-lock-wallpaper.sh" || true
  fi
fi

# Keep lock colors in sync with latest wallpaper before launching hyprlock.
if [ -x "$HOME/.config/hypr/scripts/theme-sync.sh" ] && [ -n "$wall" ] && [ -f "$wall" ]; then
  timeout 3 "$HOME/.config/hypr/scripts/theme-sync.sh" "$wall" >/dev/null 2>&1 || true
fi

if command -v hyprlock >/dev/null 2>&1; then
  # Render immediately to avoid a perceived blank frame while preserving
  # hyprlock's default fade-in for a smoother lock transition.
  exec hyprlock --immediate-render --grace 2
fi

if command -v swaylock >/dev/null 2>&1; then
  exec swaylock -f
fi

exec loginctl lock-session
