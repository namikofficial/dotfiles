#!/usr/bin/env sh
# theme-hooks.d/60-hyprland-accent.sh
# Immediately applies wallpaper-derived accent colours to Hyprland border
# decorations without waiting for a full hyprctl reload.
# Called by theme-sync.sh with THEME_* env vars already set.
set -eu

command -v hyprctl >/dev/null 2>&1 || exit 0
# Only run inside a live Hyprland session.
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || exit 0

accent="${THEME_ACCENT:-#6f94c9}"
accent2="${THEME_ACCENT2:-#66c2b8}"
surface="${THEME_SURFACE:-#20263a}"

a1="${accent#\#}"
a2="${accent2#\#}"
sf="${surface#\#}"

hyprctl keyword general:col.active_border   "rgba(${a1}ff) rgba(${a2}ff) 45deg" >/dev/null 2>&1 || true
hyprctl keyword general:col.inactive_border "rgba(${sf}cc)"                       >/dev/null 2>&1 || true
