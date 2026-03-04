#!/usr/bin/env sh
set -eu

out="$("$HOME/.config/waybar/scripts/gpu.sh" 2>/dev/null || echo '')"
case "$out" in
  *active*|*%*) echo true ;;
  *) echo false ;;
esac
