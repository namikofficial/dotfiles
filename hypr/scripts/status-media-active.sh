#!/usr/bin/env sh
set -eu

out="$("$HOME/.config/waybar/scripts/media.sh" 2>/dev/null || echo '')"
case "$out" in
  *idle*|*no\ player*|'') echo false ;;
  *) echo true ;;
esac
