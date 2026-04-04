#!/usr/bin/env sh
set -eu

if [ -x "$HOME/.config/hypr/scripts/notif-peek.sh" ]; then
  state="$("$HOME/.config/hypr/scripts/notif-peek.sh" dnd 2>/dev/null || echo OFF)"
  case "$state" in
    ON|on|true|1) echo true ;;
    *) echo false ;;
  esac
else
  state="$(swaync-client -sw -D 2>/dev/null || echo false)"
  case "$state" in
    true|1|on|enabled) echo true ;;
    *) echo false ;;
  esac
fi
