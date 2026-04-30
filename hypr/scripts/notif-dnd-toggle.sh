#!/usr/bin/env bash
set -euo pipefail

if ! command -v wayle >/dev/null 2>&1; then
  exit 0
fi

wayle notify dnd >/dev/null 2>&1 || true
state="$(wayle notify status 2>/dev/null | awk -F': ' '/Do Not Disturb/ {print $2}' | tr '[:upper:]' '[:lower:]' || true)"

if command -v notify-send >/dev/null 2>&1; then
  case "$state" in
    on|enabled|true|1) notify-send -a Noxflow "Notifications" "DND enabled" ;;
    *) notify-send -a Noxflow "Notifications" "DND disabled" ;;
  esac
fi
