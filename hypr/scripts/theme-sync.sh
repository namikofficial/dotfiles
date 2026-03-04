#!/usr/bin/env sh
set -eu

wall="${1:-}"

# Stable accent per wallpaper path (hash-based pick).
palettes="#7aa2f7 #9ece6a #bb9af7 #2ac3de #e0af68 #f7768e"
if [ -n "$wall" ] && command -v cksum >/dev/null 2>&1; then
  idx="$(printf '%s' "$wall" | cksum | awk '{print $1 % 6 + 1}')"
else
  idx=1
fi
accent="$(printf '%s\n' $palettes | sed -n "${idx}p")"

cache_dir="$HOME/.cache/hypr"
mkdir -p "$cache_dir"
printf '%s\n' "$accent" >"$cache_dir/current-accent"

# Keep legacy fallback notifiers in sync if users run them manually.
sed -i "s/^frame_color = .*/frame_color = \"${accent}\"/" "$HOME/.config/dunst/dunstrc" 2>/dev/null || true
sed -i "0,/^frame_color = .*/s//frame_color = \"${accent}\"/" "$HOME/.config/dunst/dunstrc" 2>/dev/null || true
sed -i "s/border-color: #89b4fa;/border-color: ${accent};/" "$HOME/.config/wlogout/style.css" 2>/dev/null || true

# Refresh waybar colors if the bar is already running.
if pgrep -x waybar >/dev/null 2>&1; then
  pkill -USR2 -x waybar >/dev/null 2>&1 || true
fi
