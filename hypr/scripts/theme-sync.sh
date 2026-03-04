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
accent="$(printf '%s\n' "$palettes" | tr ' ' '\n' | sed -n "${idx}p")"

cache_dir="$HOME/.cache/hypr"
mkdir -p "$cache_dir"
printf '%s\n' "$accent" >"$cache_dir/current-accent"

# Avoid mutating tracked dotfiles. Keep accent in cache only.

# Refresh waybar colors if the bar is already running.
if pgrep -x waybar >/dev/null 2>&1; then
  pkill -USR2 -x waybar >/dev/null 2>&1 || true
fi
